// Subsystem pages (DESIGN.md section 8): when a file's `l1` changes, its subsystem page is refreshed
// once at the end of the tick from the package's file entries, README and dependencies. A package
// without a page gets one, since every file entry names a subsystem that must exist. The page then
// goes through lint and a cold-reader pass, and failures are rewritten once.

import { readdir } from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { lint } from "../lint.js";
import { readEntry, saveEntry, systemEntryPath, type Entry } from "../wordbase.js";
import type { Backend, Completion, Turn } from "./backends.js";
import { extractJson } from "./describe.js";
import { inputBlock, renderPrompt } from "./prompts.js";
import { signatures, type MarinRepo } from "./repo.js";
import { parseGaps, type Gap } from "./prepare.js";

const SystemOut = z.object({ l1: z.string().min(1), l2: z.string().min(1).optional(), l3: z.array(z.string().min(1)).optional() });
type SystemOut = z.infer<typeof SystemOut>;

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

export async function dependencyGraph(repo: MarinRepo, commit: string): Promise<Map<string, { uses: string[]; used_by: string[] }>> {
  const files = await repo.lsTree(commit, "lib/");
  const packages = [...new Set(files.map((f) => f.split("/")[1]!).filter(Boolean))];
  const uses = new Map<string, string[]>();
  for (const p of packages) {
    const text = (await repo.show(commit, `lib/${p}/pyproject.toml`)) ?? "";
    uses.set(p, workspaceDeps(text, packages).filter((d) => d !== p));
  }
  const graph = new Map<string, { uses: string[]; used_by: string[] }>();
  for (const p of packages) graph.set(p, { uses: uses.get(p) ?? [], used_by: packages.filter((q) => uses.get(q)?.includes(p)).sort() });
  return graph;
}

async function fileEntries(wordbase: string, pkg: string): Promise<Map<string, Entry>> {
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

function lintPage(o: SystemOut): string[] {
  const fields: [string, string][] = [["l1", o.l1], ...(o.l2 ? [["l2", o.l2] as [string, string]] : []), ...(o.l3 ?? []).map((t, i): [string, string] => [`l3[${i}]`, t])];
  return fields.flatMap(([f, t]) => lint(t).map((h) => `${f}: ${h.rule} "${h.match}"`));
}

function parsePage(text: string): SystemOut {
  const p = SystemOut.safeParse(extractJson(text));
  if (!p.success) throw new Error(`subsystem page reply does not match {l1, l2?, l3?}: ${p.error.issues.map((i) => i.message).join("; ")}`);
  return p.data;
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

export async function refreshSystem(p: { repo: MarinRepo; commit: string; wordbase: string; prompts: string; backend: Backend; system: string; by: string }): Promise<SystemResult> {
  const { repo, commit, system } = p;
  const file = systemEntryPath(p.wordbase, system);
  const prev = await readEntry(file);
  const entries = await fileEntries(p.wordbase, system);
  const all = (await repo.lsTree(commit, `lib/${system}/`)).filter((f) => f.endsWith(".py"));
  const graph = (await dependencyGraph(repo, commit)).get(system) ?? { uses: [], used_by: [] };

  const fileLines: string[] = [];
  let sigChars = 0;
  for (const f of all) {
    const e = entries.get(f);
    if (e?.front.l1) fileLines.push(`- ${f}: ${e.front.l1}`);
    else if (sigChars < 60_000 && !f.includes("/tests/")) {
      const sigs = signatures((await repo.show(commit, f)) ?? "", 12);
      sigChars += sigs.join("\n").length;
      fileLines.push(`- ${f}: no entry; definitions: ${sigs.map((s) => s.trim()).join(" | ") || "none"}`);
    } else fileLines.push(`- ${f}: no entry`);
  }
  let readme = (await repo.show(commit, `lib/${system}/README.md`)) ?? "none";
  if (readme.length > 20_000) readme = `${readme.slice(0, 20_000)}\n... (cut)`;
  const existing = prev ? [`l1: ${prev.front.l1 ?? ""}`, ...(prev.front.l2 ? [`l2: ${prev.front.l2}`] : []), ...(prev.front.l3 ?? []).map((x) => `l3: ${x}`)].join("\n") : "none";
  const prompt = [
    await renderPrompt(p.prompts, "describe-system.md", { system, commit }),
    "",
    inputBlock("README", readme),
    inputBlock("FILES", fileLines.join("\n")),
    inputBlock("DEPENDENCIES", `depends on: ${graph.uses.join(", ") || "none"}\ndepended on by: ${graph.used_by.join(", ") || "none"}`),
    inputBlock("EXISTING", existing),
  ].join("\n");

  const turns: Turn[] = [{ role: "user", content: prompt }];
  const completions: Completion[] = [];
  const ask = async () => {
    const c = await p.backend.complete(turns);
    completions.push(c);
    turns.push({ role: "assistant", content: c.text });
    return c.text;
  };
  let page = parsePage(await ask());

  // Cold reader: a fresh call with only the page and the package's file lines.
  const coldPrompt = await renderPrompt(p.prompts, "cold-reader.md", {
    subject: `the ${system} package of the Marin repository`,
    where: "summarised under CODE, one line per file with its wordbase description or its definitions; you have no other access to the code",
    text: JSON.stringify(page, null, 1),
    code: fileLines.join("\n"),
  });
  let gaps: Gap[] = [];
  try {
    const c = await p.backend.complete([{ role: "user", content: coldPrompt }]);
    completions.push(c);
    gaps = parseGaps(c.text);
  } catch {
    gaps = [];
  }
  let hits = lintPage(page);
  if (gaps.length || hits.length) {
    turns.push({
      role: "user",
      content: [
        "Revise the page and reply with the complete JSON object again.",
        ...(gaps.length ? ["", "A cold reader could not check these claims against the inputs; fix each with the smallest local edit or narrow the claim:", ...gaps.map((g) => `- ${g.where}: "${g.claim}": ${g.problem}`)] : []),
        ...(hits.length ? ["", "Style lint hits (rewrite each sentence from scratch; do not swap in a synonym):", ...hits.map((h) => `- ${h}`)] : []),
      ].join("\n"),
    });
    try {
      page = parsePage(await ask());
    } catch {
      // keep the first page when the rewrite is not valid JSON
    }
    hits = lintPage(page);
  }

  const now = new Date().toISOString().replace(/\.\d+Z$/, "Z");
  const front: Entry["front"] = prev
    ? { ...prev.front }
    : { kind: "system", name: system, members: [`lib/${system}/`], uses: graph.uses, used_by: graph.used_by };
  // A page with a diagram keeps its uses/used_by, since every name there needs a box.
  if (prev && !prev.front.diagram) {
    front.uses = graph.uses;
    front.used_by = graph.used_by;
  }
  Object.assign(front, { commit, updated: now, by: p.by, l1: page.l1 });
  if (page.l2) front.l2 = page.l2;
  else delete front.l2;
  if (page.l3?.length) front.l3 = page.l3;
  else delete front.l3;
  if (hits.length) front.lint = hits;
  else delete front.lint;
  await saveEntry(file, { front, preamble: prev?.preamble ?? "", symbols: prev?.symbols ?? [], notes: prev?.notes ?? [], other: prev?.other ?? [] });
  return { system, file, created: !prev, lint: hits, gaps, completions, cost_usd: completions.reduce((s, c) => s + c.cost_usd, 0) };
}
