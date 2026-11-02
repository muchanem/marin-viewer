// Subsystem pages (DESIGN.md sections 6 and 8): one page per package under `lib/`, with its layered
// description and its map for the strip's "In Marin" card. `npm run system-pages` writes all of them;
// the poller refreshes one at the end of a tick when a file's `l1` in the package changed.
//
// A page is written in four calls: the writer drafts it from the package's inputs, a cold reader
// lists the claims it cannot check against those inputs, the writer rewrites once for the gaps, the
// lint hits and the map's problems, and the cold reader reads the result again. Lint hits left after
// the rewrite go into `lint:`. A map that still fails its checks is dropped, with the reason in `lint:`.

import { readdir } from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { lint } from "../lint.js";
import { Diagram } from "../protocol.js";
import { readEntry, saveEntry, systemEntryPath, type Entry } from "../wordbase.js";
import type { Backend, CompleteOptions, Completion, Turn } from "./backends.js";
import { extractJson } from "./describe.js";
import { inputBlock, renderPrompt } from "./prompts.js";
import { importGraph, isTestPath, packageName, signatures, type ImportGraph, type MarinRepo } from "./repo.js";
import { countTokens, type TokenCounter } from "./tokens.js";
import { parseGaps, type Gap } from "./prepare.js";

export const SYSTEM_BUDGET = 256_000;
/** The map's limits: the preparation prompt's 10 boxes, and the card's 4 by 3 grid. */
export const MAX_BOXES = 10;
export const MAX_COLS = 4;
export const MAX_ROWS = 3;
/** An entry point longer than this is given as its definition lines. */
export const EXCERPT_FULL_MAX = 12_000;

const SystemOut = z.object({
  l1: z.string().min(1),
  l2: z.string().min(1).optional(),
  l3: z.array(z.string().min(1)).optional(),
  diagram: z.unknown().optional(),
});
export interface SystemPageOut {
  l1: string;
  l2?: string;
  l3?: string[];
  diagram?: unknown;
}

