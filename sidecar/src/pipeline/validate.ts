// Validation of a preparation run's outputs (DESIGN.md section 6): the sidecar's zod schemas, the
// limits the preparation prompt sets (10 boxes, a 4 by 3 grid), lint over every text field, and
// `prompts/check_fixture.py --pr <n>` for the checks that need the head commit's source.

import { readFile } from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { lint } from "../lint.js";
import { CodePath, Diagram, ReviewNote } from "../protocol.js";
import { parseEntry } from "../wordbase.js";
import { run } from "./exec.js";

export const PrFront = z
  .object({
    kind: z.literal("pr"),
    number: z.number().int().positive(),
    title: z.string().min(1),
    author: z.string().min(1),
    state: z.string().min(1),
    head: z.string().regex(/^[0-9a-f]{40}$/),
    base: z.string().regex(/^[0-9a-f]{40}$/),
    merge_base: z.string().regex(/^[0-9a-f]{40}$/),
    prepared_at: z.string().min(1),
    session_id: z.string().min(1),
    commit: z.string().regex(/^[0-9a-f]{40}$/),
    updated: z.string().min(1),
    by: z.string().min(1),
    l1: z.string().min(1),
    l2: z.string().min(1).optional(),
    l3: z.array(z.string().min(1)).optional(),
  })
  .passthrough();

export const Diagrams = z.object({ pr: Diagram, steps: z.record(z.string().regex(/^\d+$/), Diagram).default({}) }).strict();
export const FileLayers = z.record(z.string().min(1), z.object({ l1: z.string().min(1), l2: z.string().min(1).optional() }).strict());

export const MAX_BOXES = 10;
export const MAX_COLS = 4;
export const MAX_ROWS = 3;

export interface Validation {
  problems: string[];
  /** Lint hits as `file field: rule "match"`. */
  lint: string[];
  counts: { steps: number; diagrams: number; notes: number; files: number; boxes: number };
}

