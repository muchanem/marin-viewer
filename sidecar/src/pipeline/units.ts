// Description units (DESIGN.md section 8, "Context for descriptions"). A unit is one directory of
// Python files at one commit. Its prompt input holds the source of every file in the directory, the
// package README, the signatures and wordbase `l1` lines of the modules it imports and of those that
// import it, the subsystem page, the existing entries and, on a regeneration, the diff.

import path from "node:path";
import { readFile } from "node:fs/promises";
import { fileEntryPath, readEntry, systemEntryPath, type Entry } from "../wordbase.js";
import { inputBlock } from "./prompts.js";
import { importGraph, packageName, signatures, type MarinRepo } from "./repo.js";

export interface Unit {
  /** The directory, such as `lib/shellbox/src/shellbox`. */
  dir: string;
  package: string;
  commit: string;
  /** Every non-empty Python file directly in the directory. */
  files: string[];
  /** The files the run writes entries for; the rest are context. */
  targets: string[];
}

/** Group paths into directory units. Targets are the given paths; `files` is filled in by `loadUnit`. */
export function groupByDirectory(paths: string[], commit: string): Unit[] {
  const byDir = new Map<string, string[]>();
  for (const p of paths) {
    const dir = path.posix.dirname(p);
    if (!byDir.has(dir)) byDir.set(dir, []);
    byDir.get(dir)!.push(p);
  }
  return [...byDir.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([dir, targets]) => ({ dir, package: packageName(dir), commit, files: [], targets: targets.sort() }));
}

export interface UnitContext {
  unit: Unit;
  /** The rendered input blocks that follow the prompt. */
  inputs: string;
  /** Sizes for the report: characters of source in full and as signatures only. */
  stats: { sourceChars: number; signatureOnly: string[]; neighbours: number; chars: number };
  existing: Map<string, Entry>;
}

export interface UnitOptions {
  wordbase: string;
  /** Total character budget for the inputs; files past it are given as signatures only. */
  maxChars?: number;
  /** For a regeneration: diff each target from the commit of its existing entry, or from here. */
  diffFrom?: string | null;
  maxNeighbours?: number;
  /** Leave EXISTING empty, as on a first pass (the model comparison does this). */
  ignoreExisting?: boolean;
}

const block = inputBlock;

let graphCache: { commit: string; graph: Awaited<ReturnType<typeof importGraph>> } | null = null;

async function graphAt(repo: MarinRepo, commit: string) {
  if (graphCache?.commit !== commit) graphCache = { commit, graph: await importGraph(repo, commit) };
  return graphCache.graph;
}

/** Fill in the unit's files: every non-empty `.py` directly in its directory at its commit. */
export async function loadUnit(repo: MarinRepo, unit: Unit): Promise<Unit> {
  const sizes = await repo.sizes(unit.commit, `${unit.dir}/`);
  const files = [...sizes.entries()]
    .filter(([p, n]) => p.endsWith(".py") && path.posix.dirname(p) === unit.dir && n > 0)
    .map(([p]) => p)
    .sort();
  const targets = unit.targets.filter((t) => files.includes(t));
  return { ...unit, files, targets };
}

async function readText(file: string): Promise<string | null> {
  try {
    return await readFile(file, "utf8");
  } catch {
    return null;
  }
}

