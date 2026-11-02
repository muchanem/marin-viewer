// Description runs (DESIGN.md section 8): render `prompts/describe-unit.md` for one unit, call a
// backend, validate the JSON reply, lint every text field, and send one rewrite turn when either
// check fails. A reply that still fails validation is rejected; text that still fails lint is kept
// with a `lint:` field listing the hits.

import path from "node:path";
import { z } from "zod";
import { lint } from "../lint.js";
import { fileEntryPath, readEntry, saveEntry, type Entry, type Note, type SymbolSection } from "../wordbase.js";
import type { Backend, Completion } from "./backends.js";
import { renderPrompt } from "./prompts.js";
import type { UnitContext } from "./units.js";

export const SymbolOut = z.object({ name: z.string().min(1), l1: z.string().min(1), l2: z.string().min(1).optional() });
export const EntryOut = z.object({
  l1: z.string().min(1),
  l2: z.string().min(1).optional(),
  l3: z.array(z.string().min(1)).optional(),
  system: z.string().min(1),
  symbols: z.array(SymbolOut).optional(),
  changed_symbols: z.array(z.string().min(1)).optional(),
});
export const KeepOut = z.object({ keep: z.literal(true) }).strict();
export const UnitOutput = z.record(z.string(), z.union([KeepOut, EntryOut]));
export type EntryOut = z.infer<typeof EntryOut>;
export type UnitOutput = z.infer<typeof UnitOutput>;

// The same single-sentence test as prompts/check_fixture.py.
const SENTENCE_BREAK = /(?<!\be\.g)(?<!\bi\.e)[.!?]\s+[A-Z`]/;

export async function renderDescribePrompt(promptsDir: string, ctx: UnitContext): Promise<string> {
  const text = await renderPrompt(promptsDir, "describe-unit.md", {
    unit: ctx.unit.dir,
    commit: ctx.unit.commit,
    package: ctx.unit.package,
    unit_kind: "a single directory",
  });
  return `${text}\n\n${ctx.inputs}`;
}

/** Pull one JSON object out of a reply, tolerating fences or prose around it. */
export function extractJson(text: string): unknown {
  const t = text.trim().replace(/^```(?:json)?\s*\n/, "").replace(/\n```\s*$/, "");
  try {
    return JSON.parse(t);
  } catch {
    const a = t.indexOf("{");
    const b = t.lastIndexOf("}");
    if (a < 0 || b <= a) throw new Error("the reply holds no JSON object");
    return JSON.parse(t.slice(a, b + 1));
  }
}

export interface Checked {
  output: UnitOutput | null;
  /** Validation problems: a reply with any is rejected. */
  problems: string[];
  /** Lint hits by path, as `field: rule "match"`. */
  lint: Map<string, string[]>;
}

export function lintEntry(e: EntryOut): string[] {
  const fields: [string, string][] = [["l1", e.l1]];
  if (e.l2) fields.push(["l2", e.l2]);
  (e.l3 ?? []).forEach((p, i) => fields.push([`l3[${i}]`, p]));
  for (const s of e.symbols ?? []) {
    fields.push([`${s.name}.l1`, s.l1]);
    if (s.l2) fields.push([`${s.name}.l2`, s.l2]);
  }
  return fields.flatMap(([f, t]) => lint(t).map((h) => `${f}: ${h.rule} "${h.match}"`));
}

export function checkOutput(text: string, targets: string[], existing: Set<string>, pkg: string): Checked {
  const problems: string[] = [];
  const lintHits = new Map<string, string[]>();
  let raw: unknown;
  try {
    raw = extractJson(text);
  } catch (e) {
    return { output: null, problems: [`the reply is not a JSON object: ${(e as Error).message}`], lint: lintHits };
  }
  const parsed = UnitOutput.safeParse(raw);
  if (!parsed.success) {
    const issues = parsed.error.issues.slice(0, 8).map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`);
    return { output: null, problems: [`the JSON does not match the entry schema: ${issues.join("; ")}`], lint: lintHits };
  }
  const out = parsed.data;
  const keys = new Set(Object.keys(out));
  const missing = targets.filter((t) => !keys.has(t));
  const extra = [...keys].filter((k) => !targets.includes(k));
  if (missing.length) problems.push(`entries missing for ${missing.join(", ")}`);
  if (extra.length) problems.push(`keys that are not targets: ${extra.join(", ")}`);
  for (const [p, v] of Object.entries(out)) {
    if ("keep" in v) {
      if (!existing.has(p)) problems.push(`${p}: keep given to a file without an existing entry`);
      continue;
    }
    if (SENTENCE_BREAK.test(v.l1)) problems.push(`${p}: l1 must be a single sentence`);
    if (v.system !== pkg) v.system = pkg; // the subsystem is the package; nested systems are not generated
    const hits = lintEntry(v);
    if (hits.length) lintHits.set(p, hits);
  }
  return { output: out, problems, lint: lintHits };
}