const issues = (e: z.ZodError) => e.issues.slice(0, 6).map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`).join("; ");

function diagramLimits(where: string, d: z.infer<typeof Diagram>, problems: string[]): void {
  if (d.nodes.length > MAX_BOXES) problems.push(`${where}: ${d.nodes.length} boxes; the limit is ${MAX_BOXES}`);
  for (const n of d.nodes) {
    if (!n.grid) continue;
    const right = n.grid.col + (n.grid.span ?? 1);
    if (right > MAX_COLS || n.grid.row + 1 > MAX_ROWS) problems.push(`${where} node ${n.id}: grid cell runs past ${MAX_COLS} columns by ${MAX_ROWS} rows`);
  }
  // A box that stands for code carries `paths`, so the viewer can mark it touched or dimmed.
  const missingPaths = d.nodes.filter((n) => n.at && !n.paths?.length).map((n) => n.id);
  if (missingPaths.length) problems.push(`${where}: boxes with code anchors but no paths: ${missingPaths.join(", ")}`);
}

function lintFields(file: string, fields: [string, string | undefined][], out: string[]): void {
  for (const [f, t] of fields) if (t) for (const h of lint(t)) out.push(`${file} ${f}: ${h.rule} "${h.match}"`);
}

async function readOr(file: string): Promise<string | null> {
  try {
    return await readFile(file, "utf8");
  } catch {
    return null;
  }
}

/** Validate `wordbase/prs/<n>/` against the schemas and limits, and lint its text. */
export async function validatePrOutputs(dir: string, expect: { number: number; head: string }): Promise<Validation> {
  const problems: string[] = [];
  const lintOut: string[] = [];
  const counts = { steps: 0, diagrams: 0, notes: 0, files: 0, boxes: 0 };

  const prText = await readOr(path.join(dir, "pr.md"));
  if (prText === null) problems.push("pr.md is missing");
  else {
    let front: unknown;
    try {
      front = parseEntry(prText).front;
    } catch (e) {
      problems.push(`pr.md front matter does not parse: ${(e as Error).message}`);
    }
    if (front) {
      // parseEntry stringifies some fields; number comes back as written.
      const f = { ...(front as Record<string, unknown>) };
      if (typeof f.number === "string" && /^\d+$/.test(f.number)) f.number = Number(f.number);
      const p = PrFront.safeParse(f);
      if (!p.success) problems.push(`pr.md front matter: ${issues(p.error)}`);
      else {
        if (p.data.number !== expect.number) problems.push(`pr.md number is ${p.data.number}, expected ${expect.number}`);
        if (p.data.head !== expect.head) problems.push(`pr.md head is ${p.data.head.slice(0, 10)}, expected ${expect.head.slice(0, 10)}`);
        lintFields("pr.md", [["l1", p.data.l1], ["l2", p.data.l2], ...(p.data.l3 ?? []).map((t, i): [string, string] => [`l3[${i}]`, t])], lintOut);
      }
    }
  }

  let stepIds = new Set<number>();
  const cpText = await readOr(path.join(dir, "code-path.json"));
  if (cpText === null) problems.push("code-path.json is missing");
  else {
    try {
      const cp = CodePath.safeParse(JSON.parse(cpText));
      if (!cp.success) problems.push(`code-path.json: ${issues(cp.error)}`);
      else {
        counts.steps = cp.data.length;
        stepIds = new Set(cp.data.map((s) => s.id));
        if (!cp.data.length) problems.push("code-path.json has no steps");
        for (const s of cp.data) {
          if (!s.node) problems.push(`code-path.json step ${s.id}: missing node`);
          if (!s.excerpts.length) problems.push(`code-path.json step ${s.id}: no excerpts`);
          for (const e of s.excerpts) if (path.isAbsolute(e.path) || e.path.split("/").includes("..")) problems.push(`code-path.json step ${s.id}: path ${e.path} is not repository-relative`);
          lintFields("code-path.json", [[`step ${s.id} title`, s.title], [`step ${s.id} l1`, s.l1], [`step ${s.id} l2`, s.l2]], lintOut);
        }
      }
    } catch (e) {
      problems.push(`code-path.json is not JSON: ${(e as Error).message}`);
    }
  }

  const dText = await readOr(path.join(dir, "diagrams.json"));
  if (dText === null) problems.push("diagrams.json is missing");
  else {
    try {
      const d = Diagrams.safeParse(JSON.parse(dText));
      if (!d.success) problems.push(`diagrams.json: ${issues(d.error)}`);
      else {
        const all: [string, z.infer<typeof Diagram>][] = [["pr", d.data.pr], ...Object.entries(d.data.steps).map(([k, v]): [string, z.infer<typeof Diagram>] => [`step ${k}`, v])];
        counts.diagrams = all.length;
        counts.boxes = d.data.pr.nodes.length;
        for (const [k, dg] of all) {
          diagramLimits(`diagrams.json ${k}`, dg, problems);
          lintFields("diagrams.json", dg.nodes.flatMap((n): [string, string | undefined][] => [[`${k} ${n.id} label`, n.label], [`${k} ${n.id} sub`, n.sub]]), lintOut);
          lintFields("diagrams.json", dg.groups.map((g, i): [string, string] => [`${k} group ${i}`, g.label]), lintOut);
        }
        for (const k of Object.keys(d.data.steps)) if (!stepIds.has(Number(k))) problems.push(`diagrams.json: step diagram ${k} has no step`);
      }
    } catch (e) {
      problems.push(`diagrams.json is not JSON: ${(e as Error).message}`);
    }
  }

  const nText = await readOr(path.join(dir, "notes.jsonl"));
  if (nText === null) problems.push("notes.jsonl is missing");
  else {
    nText.split("\n").forEach((line, i) => {
      if (!line.trim()) return;
      try {
        const n = ReviewNote.safeParse(JSON.parse(line));
        if (!n.success) problems.push(`notes.jsonl line ${i + 1}: ${issues(n.error)}`);
        else {
          counts.notes++;
          if (n.data.who !== "you") lintFields("notes.jsonl", [[`${n.data.id} l1`, n.data.l1], [`${n.data.id} l2`, n.data.l2]], lintOut);
        }
      } catch (e) {
        problems.push(`notes.jsonl line ${i + 1} is not JSON: ${(e as Error).message}`);
      }
    });
  }

  const fText = await readOr(path.join(dir, "files.json"));
  if (fText === null) problems.push("files.json is missing");
  else {
    try {
      const f = FileLayers.safeParse(JSON.parse(fText));
      if (!f.success) problems.push(`files.json: ${issues(f.error)}`);
      else {
        counts.files = Object.keys(f.data).length;
        for (const [p, v] of Object.entries(f.data)) lintFields("files.json", [[`${p} l1`, v.l1], [`${p} l2`, v.l2]], lintOut);
      }
    } catch (e) {
      problems.push(`files.json is not JSON: ${(e as Error).message}`);
    }
  }
  return { problems, lint: lintOut, counts };
}

export interface CheckerResult {
  ok: boolean;
  failures: string[];
  output: string;
}

/** The checker command, as the preparation prompt shows it and as the poller runs it. */
export function checkerArgs(opts: { prompts: string; wordbase: string; marin: string; pr?: number; entries?: string[] }): string[] {
  return [
    "run",
    "--with",
    "pyyaml",
    path.join(opts.prompts, "check_fixture.py"),
    "--wordbase",
    opts.wordbase,
    "--marin",
    opts.marin,
    "--strict-boxes",
    ...(opts.pr ? ["--pr", String(opts.pr)] : []),
    ...(opts.entries ?? []).flatMap((e) => ["--entry", e]),
  ];
}

export async function runChecker(opts: { prompts: string; wordbase: string; marin: string; pr?: number; entries?: string[]; cwd: string }): Promise<CheckerResult> {
  const r = await run("uv", checkerArgs(opts), { cwd: opts.cwd, timeoutMs: 300_000 });
  const output = `${r.stdout}${r.stderr}`;
  const failures = output.split("\n").filter((l) => l.startsWith("FAIL "));
  if (r.code !== 0 && !failures.length) failures.push(`check_fixture.py exited ${r.code}: ${output.trim().slice(-400)}`);
  return { ok: r.code === 0, failures, output };
}