export async function buildContext(repo: MarinRepo, unit: Unit, opts: UnitOptions): Promise<UnitContext> {
  const maxChars = opts.maxChars ?? 400_000;
  const maxNeighbours = opts.maxNeighbours ?? 30;
  const parts: string[] = [];
  let used = 0;

  // 1. Sources: targets first, then siblings, in full while the budget allows.
  const order = [...unit.targets, ...unit.files.filter((f) => !unit.targets.includes(f))];
  const signatureOnly: string[] = [];
  let sourceChars = 0;
  for (const f of order) {
    const src = (await repo.show(unit.commit, f)) ?? "";
    const isTarget = unit.targets.includes(f);
    if (!isTarget && used + src.length > maxChars * 0.7) {
      signatureOnly.push(f);
      parts.push(block(`SOURCE ${f} (signatures only; not in the unit's budget)`, signatures(src, 80).join("\n") || "(no definitions)"));
      continue;
    }
    sourceChars += src.length;
    used += src.length;
    parts.push(block(`SOURCE ${f}`, src));
  }

  // 2. README, cut to 20,000 characters.
  const pkgRoot = `lib/${unit.package}`;
  let readme = (await repo.show(unit.commit, `${pkgRoot}/README.md`)) ?? "none";
  if (readme.length > 20_000) readme = `${readme.slice(0, 20_000)}\n... (README cut at 20,000 characters)`;
  parts.push(block("README", readme));

  // 3. Neighbours: modules the unit imports and modules that import it.
  const { imports, importers } = await graphAt(repo, unit.commit);
  const inUnit = new Set(unit.files);
  const imported = new Set<string>();
  const importing = new Set<string>();
  for (const f of unit.files) {
    for (const t of imports.get(f) ?? []) if (!inUnit.has(t)) imported.add(t);
    for (const s of importers.get(f) ?? []) if (!inUnit.has(s)) importing.add(s);
  }
  const rank = (list: Set<string>) =>
    [...list].sort((a, b) => Number(b.startsWith(pkgRoot)) - Number(a.startsWith(pkgRoot)) || Number(a.includes("/tests/")) - Number(b.includes("/tests/")) || a.localeCompare(b));
  const neighbourBlock = async (title: string, list: string[]) => {
    const out = [`## ${title}`, ""];
    for (const p of list) {
      const entry = await readEntry(fileEntryPath(opts.wordbase, p)).catch(() => null);
      const sigs = signatures((await repo.show(unit.commit, p)) ?? "", 30);
      out.push(`### ${p}`, `l1: ${entry?.front.l1 ?? "no entry"}`, "```python", ...(sigs.length ? sigs : ["(no definitions)"]), "```", "");
    }
    return out.join("\n");
  };
  const half = Math.ceil(maxNeighbours / 2);
  const importedList = rank(imported).slice(0, half);
  const importingList = rank(importing).slice(0, maxNeighbours - importedList.length);
  const omitted = imported.size + importing.size - importedList.length - importingList.length;
  parts.push(
    block(
      "NEIGHBOURS",
      [
        await neighbourBlock("Imported by the unit", importedList),
        await neighbourBlock("Imports the unit", importingList),
        omitted > 0 ? `(${omitted} more neighbouring modules omitted)` : "",
      ].join("\n"),
    ),
  );

  // 4. Subsystem page.
  parts.push(block("SUBSYSTEM", (await readText(systemEntryPath(opts.wordbase, unit.package))) ?? "none"));

  // 5. Existing entries.
  const existing = new Map<string, Entry>();
  const existingText: string[] = [];
  for (const f of unit.files) {
    const e = opts.ignoreExisting ? null : await readEntry(fileEntryPath(opts.wordbase, f)).catch(() => null);
    if (!e || e.front.deleted) continue;
    existing.set(f, e);
    const lines = [`### ${f}`, `commit: ${e.front.commit ?? "unknown"}`, `l1: ${e.front.l1 ?? ""}`];
    if (e.front.l2) lines.push(`l2: ${e.front.l2}`);
    for (const p of e.front.l3 ?? []) lines.push(`l3: ${p}`);
    for (const s of e.symbols) lines.push(`symbol ${s.name}: ${String(s.fields.l1 ?? s.raw ?? "")}`);
    existingText.push(lines.join("\n"));
  }
  parts.push(block("EXISTING", existingText.length ? existingText.join("\n\n") : "none"));

  // 6. Diff, on a regeneration.
  let diff = "none";
  if (opts.diffFrom !== undefined && opts.diffFrom !== null) {
    const d = await repo.diff(opts.diffFrom, unit.commit, unit.targets).catch(() => "");
    if (d.trim()) diff = d.length > 40_000 ? `${d.slice(0, 40_000)}\n... (diff cut at 40,000 characters)` : d;
  }
  parts.push(block("DIFF", diff));

  // 7. Targets.
  parts.push(block("TARGETS", unit.targets.join("\n")));

  const inputs = parts.join("\n");
  return { unit, inputs, existing, stats: { sourceChars, signatureOnly, neighbours: importedList.length + importingList.length, chars: inputs.length } };
}