/** Marin packages a package depends on, read from `lib/<pkg>/pyproject.toml`'s dependency lists. */
export function workspaceDeps(pyproject: string, packages: string[]): string[] {
  const norm = (s: string) => s.toLowerCase().replace(/[-_.]+/g, "-");
  const known = new Map(packages.map((p) => [norm(p), p]));
  const out = new Set<string>();
  // Every quoted requirement string in the file: `"marin-rigging>=0.1"`, `"iris"`.
  for (const m of pyproject.matchAll(/["']([A-Za-z0-9][A-Za-z0-9._-]*)\s*(?:\[[^\]]*\])?\s*(?:[<>=!~;@ ]|["'])/g)) {
    const name = norm(m[1]!);
    for (const candidate of [name, name.replace(/^marin-/, "")]) {
      const pkg = known.get(candidate);
      if (pkg) out.add(pkg);
    }
  }
  return [...out].sort();
}

export type DepGraph = Map<string, { uses: string[]; used_by: string[] }>;

export async function dependencyGraph(repo: MarinRepo, commit: string): Promise<DepGraph> {
  const files = await repo.lsTree(commit, "lib/");
  const packages = [...new Set(files.map((f) => f.split("/")[1]!).filter(Boolean))];
  const uses = new Map<string, string[]>();
  for (const p of packages) {
    const text = (await repo.show(commit, `lib/${p}/pyproject.toml`)) ?? "";
    uses.set(p, workspaceDeps(text, packages).filter((d) => d !== p));
  }
  const graph: DepGraph = new Map();
  for (const p of packages) graph.set(p, { uses: uses.get(p) ?? [], used_by: packages.filter((q) => uses.get(q)?.includes(p)).sort() });
  return graph;
}

/**
 * Packages in waves: a package comes after every package it uses, so its neighbours' `l1`s from this
 * run are ready for it. Throws on a dependency cycle.
 */
export function dependencyWaves(graph: DepGraph, names: string[]): string[][] {
  const left = new Set(names);
  const done = new Set([...graph.keys()].filter((p) => !left.has(p)));
  const waves: string[][] = [];
  while (left.size) {
    const wave = [...left].filter((p) => (graph.get(p)?.uses ?? []).every((u) => done.has(u) || !graph.has(u))).sort();
    if (!wave.length) throw new Error(`dependency cycle among ${[...left].sort().join(", ")}`);
    for (const p of wave) {
      left.delete(p);
      done.add(p);
    }
    waves.push(wave);
  }
  return waves;
}

export async function fileEntries(wordbase: string, pkg: string): Promise<Map<string, Entry>> {
  const root = path.join(wordbase, "lib", pkg);
  const out = new Map<string, Entry>();
  let names: string[];
  try {
    names = (await readdir(root, { recursive: true })) as string[];
  } catch {
    return out;
  }
  for (const n of names.filter((x) => x.endsWith(".py.md")).sort()) {
    const e = await readEntry(path.join(root, n)).catch(() => null);
    if (e && !e.front.deleted && e.front.kind === "file") out.set(`lib/${pkg}/${n.replace(/\.md$/, "")}`, e);
  }
  return out;
}

/** The README's first prose paragraph, skipping headings, badges, HTML and code. */
export function readmeOpening(readme: string, max = 600): string | null {
  let inCode = false;
  const paras: string[] = [];
  let cur: string[] = [];
  for (const raw of readme.split("\n")) {
    const line = raw.trim();
    if (line.startsWith("```")) {
      inCode = !inCode;
      continue;
    }
    if (inCode) continue;
    if (!line) {
      if (cur.length) paras.push(cur.join(" "));
      cur = [];
      continue;
    }
    if (/^(#|<|!\[|\[!\[|\||-{3,}|={3,})/.test(line)) {
      if (cur.length) paras.push(cur.join(" "));
      cur = [];
      continue;
    }
    cur.push(line);
  }
  if (cur.length) paras.push(cur.join(" "));
  const p = paras.find((x) => x.length >= 40 && !/^[-*] /.test(x));
  if (!p) return null;
  return p.length > max ? `${p.slice(0, max).replace(/\s+\S*$/, "")} ...` : p;
}

export interface Neighbour {
  name: string;
  relation: "uses" | "used_by";
  l1: string | null;
  /** Where the sentence came from: "its subsystem page", "the opening of its README", ... */
  from: string;
}

export interface SystemInputs {
  system: string;
  commit: string;
  uses: string[];
  used_by: string[];
  /** The rendered input blocks, in prompt order. */
  inputs: string;
  /** Every source and test path the page may name, and the directories that hold them. */
  paths: Set<string>;
  stats: {
    tokens: number;
    budget: number;
    files: number;
    filesWithL2: number;
    l2Dropped: number;
    tests: number;
    testsDropped: number;
    readmeTokens: number;
    readmeCut: boolean;
    excerpts: { path: string; tokens: number; full: boolean }[];
    excerptsDropped: string[];
    neighbours: number;
  };
  leftOut: string[];
}

export interface InputOptions {
  repo: MarinRepo;
  commit: string;
  wordbase: string;
  prompts: string;
  system: string;
  graph: DepGraph;
  /** The whole-checkout import graph, for ranking entry points by importers outside the package. */
  imports: ImportGraph;
  neighbourL1: (name: string) => Promise<{ l1: string | null; from: string }>;
  budget?: number;
  /** A cap on the excerpts' share of the budget. */
  excerptBudget?: number;
  /** A file above this many tokens is given as its definition lines; `EXCERPT_FULL_MAX` by default. */
  excerptFullMax?: number;
  /** The current page's layers, for the poller's refresh; the full run starts fresh. */
  existing?: string | null;
  count?: TokenCounter;
}

/** Modules a `pyproject.toml` names under `[project.scripts]`, as `module.path`. */
export function scriptModules(pyproject: string): string[] {
  const m = /^\[project\.scripts\]\s*$([\s\S]*?)(?=^\[|(?![\s\S]))/m.exec(pyproject);
  if (!m) return [];
  return [...m[1]!.matchAll(/=\s*["']([A-Za-z0-9_.]+)(?::[A-Za-z0-9_.]+)?["']/g)].map((x) => x[1]!);
}

/**
 * The package's main entry points, best first: its top-level `__init__.py`, the modules its
 * `pyproject.toml` names as scripts, `__main__.py`/`cli.py`/`main.py`, then the modules with the most
 * importers outside the package.
 */
export function entryPoints(system: string, source: string[], imports: ImportGraph, pyproject: string): string[] {
  const set = new Set(source);
  const out: string[] = [];
  const add = (p: string | undefined) => {
    if (p && set.has(p) && !out.includes(p)) out.push(p);
  };
  const tops = source.filter((p) => /^lib\/[^/]+\/(src\/)?[^/]+\/__init__\.py$/.test(p)).sort((a, b) => a.length - b.length);
  for (const t of tops) add(t);
  for (const mod of scriptModules(pyproject)) add(imports.index.path(mod, `lib/${system}/x.py`));
  for (const p of source.filter((x) => /\/(__main__|cli|main)\.py$/.test(x)).sort()) add(p);
  const outside = (p: string) => [...(imports.importers.get(p) ?? [])].filter((q) => packageName(q) !== system || !q.startsWith("lib/")).length;
  const ranked = source
    .map((p) => ({ p, n: outside(p) }))
    .filter((x) => x.n > 0)
    .sort((a, b) => b.n - a.n || a.p.localeCompare(b.p));
  for (const r of ranked) add(r.p);
  return out;
}

export async function systemInputs(o: InputOptions): Promise<SystemInputs> {
  const count = o.count ?? countTokens;
  const budget = o.budget ?? SYSTEM_BUDGET;
  const { repo, commit, system } = o;
  const g = o.graph.get(system) ?? { uses: [], used_by: [] };
  const files = (await repo.lsTree(commit, `lib/${system}/`)).filter((f) => f.endsWith(".py"));
  const entries = await fileEntries(o.wordbase, system);
  const source = files.filter((f) => !isTestPath(f) && entries.get(f)?.front.test !== true);
  const tests = files.filter((f) => !source.includes(f));
  const paths = new Set<string>();
  for (const f of files) {
    paths.add(f);
    const parts = f.split("/");
    for (let i = 2; i < parts.length; i++) paths.add(`${parts.slice(0, i).join("/")}/`);
  }

  const template = await renderPrompt(o.prompts, "describe-system.md", { system, commit });
  let room = budget - count(template) - 2_000; // the block markers, the left-out list
  const leftOut: string[] = [];

  // Neighbours are a few hundred tokens; their room is set aside before anything else.
  const neighbours: Neighbour[] = [];
  for (const [relation, list] of [["uses", g.uses], ["used_by", g.used_by]] as const)
    for (const name of list) neighbours.push({ name, relation, ...(await o.neighbourL1(name)) });
  const neighbourText = neighbours.length
    ? neighbours.map((n) => `- ${n.name} (${n.relation === "uses" ? `${system} uses it` : `it uses ${system}`}): ${n.l1 ?? "no description"} [${n.from}]`).join("\n")
    : "none";
  room -= count(neighbourText);
  const existing = o.existing ?? "none";
  room -= count(existing);

  // 1. Source entries: every l1, then l2s while they fit.
  const l1Lines = source.map((f) => {
    const e = entries.get(f);
    return { f, l1: e?.front.l1 ? String(e.front.l1) : null, l2: e?.front.l2 ? String(e.front.l2) : null };
  });
  const noEntry = l1Lines.filter((x) => !x.l1).map((x) => x.f);
  const l1Text = l1Lines.map((x) => `- ${x.f}: ${x.l1 ?? "(no entry)"}`);
  room -= count(l1Text.join("\n"));
  const withL2 = new Set<string>();
  let l2Dropped = 0;
  for (const x of l1Lines) {
    if (!x.l2) continue;
    const t = count(x.l2) + 4;
    if (t <= room) {
      withL2.add(x.f);
      room -= t;
    } else l2Dropped++;
  }
  if (l2Dropped) leftOut.push(`the l2 paragraphs of ${l2Dropped} source files`);
  if (noEntry.length) leftOut.push(`entries for ${noEntry.length} source files that have none: ${noEntry.slice(0, 20).join(", ")}${noEntry.length > 20 ? ", ..." : ""}`);
  const filesText = l1Lines.map((x) => `- ${x.f}: ${x.l1 ?? "(no entry)"}${withL2.has(x.f) ? `\n  ${x.l2}` : ""}`).join("\n") || "none";

  // 2. Test l1s.
  const testLines: string[] = [];
  let testsDropped = 0;
  for (const t of tests) {
    const e = entries.get(t);
    const line = `- ${t}: ${e?.front.l1 ? String(e.front.l1) : "(no entry)"}`;
    const n = count(line) + 1;
    if (n <= room) {
      testLines.push(line);
      room -= n;
    } else testsDropped++;
  }
  if (testsDropped) leftOut.push(`the l1 lines of ${testsDropped} test files`);

  // 3. README, in full when it fits.
  let readme = (await repo.show(commit, `lib/${system}/README.md`)) ?? "none";
  let readmeTokens = count(readme);
  let readmeCut = false;
  if (readmeTokens > room) {
    const keep = Math.max(0, Math.floor((readme.length * room) / readmeTokens) - 200);
    readme = `${readme.slice(0, keep)}\n... (cut: the README did not fit)`;
    readmeCut = true;
    leftOut.push(`the README after its first ${keep} characters`);
    readmeTokens = count(readme);
  }
  room -= readmeTokens;

  // 4. Entry-point excerpts, within the excerpt cap.
  let excerptRoom = Math.min(room, o.excerptBudget ?? Infinity);
  const pyproject = (await repo.show(commit, `lib/${system}/pyproject.toml`)) ?? "";
  const excerpts: { path: string; tokens: number; full: boolean; text: string }[] = [];
  const excerptsDropped: string[] = [];
  for (const p of entryPoints(system, source, o.imports, pyproject)) {
    const text = (await repo.show(commit, p)) ?? "";
    if (!text.trim()) continue;
    let body = text;
    let full = true;
    let n = count(body);
    if (n > (o.excerptFullMax ?? EXCERPT_FULL_MAX)) {
      body = signatures(text, 200).join("\n");
      full = false;
      n = count(body);
    }
    n += 30;
    if (n <= excerptRoom) {
      excerpts.push({ path: p, tokens: n, full, text: body });
      excerptRoom -= n;
      room -= n;
    } else excerptsDropped.push(p);
  }
  if (excerptsDropped.length) leftOut.push(`excerpts of ${excerptsDropped.length} more entry points: ${excerptsDropped.slice(0, 20).join(", ")}${excerptsDropped.length > 20 ? ", ..." : ""}`);
  const excerptText = excerpts.map((x) => `--- ${x.path}${x.full ? "" : " (definition lines only)"}\n${x.text.trimEnd()}`).join("\n\n") || "none";

  const inputs = [
    inputBlock("FILES", filesText),
    inputBlock("TESTS", testLines.join("\n") || "none"),
    inputBlock("README", readme),
    inputBlock("EXCERPTS", excerptText),
    inputBlock("NEIGHBOURS", neighbourText),
    inputBlock("LEFT OUT", leftOut.map((l) => `- ${l}`).join("\n") || "none"),
    inputBlock("EXISTING", existing),
  ].join("\n");
  return {
    system,
    commit,
    uses: g.uses,
    used_by: g.used_by,
    inputs,
    paths,
    stats: {
      tokens: count(template) + count(inputs),
      budget,
      files: source.length,
      filesWithL2: withL2.size,
      l2Dropped,
      tests: tests.length,
      testsDropped,
      readmeTokens,
      readmeCut,
      excerpts: excerpts.map(({ path: p, tokens, full }) => ({ path: p, tokens, full })),
      excerptsDropped,
      neighbours: neighbours.length,
    },
    leftOut,
  };
}

export function describeSystemStats(s: SystemInputs["stats"]): string {
  return `${s.tokens} tokens of ${s.budget}: ${s.files} source entries (${s.filesWithL2} with l2${s.l2Dropped ? `, ${s.l2Dropped} l2 left out` : ""}), ${s.tests - s.testsDropped} of ${s.tests} test l1s, README ${s.readmeTokens} tokens${s.readmeCut ? " (cut)" : ""}, ${s.excerpts.length} excerpts (${s.excerpts.filter((e) => !e.full).length} as definitions; ${s.excerptsDropped.length} left out), ${s.neighbours} neighbours`;
}

const SENTENCE_BREAK = /(?<!\be\.g)(?<!\bi\.e)[.!?]\s+[A-Z`]/;

export function lintPage(o: SystemPageOut): string[] {
  const fields: [string, string][] = [["l1", o.l1], ...(o.l2 ? [["l2", o.l2] as [string, string]] : []), ...(o.l3 ?? []).map((t, i): [string, string] => [`l3[${i}]`, t])];
  return fields.flatMap(([f, t]) => lint(t).map((h) => `${f}: ${h.rule} "${h.match}"`));
}

/** The checks `check_fixture.py` makes on a system entry's layers and map, plus the card's grid limits. */
export function checkPage(o: SystemPageOut, ctx: { system: string; uses: string[]; used_by: string[]; paths: Set<string>; requireDiagram?: boolean }): string[] {
  const problems: string[] = [];
  if (SENTENCE_BREAK.test(o.l1)) problems.push("l1: must be a single sentence");
  if (o.diagram === undefined) {
    if (ctx.requireDiagram) problems.push(`diagram: the reply has no "diagram" object; every page needs the map that the Map section describes`);
    return problems;
  }
  const parsed = Diagram.safeParse(o.diagram);
  if (!parsed.success) {
    problems.push(...parsed.error.issues.slice(0, 8).map((i) => `diagram: ${i.path.join(".") || "(root)"}: ${i.message}`));
    return problems;
  }
  const d = parsed.data;
  if (d.nodes.length > MAX_BOXES) problems.push(`diagram: ${d.nodes.length} boxes, more than ${MAX_BOXES}`);
  if (d.layout?.mode !== "grid") problems.push(`diagram: layout must be {"mode": "grid"}`);
  const ids = new Set<string>();
  const cells = new Map<string, string>();
  let cols = 0;
  let rows = 0;
  const neighbours = new Set([...ctx.uses, ...ctx.used_by]);
  const covered = new Set<string>();
  for (const n of d.nodes) {
    if (ids.has(n.id)) problems.push(`diagram: duplicate box id ${n.id}`);
    ids.add(n.id);
    covered.add(n.id);
    const words = (t: string) => t.trim().split(/\s+/).filter(Boolean).length;
    if (!n.sub) problems.push(`diagram: box ${n.id} has no sub`);
    else if (words(n.sub) > 5) problems.push(`diagram: box ${n.id} has a sub of ${words(n.sub)} words; give it one to four`);
    if (words(n.label) > 3) problems.push(`diagram: box ${n.id} has a label of ${words(n.label)} words; give it one to three`);
    if (!n.paths?.length) problems.push(`diagram: box ${n.id} names no paths`);
    if (n.id === ctx.system && !n.paths?.includes(`lib/${ctx.system}/`)) problems.push(`diagram: box ${n.id} stands for the package; give it the path lib/${ctx.system}/`);
    if (neighbours.has(n.id) && !n.paths?.includes(`lib/${n.id}/`)) problems.push(`diagram: box ${n.id} stands for that package; give it the path lib/${n.id}/`);
    for (const s of n.systems ?? []) if (!n.paths?.includes(`lib/${s}/`)) problems.push(`diagram: box ${n.id} lists ${s}; add the path lib/${s}/`);
    if (n.systems?.length === 1) problems.push(`diagram: box ${n.id} stands for the one package ${n.systems[0]}; give it the id ${n.systems[0]} and drop systems`);
    for (const s of n.systems ?? []) {
      if (!neighbours.has(s)) problems.push(`diagram: box ${n.id} lists ${s} under systems, which is not a neighbour of ${ctx.system}`);
      covered.add(s);
    }
    for (const p of n.paths ?? []) if (!ctx.paths.has(p) && !/^lib\/[^/]+\/$/.test(p)) problems.push(`diagram: box ${n.id} names path ${p}, which is not in the package at this commit`);
    for (const p of n.paths ?? []) {
      const m = /^lib\/([^/]+)\/$/.exec(p);
      if (m && m[1] !== ctx.system && !neighbours.has(m[1]!)) problems.push(`diagram: box ${n.id} names ${p}, which is not this package or a neighbour`);
    }
    if (n.grid) {
      const span = n.grid.span ?? 1;
      for (let c = n.grid.col; c < n.grid.col + span; c++) {
        const k = `${n.grid.row},${c}`;
        if (cells.has(k)) problems.push(`diagram: box ${n.id} takes row ${n.grid.row} col ${c}, already taken by ${cells.get(k)}`);
        cells.set(k, n.id);
      }
      cols = Math.max(cols, n.grid.col + span);
      rows = Math.max(rows, n.grid.row + 1);
    }
  }
  if (cols > MAX_COLS || rows > MAX_ROWS) problems.push(`diagram: grid is ${cols} columns by ${rows} rows; the card allows ${MAX_COLS} by ${MAX_ROWS}`);
  if (!ids.has(ctx.system)) problems.push(`diagram: no box has the id ${ctx.system}`);
  for (const s of [...neighbours].sort()) if (!covered.has(s)) problems.push(`diagram: neighbour ${s} has no box (give it one, or list it under a box's systems)`);
  for (const e of d.edges) if (!ids.has(e[0]) || !ids.has(e[1])) problems.push(`diagram: edge ${JSON.stringify(e)} names a box that does not exist`);
  for (const gr of d.groups) for (const m of gr.members) if (!ids.has(m)) problems.push(`diagram: group ${gr.label} names ${m}, which is not a box`);
  return problems;
}

const str = { type: "string" };
const strs = { type: "array", items: str };
/** The writer's reply schema. Edges come back as objects, since tuples are outside structured outputs; `parsePage` turns them into `[from, to, label?]`. */
export const PAGE_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: ["l1", "l2", "diagram"],
  properties: {
    l1: str,
    l2: str,
    l3: strs,
    diagram: {
      type: "object",
      additionalProperties: false,
      required: ["nodes", "edges"],
      properties: {
        nodes: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: ["id", "label", "sub", "paths", "grid"],
            properties: {
              id: str,
              label: str,
              sub: str,
              paths: strs,
              systems: strs,
              grid: { type: "object", additionalProperties: false, required: ["col", "row"], properties: { col: { type: "integer" }, row: { type: "integer" }, span: { type: "integer" } } },
            },
          },
        },
        edges: { type: "array", items: { type: "object", additionalProperties: false, required: ["from", "to"], properties: { from: str, to: str, label: str } } },
      },
    },
  },
};

/** A map as the schema returns it, in the wordbase's form: grid layout, edges as `[from, to, label?]`. */
export function normaliseDiagram(d: unknown): unknown {
  if (!d || typeof d !== "object") return d;
  const o = { ...(d as Record<string, unknown>) };
  o.layout ??= { mode: "grid" };
  if (Array.isArray(o.edges))
    o.edges = o.edges.map((e) => {
      if (Array.isArray(e) || !e || typeof e !== "object") return e;
      const x = e as { from?: unknown; to?: unknown; label?: unknown };
      return typeof x.label === "string" && x.label ? [x.from, x.to, x.label] : [x.from, x.to];
    });
  if (Array.isArray(o.nodes))
    o.nodes = o.nodes.map((n) => {
      if (!n || typeof n !== "object") return n;
      const c = { ...(n as Record<string, unknown>) };
      for (const k of ["paths", "systems"]) if (Array.isArray(c[k]) && !(c[k] as unknown[]).length) delete c[k];
      return c;
    });
  return o;
}

export function parsePage(text: string): SystemPageOut {
  const p = SystemOut.safeParse(extractJson(text));
  if (!p.success) throw new Error(`subsystem page reply does not match {l1, l2?, l3?, diagram?}: ${p.error.issues.map((i) => i.message).join("; ")}`);
  const o: SystemPageOut = { l1: p.data.l1 };
  if (p.data.l2) o.l2 = p.data.l2;
  if (p.data.l3?.length) o.l3 = p.data.l3;
  if (p.data.diagram !== undefined) o.diagram = normaliseDiagram(p.data.diagram);
  return o;
}

/** The page as the cold reader sees it: the layers, then the map's boxes and edges. */
export function pageText(o: SystemPageOut): string {
  const lines = [`l1: ${o.l1}`, ...(o.l2 ? [`l2: ${o.l2}`] : []), ...(o.l3 ?? []).map((p, i) => `l3[${i}]: ${p}`)];
  const d = Diagram.safeParse(o.diagram);
  if (d.success) {
    lines.push("", "diagram (the package's map; each box stands for the paths or packages listed):");
    for (const n of d.data.nodes) lines.push(`- box ${n.id}: "${n.label}" / "${n.sub ?? ""}"${n.paths?.length ? ` paths ${n.paths.join(", ")}` : ""}${n.systems?.length ? ` systems ${n.systems.join(", ")}` : ""}`);
    for (const e of d.data.edges) lines.push(`- edge ${e[0]} -> ${e[1]}${e[2] ? ` "${e[2]}"` : ""}`);
  }
  return lines.join("\n");
}

/** Thrown by `beforeCall` to stop at the spend cap; never swallowed. */
export class SpendStop extends Error {}

export interface SystemCall {
  role: "writer" | "rewrite" | "cold-before" | "cold-after";
  completion: Completion;
}

export interface SystemPageResult {
  system: string;
  page: SystemPageOut;
  /** Null when the cold reader did not run or failed (see `coldErrors`). */
  gapsBefore: Gap[] | null;
  /** Null when no rewrite happened, or the second read failed. */
  gapsAfter: Gap[] | null;
  /**
   * Which version was saved after a rewrite: the first draft when the cold reader found more gaps
   * in the rewrite and the draft had no lint hits or problems, else the rewrite. Null with no rewrite.
   */
  kept: "draft" | "rewrite" | null;
  coldErrors: string[];
  lint: string[];
  /** Map or layer problems left after the rewrite; a map problem drops the map. */
  problems: string[];
  diagramDropped: boolean;
  rewritten: boolean;
  calls: SystemCall[];
  cost_usd: number;
  costByModel: Record<string, number>;
}

export interface WriteOptions {
  inputs: SystemInputs;
  prompts: string;
  writer: Backend;
  reader: Backend;
  /** Called before every model call; throw to stop (the spend cap). */
  beforeCall?: (role: SystemCall["role"]) => void;
  /** Called after every model call with its completion, for the ledger and the running spend. */
  afterCall?: (call: SystemCall) => void;
  /** A map is required on a fresh page; the poller's refresh of a page without one may leave it out. */
  requireDiagram?: boolean;
}

/** Writer, cold reader, one rewrite, cold reader again. */
export async function writeSystemPage(o: WriteOptions): Promise<SystemPageResult> {
  const { inputs } = o;
  const calls: SystemCall[] = [];
  const ctx = { system: inputs.system, uses: inputs.uses, used_by: inputs.used_by, paths: inputs.paths, requireDiagram: o.requireDiagram ?? true };
  const prompt = `${await renderPrompt(o.prompts, "describe-system.md", { system: inputs.system, commit: inputs.commit })}\n\n${inputs.inputs}`;
  const turns: Turn[] = [{ role: "user", content: prompt }];
  const call = async (role: SystemCall["role"], b: Backend, t: Turn[], opts: CompleteOptions = {}) => {
    o.beforeCall?.(role);
    const c = await b.complete(t, opts);
    calls.push({ role, completion: c });
    o.afterCall?.({ role, completion: c });
    return c;
  };
  const coldErrors: string[] = [];
  // A cold reader that fails is recorded as null with its error, never as zero gaps.
  const cold = async (role: "cold-before" | "cold-after", page: SystemPageOut): Promise<Gap[] | null> => {
    const coldPrompt = await renderPrompt(o.prompts, "cold-reader.md", {
      subject: `the subsystem page of the ${inputs.system} package of the Marin repository`,
      where: "given under CODE as the package's file descriptions, its test descriptions, its README, source excerpts of its entry points and the one-sentence descriptions of its neighbouring packages; you have no other access to the code",
      text: pageText(page),
      code: inputs.inputs,
    });
    // The code half is the same on both reads; the second takes it from the cache.
    const cut = coldPrompt.indexOf("=== BEGIN DESCRIPTION ===");
    try {
      const c = await call(role, o.reader, [{ role: "user", content: coldPrompt }], cut > 0 ? { cachePrefix: coldPrompt.slice(0, cut) } : { cache: false });
      return parseGaps(c.text);
    } catch (e) {
      if (e instanceof SpendStop) throw e;
      coldErrors.push(`${role}: ${(e as Error).message}`);
      return null;
    }
  };

  const first = await call("writer", o.writer, turns, { jsonSchema: PAGE_SCHEMA });
  turns.push({ role: "assistant", content: first.text });
  let page: SystemPageOut;
  let parseProblem: string | null = null;
  try {
    page = parsePage(first.text);
  } catch (e) {
    parseProblem = (e as Error).message;
    page = { l1: "" };
  }
  const gapsBefore = parseProblem ? null : await cold("cold-before", page);
  let hits = parseProblem ? [] : lintPage(page);
  let problems = parseProblem ? [parseProblem] : checkPage(page, ctx);
  let rewritten = false;
  const draft = parseProblem ? null : { page: structuredClone(page), clean: !hits.length && !problems.length };
  if (gapsBefore?.length || hits.length || problems.length) {
    turns.push({
      role: "user",
      content: [
        "Revise the page and reply with the complete JSON object again.",
        ...(gapsBefore?.length ? ["", "A cold reader could not check these claims against the inputs; fix each with the smallest local edit or narrow the claim:", ...gapsBefore.map((g) => `- ${g.where}: "${g.claim}": ${g.problem}`)] : []),
        ...(hits.length ? ["", "Style lint hits (rewrite each sentence from scratch; do not swap in a synonym):", ...hits.map((h) => `- ${h}`)] : []),
        ...(problems.length ? ["", "Problems with the page or its map:", ...problems.map((p) => `- ${p}`)] : []),
      ].join("\n"),
    });
    const second = await call("rewrite", o.writer, turns, { jsonSchema: PAGE_SCHEMA });
    rewritten = true;
    try {
      page = parsePage(second.text);
    } catch (e) {
      if (parseProblem) throw new Error(`neither reply parsed: ${(e as Error).message}`);
      // keep the first page when the rewrite is not valid JSON
    }
    hits = lintPage(page);
    problems = checkPage(page, ctx);
  }
  const gapsAfter = rewritten ? await cold("cold-after", page) : null;
  // A rewrite that leaves more unchecked claims than the draft is worse; keep the draft when it was clean.
  let kept: SystemPageResult["kept"] = rewritten ? "rewrite" : null;
  if (rewritten && draft?.clean && gapsBefore && gapsAfter && gapsAfter.length > gapsBefore.length) {
    page = draft.page;
    hits = [];
    problems = [];
    kept = "draft";
  }

  let diagramDropped = false;
  if (problems.some((p) => p.startsWith("diagram:")) && page.diagram !== undefined) {
    delete page.diagram;
    diagramDropped = true;
  }
  const costByModel: Record<string, number> = {};
  for (const c of calls) costByModel[c.completion.model] = (costByModel[c.completion.model] ?? 0) + c.completion.cost_usd;
  return {
    system: inputs.system,
    page,
    gapsBefore,
    gapsAfter,
    kept,
    lint: hits,
    problems,
    diagramDropped,
    rewritten,
    coldErrors,
    calls,
    cost_usd: calls.reduce((s, c) => s + c.completion.cost_usd, 0),
    costByModel,
  };
}

/** Write the page into `systems/<name>.md`, keeping its body (notes) and any keys this run does not set. */
export async function saveSystemPage(wordbase: string, inputs: SystemInputs, r: SystemPageResult, by: string, opts: { keepUses?: boolean } = {}): Promise<string> {
  const file = systemEntryPath(wordbase, inputs.system);
  const prev = await readEntry(file);
  const now = new Date().toISOString().replace(/\.\d+Z$/, "Z");
  const front: Entry["front"] = prev ? { ...prev.front } : { kind: "system", name: inputs.system };
  front.kind = "system";
  front.name = inputs.system;
  front.members ??= [`lib/${inputs.system}/`];
  if (!opts.keepUses) {
    front.uses = inputs.uses;
    front.used_by = inputs.used_by;
  }
  Object.assign(front, { commit: inputs.commit, updated: now, by, l1: r.page.l1 });
  if (r.page.l2) front.l2 = r.page.l2;
  else delete front.l2;
  if (r.page.l3?.length) front.l3 = r.page.l3;
  else delete front.l3;
  if (r.page.diagram !== undefined) front.diagram = Diagram.parse(r.page.diagram);
  else if (!opts.keepUses) delete front.diagram;
  const lintField = [...r.lint, ...r.problems];
  if (lintField.length) front.lint = lintField;
  else delete front.lint;
  await saveEntry(file, { front, preamble: prev?.preamble ?? "", symbols: prev?.symbols ?? [], notes: prev?.notes ?? [], other: prev?.other ?? [] });
  return file;
}

export interface SystemResult {
  system: string;
  file: string;
  created: boolean;
  lint: string[];
  gaps: Gap[];
  completions: Completion[];
  cost_usd: number;
}

/** A neighbour's sentence: its page's `l1`, else its README's opening paragraph. */
export function neighbourLookup(repo: MarinRepo, commit: string, wordbase: string): (name: string) => Promise<{ l1: string | null; from: string }> {
  return async (name) => {
    const e = await readEntry(systemEntryPath(wordbase, name));
    if (e?.front.l1) return { l1: String(e.front.l1), from: "its subsystem page" };
    const readme = await repo.show(commit, `lib/${name}/README.md`);
    const open = readme ? readmeOpening(readme) : null;
    return open ? { l1: open, from: "the opening of its README; it has no page yet" } : { l1: null, from: "no page and no README" };
  };
}

/** The poller's refresh: one backend writes and cold-reads, and a page with a map keeps it unless the reply brings a valid one. */
export async function refreshSystem(p: { repo: MarinRepo; commit: string; wordbase: string; prompts: string; backend: Backend; system: string; by: string; imports?: ImportGraph }): Promise<SystemResult> {
  const { repo, commit, system } = p;
  const file = systemEntryPath(p.wordbase, system);
  const prev = await readEntry(file);
  const graph = await dependencyGraph(repo, commit);
  const existing = prev ? [`l1: ${prev.front.l1 ?? ""}`, ...(prev.front.l2 ? [`l2: ${prev.front.l2}`] : []), ...(prev.front.l3 ?? []).map((x) => `l3: ${x}`)].join("\n") : "none";
  const inputs = await systemInputs({
    repo,
    commit,
    wordbase: p.wordbase,
    prompts: p.prompts,
    system,
    graph,
    imports: p.imports ?? (await importGraph(repo, commit)),
    neighbourL1: neighbourLookup(repo, commit, p.wordbase),
    existing,
  });
  const r = await writeSystemPage({ inputs, prompts: p.prompts, writer: p.backend, reader: p.backend, requireDiagram: false });
  // A page with a map and no valid new one keeps its map and its uses/used_by, since every name there needs a box.
  const keepUses = !!prev?.front.diagram && r.page.diagram === undefined;
  await saveSystemPage(p.wordbase, inputs, { ...r, problems: r.problems.filter((x) => !(keepUses && x.startsWith("diagram:"))) }, p.by, { keepUses });
  return { system, file, created: !prev, lint: r.lint, gaps: (r.kept === "draft" ? r.gapsBefore : (r.gapsAfter ?? r.gapsBefore)) ?? [], completions: r.calls.map((c) => c.completion), cost_usd: r.cost_usd };
}
