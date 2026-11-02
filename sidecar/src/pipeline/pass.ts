// The full first pass, planned and sized without calling a model: every source directory under
// `lib/` (split where it passes the budget), its tests, and the orphan batches, each prompt built
// by `ContextBuilder` and counted in o200k tokens. `earlier` sizes the rules of 2026-11-02 morning,
// when test directories were units of their own and a source unit carried every test that imports it.

import path from "node:path";
import type { MarinRepo } from "./repo.js";
import { ContextBuilder, unitLabel, type BuilderOptions, type ContextStats, type Unit } from "./units.js";

export type PassRules = "current" | "earlier";

export interface PassPrompt {
  label: string;
  kind: "source" | "tests" | "orphans";
  tokens: number;
  /** Source files given full entries. */
  files: number;
  /** Test files given an `l1` (current rules) or a full entry (earlier rules, in `files`). */
  tests: number;
  neighbours: number;
  neighboursDropped: number;
  testsInPrompt: number;
  testsDropped: number;
  outsideLib: number;
  overBudget: boolean;
}

export interface PassPlan {
  rules: PassRules;
  commit: string;
  budget: number;
  prompts: PassPrompt[];
  /** Directories cut into slices, with each slice's files, tests and tokens. */
  splits: { dir: string; files: number; slices: { files: number; tests: number; tokens: number }[] }[];
  /** Owned tests that could not ride with their unit and went to an orphan batch. */
  overflow: number;
  orphans: number;
}

function record(label: string, kind: PassPrompt["kind"], u: Unit, s: ContextStats): PassPrompt {
  return {
    label,
    kind,
    tokens: s.tokens,
    files: u.targets.length,
    tests: (u.testTargets ?? []).length,
    neighbours: s.neighbours.length,
    neighboursDropped: s.neighboursDropped.length,
    testsInPrompt: s.tests.length,
    testsDropped: s.testsDropped.length,
    outsideLib: s.outsideLib.length,
    overBudget: s.overBudget,
  };
}

export async function planPass(repo: MarinRepo, commit: string, opts: Omit<BuilderOptions, "mandatoryTests">, rules: PassRules, log: (line: string) => void = () => {}): Promise<PassPlan> {
  const builder = new ContextBuilder(repo, commit, { ...opts, ignoreExisting: true, mandatoryTests: rules === "current" ? "owned" : "all" });
  const dirs = await builder.sourceDirs();
  const owners = await builder.owners();
  const plan: PassPlan = { rules, commit, budget: builder.budget, prompts: [], splits: [], overflow: 0, orphans: 0 };
  const units: { unit: Unit; kind: PassPrompt["kind"] }[] = [];
  for (const [dir, files] of [...dirs].sort(([a], [b]) => a.localeCompare(b))) {
    const owned = rules === "current" ? [...owners].filter(([, d]) => d === dir).map(([t]) => t) : [];
    units.push({ unit: { dir, package: dir.split("/")[1] ?? "", commit, files, targets: files, testTargets: owned }, kind: "source" });
  }
  if (rules === "earlier") {
    const byDir = new Map<string, string[]>();
    for (const t of await builder.libTests()) {
      const d = path.posix.dirname(t);
      if (!byDir.has(d)) byDir.set(d, []);
      byDir.get(d)!.push(t);
    }
    for (const [dir, files] of [...byDir].sort(([a], [b]) => a.localeCompare(b))) units.push({ unit: { dir, package: dir.split("/")[1] ?? "", commit, files, targets: files }, kind: "tests" });
  }
  const orphanTests = rules === "current" ? [...owners].filter(([, d]) => d === null).map(([t]) => t) : [];
  plan.orphans = orphanTests.length;
  let n = 0;
  for (const { unit, kind } of units) {
    const planned = await builder.plan(unit);
    if (rules === "current") {
      const lost = planned.overflow.filter((t) => (unit.testTargets ?? []).includes(t));
      orphanTests.push(...lost);
      plan.overflow += lost.length;
    }
    const sliceRecords: PassPlan["splits"][number]["slices"] = [];
    for (const u of planned.units) {
      const siblings = planned.units.length > 1 ? unit.files.filter((f) => !u.files.includes(f)) : [];
      const ctx = await builder.build(u, { siblings });
      plan.prompts.push(record(unitLabel(u), kind, u, ctx.stats));
      sliceRecords.push({ files: u.files.length, tests: (u.tests ?? []).length, tokens: ctx.stats.tokens });
    }
    if (planned.units.length > 1) {
      plan.splits.push({ dir: unit.dir, files: unit.files.length, slices: sliceRecords });
      log(`split ${unit.dir}: ${sliceRecords.map((r) => `${r.files} files + ${r.tests} tests = ${r.tokens} tokens`).join("; ")}`);
    }
    if (++n % 25 === 0) log(`${rules}: ${n} of ${units.length} units sized`);
  }
  for (const b of await builder.orphanBatches([...new Set(orphanTests)].sort())) {
    const ctx = await builder.build(b);
    plan.prompts.push(record(unitLabel(b), "orphans", b, ctx.stats));
  }
  return plan;
}

/** USD per million tokens; `firstInput` is what a first call's prompt is billed at. */
export interface PromptPrices {
  firstInput: number;
  cachedInput: number;
  output: number;
}

export interface PromptModel {
  /** Billed prompt tokens per o200k token, from the live runs. */
  tokenRatio: number;
  /** Output tokens per source file with a full entry, reasoning included. */
  outPerFile: number;
  /** Output tokens per test `l1` (an assumption until a run measures it). */
  outPerTest: number;
  /** Share of prompts that need a rewrite turn, which rereads the prompt from cache. */
  rewriteRate: number;
}

export function pricePass(prompts: PassPrompt[], m: PromptModel, p: PromptPrices): { usd: number; inputTokens: number; outputTokens: number; over272k: string[] } {
  let usd = 0;
  let inputTokens = 0;
  let outputTokens = 0;
  const over272k: string[] = [];
  for (const q of prompts) {
    const input = q.tokens * m.tokenRatio;
    if (input > 272_000) over272k.push(q.label);
    const output = q.files * m.outPerFile + q.tests * m.outPerTest;
    usd += (input * p.firstInput + m.rewriteRate * input * p.cachedInput + output * p.output) / 1e6;
    inputTokens += input * (1 + m.rewriteRate);
    outputTokens += output;
  }
  return { usd, inputTokens, outputTokens, over272k };
}