export function rewriteRequest(c: Checked): string {
  const lines = ["Your reply has problems. Fix them and reply with the complete JSON object again, in the same format and with the same keys.", ""];
  if (c.problems.length) lines.push("Validation:", ...c.problems.map((p) => `- ${p}`), "");
  if (c.lint.size) {
    lines.push("Style lint (each hit breaks a rule in the style section; rewrite the sentence from scratch, and do not swap in a synonym):");
    for (const [p, hits] of c.lint) lines.push(`- ${p}`, ...hits.map((h) => `  - ${h}`));
  }
  return lines.join("\n");
}

export interface UnitResult {
  output: UnitOutput;
  lint: Map<string, string[]>;
  completions: Completion[];
  rewritten: boolean;
  /** The problems and lint hits that triggered the rewrite. */
  rewriteReason: string[];
  cost_usd: number;
  latency_ms: number;
}

export async function describeUnit(backend: Backend, promptsDir: string, ctx: UnitContext): Promise<UnitResult> {
  const prompt = await renderDescribePrompt(promptsDir, ctx);
  const existing = new Set(ctx.existing.keys());
  const first = await backend.complete([{ role: "user", content: prompt }]);
  let checked = checkOutput(first.text, ctx.unit.targets, existing, ctx.unit.package);
  const completions = [first];
  let rewritten = false;
  let rewriteReason: string[] = [];
  if (checked.problems.length || checked.lint.size) {
    rewritten = true;
    rewriteReason = [...checked.problems, ...[...checked.lint].flatMap(([f, hits]) => hits.map((h) => `${path.basename(f)} ${h}`))];
    const second = await backend.complete([
      { role: "user", content: prompt },
      { role: "assistant", content: first.text },
      { role: "user", content: rewriteRequest(checked) },
    ]);
    completions.push(second);
    const again = checkOutput(second.text, ctx.unit.targets, existing, ctx.unit.package);
    // Keep the first reply's valid entries when the rewrite breaks the JSON.
    checked = again.output || !checked.output ? again : { ...checked, problems: [...checked.problems, ...again.problems] };
  }
  const cost = completions.reduce((s, c) => s + c.cost_usd, 0);
  const latency = completions.reduce((s, c) => s + c.latency_ms, 0);
  if (!checked.output || checked.problems.length) {
    const err = new Error(`${backend.name} output for ${ctx.unit.dir} failed validation after one rewrite: ${checked.problems.join("; ")}`) as Error & { cost_usd?: number };
    err.cost_usd = cost;
    throw err;
  }
  return { output: checked.output, lint: checked.lint, completions, rewritten, rewriteReason, cost_usd: cost, latency_ms: latency };
}

// ---------------------------------------------------------------------------
// Writing entries

export function markChangedNotes(notes: Note[], symbols: string[], sha: string): Note[] {
  const tag = `(code changed at ${sha.slice(0, 7)})`;
  return notes.map((n) => {
    if (n.text.includes(tag)) return n;
    const hit = symbols.some((s) => n.text.includes(`\`${s}\``) || n.text.includes(`\`${s.split(".").at(-1)}\``));
    return hit ? { ...n, text: `${n.text} ${tag}`, ...(n.body ? { body: `${n.body} ${tag}` } : {}) } : n;
  });
}

export function buildEntry(prev: Entry | null, repoPath: string, out: EntryOut, meta: { commit: string; by: string; now: string; lint?: string[] }): Entry {
  const front: Entry["front"] = {
    kind: "file",
    path: repoPath,
    commit: meta.commit,
    updated: meta.now,
    by: meta.by,
    l1: out.l1,
    ...(out.l2 ? { l2: out.l2 } : {}),
    ...(out.l3?.length ? { l3: out.l3 } : {}),
    system: out.system,
    ...(meta.lint?.length ? { lint: meta.lint } : {}),
  };
  const symbols: SymbolSection[] = (out.symbols ?? []).map((s) => ({ name: s.name, fields: { l1: s.l1, ...(s.l2 ? { l2: s.l2 } : {}) } }));
  const notes = markChangedNotes(prev?.notes ?? [], out.changed_symbols ?? [], meta.commit);
  return { front, preamble: prev?.preamble ?? "", symbols, notes, other: prev?.other ?? [] };
}

export interface Written {
  files: string[];
  /** Repository paths whose `l1` changed or that are new, for the subsystem refresh. */
  l1Changed: string[];
  kept: string[];
  lintHits: number;
}

export async function writeEntries(wordbase: string, result: UnitResult, meta: { commit: string; by: string; now?: string }): Promise<Written> {
  const now = meta.now ?? new Date().toISOString().replace(/\.\d+Z$/, "Z");
  const w: Written = { files: [], l1Changed: [], kept: [], lintHits: 0 };
  for (const [repoPath, v] of Object.entries(result.output)) {
    if ("keep" in v) {
      w.kept.push(repoPath);
      continue;
    }
    const file = fileEntryPath(wordbase, repoPath);
    const prev = await readEntry(file);
    const hits = result.lint.get(repoPath) ?? [];
    w.lintHits += hits.length;
    await saveEntry(file, buildEntry(prev, repoPath, v, { commit: meta.commit, by: meta.by, now, lint: hits }));
    w.files.push(file);
    if (!prev || prev.front.l1 !== v.l1) w.l1Changed.push(repoPath);
  }
  return w;
}
