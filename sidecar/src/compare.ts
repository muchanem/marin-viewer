// `npm run compare`: the 20-file description comparison of DESIGN.md section 8. Describes the same
// directory units with each model on the first-pass shape (no existing entries), and writes lint
// hits, cost, latency and the texts side by side to `state/reports/describe-comparison.md`. Results
// are kept in `describe-comparison.json` beside it, so a later `--models glm` run fills in a model
// without rerunning the others. Nothing is written to the wordbase.
//
//   npm run compare -- [--models terra-full] [--commit <rev>] [--fresh] [--report-only] [--estimate]
//
// A model with earlier results keeps its successful units and reruns the others; --fresh reruns all.
// Sonnet, Opus, GLM-5.3 and the first Terra column ran on the context builder before 2026-11-02
// (signature-only neighbours from lib/ alone); that builder is gone, so their results are kept and
// cannot be rerun. --estimate sizes the full first pass under the current and earlier test rules
// (every prompt built and counted, no model calls) and keeps the result in the JSON.

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { loadConfig, openRouterKey } from "./config.js";
import { lint } from "./lint.js";
import { ClaudeBackend, FleetHold, GlmBackend, TunnelDown, type Backend } from "./pipeline/backends.js";
import { checkOutput, describeUnit, type EntryOut } from "./pipeline/describe.js";
import { passCost, passUnits, type PassModel, type PassPrices } from "./pipeline/estimate.js";
import { OpenRouterBackend } from "./pipeline/openrouter.js";
import { MarinRepo } from "./pipeline/repo.js";
import { Ledger, readJson, stateFiles, writeJson } from "./pipeline/state.js";
import { planPass, pricePass, type PassPlan, type PromptModel } from "./pipeline/pass.js";
import { ContextBuilder, describeStats, groupByDirectory, loadUnit, type UnitContext, type Unit } from "./pipeline/units.js";

export const UNITS = ["lib/shellbox/src/shellbox/backends/local", "lib/shellbox/src/shellbox/backends/daytona", "lib/iris/src/iris/actor", "lib/finelog/src/finelog/client"];

/** GPT-6.1 Terra on OpenRouter (`/api/v1/models`, 2026-11-01). */
export const TERRA = "openai/gpt-6.1-terra";

interface ModelSpec {
  label: string;
  /** Set on models that ran on the removed context builder: their results are kept, not rerun. */
  legacy?: boolean;
  effort?: string;
  tier?: string;
  /** Where the run's costs come from, for the report. */
  costSource: string;
  make: (c: ReturnType<typeof loadConfig>) => Backend;
}

const MODELS: Record<string, ModelSpec> = {
  sonnet: { label: "Sonnet 5.5", legacy: true, effort: "medium", costSource: "API usage times the list prices in pricing.ts", make: (c) => new ClaudeBackend(c, "claude-sonnet-5-5", "medium") },
  opus: { label: "Opus 5.5", legacy: true, effort: "medium", costSource: "API usage times the list prices in pricing.ts", make: (c) => new ClaudeBackend(c, "claude-opus-5-5", "medium") },
  glm: { label: "GLM-5.3", legacy: true, costSource: "none: the fleet is self-hosted", make: () => new GlmBackend({ holdMs: 5 * 60_000 }) },
  terra: {
    label: "GPT-6.1 Terra",
    legacy: true,
    effort: "medium",
    tier: "priority",
    costSource: "OpenRouter's reported cost (usage.cost, or the generation record when it is missing)",
    make: (c) => new OpenRouterBackend({ model: TERRA, tier: "priority", effort: "medium", key: openRouterKey(c).key }),
  },
  "terra-full": {
    label: "GPT-6.1 Terra, full context",
    effort: "medium",
    tier: "priority",
    costSource: "OpenRouter's reported cost (usage.cost, or the generation record when it is missing)",
    make: (c) => new OpenRouterBackend({ model: TERRA, tier: "priority", effort: "medium", key: openRouterKey(c).key }),
  },
};

export const MODEL_ORDER = ["sonnet", "opus", "glm", "terra", "terra-full"];

/** What one unit's prompt held, for the context section of the report. */
export interface ContextRecord {
  builder: "legacy" | "full";
  /** o200k tokens of the whole first prompt. */
  o200k: number;
  chars: number;
  tests: number;
  testsDropped: number;
  neighbours: number;
  neighboursDropped: number;
  /** Neighbours given as signatures only (the legacy builder). */
  signatureOnly: boolean;
  outsideLib: string[];
}

export function contextRecord(ctx: UnitContext): ContextRecord {
  const s = ctx.stats;
  return { builder: "full", o200k: s.tokens, chars: s.chars, tests: s.tests.length, testsDropped: s.testsDropped.length, neighbours: s.neighbours.length, neighboursDropped: s.neighboursDropped.length, signatureOnly: false, outsideLib: s.outsideLib };
}

interface UnitRun {
  unit: string;
  ok: boolean;
  error?: string;
  cost_usd: number;
  latency_ms: number;
  input_tokens: number;
  output_tokens: number;
  rewritten: boolean;
  first_lint: number;
  final_lint: number;
  hits: string[];
  entries: Record<string, EntryOut | { keep: true }>;
  /** Per call, for backends that report them: the tier served, the cost source and reasoning tokens. */
  calls?: { served_tier: string | null; cost_source: string; reasoning_tokens: number; input_tokens: number; cache_read_tokens: number; output_tokens: number; cost_usd: number; provider?: string; generation_id?: string }[];
  /** The OpenRouter generation record of the unit's first call. */
  generation?: Record<string, unknown>;
  context?: ContextRecord;
}

export interface ModelRun {
  model: string;
  label: string;
  backend: string;
  at: string;
  commit: string;
  effort?: string;
  tier?: string;
  units: UnitRun[];
  error?: string;
}

interface Results {
  commit: string;
  runs: Record<string, ModelRun>;
  /** The full first pass sized by `--estimate`. */
  pass?: { at: string; current: PassPlan; earlier: PassPlan };
}

async function runModel(key: string, units: Unit[], ctxs: Map<string, UnitContext>, config: ReturnType<typeof loadConfig>, ledger: Ledger, commit: string, prior: ModelRun | undefined): Promise<ModelRun> {
  const m = MODELS[key]!;
  if (m.legacy) {
    process.stderr.write(`compare: ${m.label} ran on the removed context builder; keeping its results${prior ? ` from ${prior.at}` : ""}\n`);
    return prior ?? { model: key, label: m.label, backend: "", at: new Date().toISOString(), commit, units: [], error: "ran on the removed context builder; not rerun" };
  }
  // Units that already succeeded for this model are kept; only failed or missing units run again.
  const kept = (prior?.units ?? []).filter((u) => u.ok && units.some((x) => x.dir === u.unit));
  const run: ModelRun = { model: key, label: m.label, backend: prior?.backend ?? "", at: new Date().toISOString(), commit, ...(m.effort ? { effort: m.effort } : {}), ...(m.tier ? { tier: m.tier } : {}), units: [...kept] };
  let backend: Backend;
  try {
    backend = m.make(config);
    run.backend = backend.name;
  } catch (e) {
    run.error = (e as Error).message;
    return run;
  }
  for (const u of units) {
    if (kept.some((k) => k.unit === u.dir)) {
      process.stderr.write(`compare: ${m.label} on ${u.dir}: kept from ${prior!.at}\n`);
      continue;
    }
    const ctx = ctxs.get(u.dir)!;
    process.stderr.write(`compare: ${m.label} on ${u.dir} (${u.targets.length} files; ${describeStats(ctx.stats)})\n`);
    try {
      const r = await describeUnit(backend, config.prompts, ctx);
      const first = checkOutput(r.completions[0]!.text, u.targets, new Set(), u.package);
      const hits = [...r.lint.entries()].flatMap(([p, hs]) => hs.map((h) => `${p} ${h}`));
      run.units.push({
        unit: u.dir,
        ok: true,
        cost_usd: r.cost_usd,
        latency_ms: r.latency_ms,
        input_tokens: r.completions.reduce((a, c) => a + c.input_tokens, 0),
        output_tokens: r.completions.reduce((a, c) => a + c.output_tokens, 0),
        rewritten: r.rewritten,
        first_lint: [...first.lint.values()].reduce((a, h) => a + h.length, 0),
        final_lint: hits.length,
        hits,
        entries: r.output,
        context: contextRecord(ctx),
      });
      const unitRun = run.units.at(-1)!;
      if (r.completions.some((c) => c.cost_source)) {
        unitRun.calls = r.completions.map((c) => ({
          served_tier: c.served_tier ?? null,
          cost_source: c.cost_source ?? "",
          reasoning_tokens: c.reasoning_tokens ?? 0,
          input_tokens: c.input_tokens,
          cache_read_tokens: c.cache_read_tokens,
          output_tokens: c.output_tokens,
          cost_usd: c.cost_usd,
          ...(c.provider ? { provider: c.provider } : {}),
          ...(c.generation_id ? { generation_id: c.generation_id } : {}),
        }));
        const id = r.completions[0]!.generation_id;
        if (id && backend instanceof OpenRouterBackend) {
          const g = await backend.generation(id);
          if (g) unitRun.generation = g;
        }
      }
      await ledger.add({ at: new Date().toISOString(), kind: "compare", run: `compare ${u.dir}`, model: backend.name, cost_usd: r.cost_usd, latency_ms: r.latency_ms });
      const tiers = unitRun.calls ? `, served ${[...new Set(unitRun.calls.map((c) => c.served_tier ?? "unreported"))].join("/")}, reasoning ${unitRun.calls.reduce((a, c) => a + c.reasoning_tokens, 0)} tokens, cost from ${[...new Set(unitRun.calls.map((c) => c.cost_source))].join("/")}` : "";
      process.stderr.write(`compare: ${m.label} on ${u.dir}: $${r.cost_usd.toFixed(3)}, ${(r.latency_ms / 1000).toFixed(0)} s, lint ${hits.length}${tiers}\n`);
    } catch (e) {
      const cost = (e as { cost_usd?: number }).cost_usd ?? 0;
      run.units.push({ unit: u.dir, ok: false, error: (e as Error).message, cost_usd: cost, latency_ms: 0, input_tokens: 0, output_tokens: 0, rewritten: true, first_lint: 0, final_lint: 0, hits: [], entries: {} });
      if (cost) await ledger.add({ at: new Date().toISOString(), kind: "compare", run: `compare ${u.dir} (failed)`, model: backend.name, cost_usd: cost });
      process.stderr.write(`compare: ${m.label} on ${u.dir} failed: ${(e as Error).message}\n`);
      if (e instanceof TunnelDown || e instanceof FleetHold) {
        run.error = (e as Error).message;
        break;
      }
    }
  }
  return run;
}

const esc = (s: string) => s.replace(/\|/g, "\\|").replace(/\n/g, " ");

/**
 * USD per million tokens for the estimates. First calls pay the cache-write price on both providers:
 * Claude because the poller sets cache_control, and OpenRouter's GPT-6.1 Terra because every uncached
 * prompt token in the 2026-11-01 runs was billed at the listed `input_cache_write` price
 * (`usage.cost` = prompt tokens x $2.50 + output x $10 on priority, to the micro-dollar).
 */
export const ESTIMATE_PRICES: { label: string; model: string; prices: PassPrices; source: string }[] = [
  { label: "Sonnet 5.5", model: "sonnet", prices: { firstInput: 2.5, cachedInput: 0.2, output: 10 }, source: "$2 / $10, cache write $2.50, read $0.20 (claude-api reference)" },
  { label: "Sonnet 5.5, Batch API", model: "sonnet", prices: { firstInput: 1.25, cachedInput: 0.1, output: 5 }, source: "half the Sonnet prices" },
  { label: "Opus 5.5", model: "opus", prices: { firstInput: 5, cachedInput: 0.2, output: 20 }, source: "$4 / $20, cache write $5, read $0.20 (claude-api reference)" },
  { label: "GPT-6.1 Terra, priority", model: "terra", prices: { firstInput: 2.5, cachedInput: 0.1, output: 10 }, source: "$2 / $10, cache write $2.50, read $0.10 (OpenRouter `openai/fast` endpoint)" },
  { label: "GPT-6.1 Terra, default", model: "terra", prices: { firstInput: 1.25, cachedInput: 0.05, output: 5 }, source: "$1 / $5, cache write $1.25, read $0.05 (OpenRouter `openai` endpoint)" },
  { label: "GPT-6.1 Terra, flex", model: "terra", prices: { firstInput: 0.625, cachedInput: 0.025, output: 2.5 }, source: "$0.50 / $2.50, cache write $0.625, read $0.025 (OpenRouter `openai/flex` endpoint)" },
];

/** The cost-model parameters a comparison run measured: output per file, rewrite share, input tokens against Sonnet's. */
export function measuredModel(run: ModelRun, sonnet: ModelRun | undefined): PassModel | null {
  const ok = run.units.filter((u) => u.ok);
  if (!ok.length) return null;
  const files = ok.reduce((a, u) => a + Object.keys(u.entries).length, 0);
  const first = (u: UnitRun) => u.calls?.[0]?.input_tokens ?? u.input_tokens / (u.rewritten ? 2 : 1);
  const mine = ok.reduce((a, u) => a + first(u), 0);
  const theirs = sonnet ? ok.reduce((a, u) => a + (sonnet.units.find((s) => s.unit === u.unit && s.ok) ? first(sonnet.units.find((s) => s.unit === u.unit)!) : 0), 0) : 0;
  return { outPerFile: ok.reduce((a, u) => a + u.output_tokens, 0) / files, rewriteRate: ok.filter((u) => u.rewritten).length / ok.length, tokenRatio: theirs ? mine / theirs : 1 };
}

/** What a run's measured calls would have cost at other prices (prompts here stay under the 272K-token override). */
export function repriced(run: ModelRun, p: { input: number; cachedInput: number; output: number }): number {
  let usd = 0;
  for (const u of run.units.filter((x) => x.ok)) {
    for (const c of u.calls ?? []) usd += ((c.input_tokens - c.cache_read_tokens) * p.input + c.cache_read_tokens * p.cachedInput + c.output_tokens * p.output) / 1e6;
  }
  return usd;
}

function renderEstimates(res: Results, pass: { units: ReturnType<typeof passUnits>; files: number } | null): string[] {
  const out: string[] = [];
  const terra = res.runs.terra;
  if (terra?.units.some((u) => u.ok && u.calls?.length)) {
    // Uncached prompt tokens bill at the cache-write price; the priority repricing checks that against OpenRouter's cost.
    const check = repriced(terra, { input: 2.5, cachedInput: 0.1, output: 10 });
    const def = repriced(terra, { input: 1.25, cachedInput: 0.05, output: 5 });
    const flex = repriced(terra, { input: 0.625, cachedInput: 0.025, output: 2.5 });
    const measured = terra.units.filter((u) => u.ok).reduce((a, u) => a + u.cost_usd, 0);
    out.push(
      "## Estimates under the old context rules",
      "",
      `The same 4 units on GPT-6.1 Terra cost $${measured.toFixed(3)} on the priority tier, as OpenRouter reported it. Repriced from the same token counts, they come to $${check.toFixed(3)} at priority prices, $${def.toFixed(3)} on the default tier and **$${flex.toFixed(3)} on the flex tier**. Uncached prompt tokens are priced at the listed cache-write rate, because that is how OpenRouter billed every call here. The flex prices are $0.50 input, $0.625 cache write, $0.025 cache read and $2.50 output per million tokens. They come from the \`openai/flex\` endpoint in OpenRouter's \`/api/v1/models/${TERRA}/endpoints\` (read 2026-11-01). That is half the default tier, and the priority tier (\`openai/fast\`) is twice the default.`,
    );
  }
  if (!pass) return out;
  const rows: string[] = [];
  for (const e of ESTIMATE_PRICES) {
    const run = res.runs[e.model];
    const m = run ? measuredModel(run, res.runs.sonnet) : null;
    if (!m) continue;
    const c = passCost(pass.units, m, e.prices);
    rows.push(`| ${e.label} | $${c.usd.toFixed(0)} | ${(c.inputTokens / 1e6).toFixed(0)}M | ${(c.outputTokens / 1e6).toFixed(1)}M | ${m.outPerFile.toFixed(0)} | ${(m.rewriteRate * 100).toFixed(0)}% | ${m.tokenRatio.toFixed(2)} | ${e.source} |`);
  }
  if (!rows.length) return out;
  if (!out.length) out.push("## Estimates under the old context rules");
  out.push(
    "",
    `The full first pass covers ${pass.files} non-empty Python files under \`lib/\` in ${pass.units.length} units (directories, split above 280K characters). Each estimate prices one first call per unit and a cached rewrite on the measured share of units. Prompt sizes use Sonnet's measured 2.4 characters per token, 5K template tokens and 36K characters of context per unit, scaled by each model's measured input tokens against Sonnet's on these 4 units. Output per file includes reasoning. GLM-5.3 is left out because it is self-hosted.`,
    "",
    "| Pass | Estimate | Input tokens | Output tokens | Output per file | Units rewritten | Input vs Sonnet | Prices per million tokens |",
    "| --- | --- | --- | --- | --- | --- | --- | --- |",
    ...rows,
  );
  return out;
}

/** Output tokens per test `l1`, reasoning included: an assumption until a run writes test lines. */
export const TEST_L1_TOKENS = 80;

const TERRA_TIERS: { label: string; prices: { firstInput: number; cachedInput: number; output: number } }[] = [
  { label: "flex", prices: { firstInput: 0.625, cachedInput: 0.025, output: 2.5 } },
  { label: "default", prices: { firstInput: 1.25, cachedInput: 0.05, output: 5 } },
  { label: "priority", prices: { firstInput: 2.5, cachedInput: 0.1, output: 10 } },
];

/** The billed prompt tokens per o200k token over a run's first calls. */
export function o200kRatio(run: ModelRun | undefined): { ratio: number; billed: number; o200k: number } | null {
  let billed = 0;
  let o200k = 0;
  for (const u of run?.units ?? []) {
    const first = u.calls?.[0]?.input_tokens;
    if (!u.ok || !u.context || !first) continue;
    billed += first;
    o200k += u.context.o200k;
  }
  return o200k ? { ratio: billed / o200k, billed, o200k } : null;
}

function renderContext(res: Results, units: Unit[]): string[] {
  const legacy = res.runs.terra;
  const full = res.runs["terra-full"];
  if (!legacy?.units.some((u) => u.context) && !full?.units.some((u) => u.context)) return [];
  const out = [
    "## Context per unit",
    "",
    "Old is the builder the first four columns ran on: full sources of the unit, the README cut at 20,000 characters, and up to 30 neighbours from `lib/` as signatures and `l1` lines. New is the builder since 2026-11-02: every file in full, the unit's tests first, neighbours as full modules from anywhere in the checkout but `vendor/`, chosen round-robin across packages, all within 256K o200k tokens for the whole prompt. Measured is the `prompt_tokens` OpenRouter billed for the unit's first call.",
    "",
    "| Unit | Builder | Measured prompt tokens | o200k tokens | Measured / o200k | Tests in prompt | Tests left out | Neighbours in prompt | Neighbours left out | From outside `lib/` |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  ];
  for (const u of units) {
    for (const [name, run] of [["old", legacy], ["new", full]] as const) {
      const x = run?.units.find((y) => y.unit === u.dir);
      const c = x?.context;
      if (!c) continue;
      const billed = x?.calls?.[0]?.input_tokens;
      const outside = c.outsideLib.length ? `${c.outsideLib.length}: ${c.outsideLib.map((p) => `\`${p}\``).join(", ")}` : "0";
      out.push(`| \`${u.dir.replace(/^lib\//, "")}\` | ${name} | ${billed ?? "not run"} | ${c.o200k} | ${billed ? (billed / c.o200k).toFixed(3) : ""} | ${c.tests} | ${c.testsDropped} | ${c.neighbours}${c.signatureOnly ? " (signatures)" : ""} | ${c.neighboursDropped} | ${outside} |`);
    }
  }
  const r = o200kRatio(full);
  const l = o200kRatio(legacy);
  out.push(
    "",
    `OpenRouter does not publish GPT-6.1 Terra's tokenizer, so the budget counts tokens with OpenAI's \`o200k_base\` (js-tiktoken 1.0.21) as a proxy.${l ? ` On the old prompts Terra billed ${l.billed} prompt tokens against ${l.o200k} by o200k (ratio ${l.ratio.toFixed(4)}).` : ""}${r ? ` On the new prompts it billed ${r.billed} against ${r.o200k} (ratio ${r.ratio.toFixed(4)}).` : ""} The difference is the few tokens of chat framing around one user message.`,
  );
  return out;
}

function renderPass(res: Results): string[] {
  const pass = res.pass;
  if (!pass) return [];
  const full = res.runs["terra-full"];
  const ok = full?.units.filter((u) => u.ok) ?? [];
  const files = ok.reduce((a, u) => a + Object.keys(u.entries).length, 0);
  const ratio = o200kRatio(full)?.ratio ?? 1;
  const m: PromptModel = {
    tokenRatio: ratio,
    outPerFile: files ? ok.reduce((a, u) => a + u.output_tokens, 0) / files : 620,
    outPerTest: TEST_L1_TOKENS,
    rewriteRate: ok.length ? ok.filter((u) => u.rewritten).length / ok.length : 0,
  };
  const rows: string[] = [];
  const over: string[] = [];
  for (const plan of [pass.earlier, pass.current]) {
    const priced = TERRA_TIERS.map((t) => pricePass(plan.prompts, m, t.prices));
    const p0 = priced[0]!;
    over.push(...p0.over272k);
    const count = (k: string) => plan.prompts.filter((q) => q.kind === k).length;
    const label = plan.rules === "current" ? "Current: tests ride with their owner unit" : "Earlier: test directories are units";
    rows.push(
      `| ${label} | ${plan.prompts.length} (${count("source")} source, ${count("tests")} test, ${count("orphans")} orphan) | ${plan.splits.length} | ${(plan.prompts.reduce((a, q) => a + q.tokens, 0) / 1e6).toFixed(1)}M | ${(p0.inputTokens / 1e6).toFixed(1)}M | ${(p0.outputTokens / 1e6).toFixed(2)}M | ${priced.map((c) => `$${c.usd.toFixed(0)}`).join(" | ")} |`,
    );
  }
  const cur = pass.current;
  const early = pass.earlier;
  const srcFiles = cur.prompts.reduce((a, q) => a + q.files, 0);
  const testFiles = cur.prompts.reduce((a, q) => a + q.tests, 0);
  const out = [
    "## Full first pass under the new context rules",
    "",
    `Every prompt of the pass was built at \`${pass.current.commit.slice(0, 12)}\` and counted in o200k tokens, without calling a model (\`npm run compare -- --estimate\`, ${pass.at.slice(0, 10)}). The current rules give ${srcFiles} source files full entries and ${testFiles} test files an \`l1\` each: each test rides with the unit it imports the most names from, and ${cur.orphans} tests that import no described code, plus ${cur.overflow} that did not fit beside their owner, go to orphan batches. The earlier rules make each test directory a unit with full entries and neighbours, and make a source unit carry every test that imports it. Billed input is o200k times ${ratio.toFixed(4)}, Terra's measured ratio; output is ${m.outPerFile.toFixed(0)} tokens per source file (measured on the full-context run) and ${TEST_L1_TOKENS} per test \`l1\` (assumed); ${(m.rewriteRate * 100).toFixed(0)}% of prompts get a rewrite turn read from cache. Prompt tokens bill at the cache-write price, as OpenRouter billed every call here.`,
    "",
    "| Rules | Prompts | Split directories | o200k input tokens | Billed input tokens | Output tokens | Terra flex | Terra default | Terra priority |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ...rows,
    "",
    `Prompts over 272K billed tokens, where Terra's long-context prices start: ${over.length ? [...new Set(over)].map((l) => `\`${l}\``).join(", ") : "none"}. Prompts whose fixed part alone passes the 256K budget: ${[...cur.prompts, ...early.prompts].filter((q) => q.overBudget).map((q) => `\`${q.label}\` (${q.tokens})`).join(", ") || "none"}.`,
    "",
  ];
  for (const plan of [cur, early]) {
    out.push(`Directories split under the ${plan.rules} rules (${plan.splits.length}):`, "");
    if (!plan.splits.length) out.push("- none");
    for (const sp of plan.splits) out.push(`- \`${sp.dir}\` (${sp.files} files): ${sp.slices.map((x, i) => `slice ${i + 1} has ${x.files} files and ${x.tests} own tests, ${x.tokens} tokens`).join("; ")}`);
    out.push("");
  }
  const sum = (plan: PassPlan, f: (q: PassPlan["prompts"][number]) => number) => plan.prompts.reduce((a, q) => a + f(q), 0);
  out.push(
    `Neighbours across the pass: the current rules show ${sum(cur, (q) => q.neighbours)} and leave out ${sum(cur, (q) => q.neighboursDropped)}, with ${sum(cur, (q) => q.outsideLib)} test and neighbour files from outside \`lib/\`; tests in prompts ${sum(cur, (q) => q.testsInPrompt)}, left out ${sum(cur, (q) => q.testsDropped)}. The earlier rules show ${sum(early, (q) => q.neighbours)} neighbours and leave out ${sum(early, (q) => q.neighboursDropped)}.`,
  );
  return out;
}

export function renderReport(res: Results, units: Unit[], pass: { units: ReturnType<typeof passUnits>; files: number } | null = null): string {
  const order = MODEL_ORDER.filter((k) => res.runs[k]);
  const runs = order.map((k) => res.runs[k]!);
  const out: string[] = [];
  out.push(
    "# Description model comparison",
    "",
    `The same ${units.reduce((a, u) => a + u.targets.length, 0)} files in ${units.length} directory units, described at Marin commit \`${res.commit.slice(0, 12)}\` with \`prompts/describe-unit.md\` on the first-pass shape, with no existing entries. Sonnet, Opus, GLM-5.3 and the first Terra column got the old context: full sources, the README cut at 20,000 characters, and neighbours from \`lib/\` as signatures and \`l1\` lines. "GPT-6.1 Terra, full context" got the context builder of 2026-11-02, described under "Context per unit": every file in full, the unit's tests, and full neighbour modules from the whole checkout within 256K tokens. Each reply was validated and linted; a reply with problems got one rewrite turn, as in the poller. Generated by \`npm run compare\`; nothing here was written to the wordbase. The verdict is left to the reader.`,
    "",
    `Units: ${units.map((u) => `\`${u.dir.replace(/^lib\//, "")}\` (${u.targets.length})`).join(", ")}.`,
    "",
    "## Totals",
    "",
    "| Model | Backend | Units done | Files | Cost | Latency (sum) | Input tokens | Output tokens | Lint, first draft | Lint, final | Rewrites |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  );
  for (const r of runs) {
    const ok = r.units.filter((u) => u.ok);
    const files = ok.reduce((a, u) => a + Object.keys(u.entries).length, 0);
    const sum = (f: (u: UnitRun) => number) => r.units.reduce((a, u) => a + f(u), 0);
    const calls = r.units.flatMap((u) => u.calls ?? []);
    const served = [...new Set(calls.map((c) => c.served_tier ?? "unreported"))];
    const settings = [r.effort ? `effort ${r.effort}` : "", r.tier ? `tier ${r.tier} requested${calls.length ? `, ${served.join(" and ")} served` : ""}` : ""].filter(Boolean).join(", ");
    out.push(
      `| ${r.label} | \`${r.backend || "unavailable"}\`${settings ? ` (${settings})` : ""} | ${ok.length} of ${units.length} | ${files} | $${sum((u) => u.cost_usd).toFixed(3)}${r.model === "glm" ? " (self-hosted)" : ""} | ${(sum((u) => u.latency_ms) / 1000).toFixed(0)} s | ${sum((u) => u.input_tokens)} | ${sum((u) => u.output_tokens)} | ${sum((u) => u.first_lint)} | ${sum((u) => u.final_lint)} | ${r.units.filter((u) => u.rewritten).length} |`,
    );
  }
  for (const r of runs) if (r.error) out.push("", `${r.label} did not complete: ${r.error}`);
  out.push("", "Where each cost comes from:", "");
  for (const r of runs) {
    const calls = r.units.flatMap((u) => u.calls ?? []);
    const recorded = [...new Set(calls.map((c) => c.cost_source))];
    const reasoning = calls.reduce((a, c) => a + c.reasoning_tokens, 0);
    out.push(`- ${r.label}: ${MODELS[r.model]?.costSource ?? "unknown"}.${recorded.length ? ` The ${calls.length} calls recorded ${recorded.join(" and ")}, and reported ${reasoning} reasoning tokens.` : ""}`);
  }
  const context = renderContext(res, units);
  if (context.length) out.push("", ...context);
  const estimates = renderEstimates(res, pass);
  if (estimates.length) out.push("", ...estimates);
  const full = renderPass(res);
  if (full.length) out.push("", ...full);
  out.push("", "## Per unit", "", "| Unit | " + runs.map((r) => `${r.label} cost / latency / lint`).join(" | ") + " |", "| --- | " + runs.map(() => "---").join(" | ") + " |");
  for (const u of units) {
    const cells = runs.map((r) => {
      const x = r.units.find((y) => y.unit === u.dir);
      if (!x) return "not run";
      if (!x.ok) return `failed: ${esc(x.error ?? "").slice(0, 120)}`;
      return `$${x.cost_usd.toFixed(3)} / ${(x.latency_ms / 1000).toFixed(0)} s / ${x.first_lint} then ${x.final_lint}${x.rewritten ? " (rewritten)" : ""}`;
    });
    out.push(`| \`${u.dir.replace(/^lib\//, "")}\` | ${cells.join(" | ")} |`);
  }
  out.push("", "## Remaining lint hits", "");
  for (const r of runs) {
    const hits = r.units.flatMap((u) => u.hits);
    out.push(`- ${r.label}: ${hits.length ? hits.map((h) => `\`${h.replace(/`/g, "'")}\``).join("; ") : "none"}`);
  }
  out.push("", "## Texts", "");
  for (const u of units) {
    out.push(`### \`${u.dir.replace(/^lib\//, "")}\``, "");
    for (const f of u.targets) {
      out.push(`#### \`${f.split("/").at(-1)}\``, "", "| | " + runs.map((r) => r.label).join(" | ") + " |", "| --- | " + runs.map(() => "---").join(" | ") + " |");
      const get = (r: ModelRun) => {
        const e = r.units.find((y) => y.unit === u.dir)?.entries[f];
        return e && !("keep" in e) ? e : null;
      };
      const row = (label: string, pick: (e: EntryOut) => string) => out.push(`| ${label} | ${runs.map((r) => (get(r) ? esc(pick(get(r)!)) || " " : "(none)")).join(" | ")} |`);
      row("l1", (e) => e.l1);
      row("l2", (e) => e.l2 ?? "");
      row("l3", (e) => (e.l3 ?? []).join(" ¶ "));
      row("symbols", (e) => (e.symbols ?? []).map((s) => `\`${s.name}\`: ${s.l1}`).join(" ¶ "));
      row("lint", (e) => {
        const n = [e.l1, e.l2 ?? "", ...(e.l3 ?? []), ...(e.symbols ?? []).flatMap((s) => [s.l1, s.l2 ?? ""])].reduce((a, t) => a + lint(t).length, 0);
        return String(n);
      });
      out.push("");
    }
  }
  return out.join("\n") + "\n";
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  let models = [...MODEL_ORDER];
  let rev = "HEAD";
  let fresh = false;
  let estimate = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--models") models = (argv[++i] ?? "").split(",").filter(Boolean);
    else if (argv[i] === "--report-only") models = [];
    else if (argv[i] === "--commit") rev = argv[++i] ?? rev;
    else if (argv[i] === "--fresh") fresh = true;
    else if (argv[i] === "--estimate") estimate = true;
    else throw new Error(`unknown flag ${argv[i]}`);
  }
  for (const m of models) if (!MODELS[m]) throw new Error(`unknown model ${m}; use ${Object.keys(MODELS).join(", ")}`);
  const config = loadConfig();
  const files = stateFiles(config.state);
  const repo = new MarinRepo(config.marin);
  const jsonFile = path.join(files.reports, "describe-comparison.json");
  const prior = await readJson<Results | null>(jsonFile, null);
  const commit = prior?.commit ?? (await repo.rev(rev));
  const units: Unit[] = [];
  for (const dir of UNITS) {
    const base = groupByDirectory([`${dir}/x.py`], commit)[0]!;
    const loaded = await loadUnit(repo, { ...base, targets: [] });
    units.push({ ...loaded, targets: loaded.files });
  }
  const total = units.reduce((a, u) => a + u.targets.length, 0);
  process.stderr.write(`compare: ${total} files in ${units.length} units at ${commit.slice(0, 10)}; models ${models.join(", ")}\n`);
  // The comparison describes the same 20 source files as before: tests ride along as context, and no
  // test l1s are asked for, so the texts stay comparable across columns.
  const builder = new ContextBuilder(repo, commit, { wordbase: config.wordbase, prompts: config.prompts, ignoreExisting: true });
  const ctxs = new Map<string, UnitContext>();
  for (const u of units) {
    const planned = await builder.plan({ ...u, testTargets: [] });
    if (planned.units.length !== 1) throw new Error(`${u.dir} splits into ${planned.units.length} slices; the comparison expects whole units`);
    const ctx = await builder.build(planned.units[0]!);
    process.stderr.write(`compare: context ${u.dir}: ${describeStats(ctx.stats)}\n`);
    ctxs.set(u.dir, ctx);
  }
  const ledger = new Ledger(files.spend);
  const runs = await Promise.all(models.map((m) => runModel(m, units, ctxs, config, ledger, commit, fresh ? undefined : prior?.runs[m])));
  const res: Results = { commit, runs: { ...(prior?.runs ?? {}) }, ...(prior?.pass ? { pass: prior.pass } : {}) };
  for (const r of runs) res.runs[r.model] = r;
  if (estimate) {
    const log = (l: string) => process.stderr.write(`estimate: ${l}\n`);
    const opts = { wordbase: config.wordbase, prompts: config.prompts };
    const current = await planPass(repo, commit, opts, "current", log);
    const earlier = await planPass(repo, commit, opts, "earlier", log);
    res.pass = { at: new Date().toISOString(), current, earlier };
  }
  await mkdir(files.reports, { recursive: true });
  await writeJson(jsonFile, res);
  const md = path.join(files.reports, "describe-comparison.md");
  const sizes = await repo.sizes(commit, "lib");
  const passList = passUnits(sizes);
  await writeFile(md, renderReport(res, units, { units: passList, files: passList.reduce((a, u) => a + u.files, 0) }), "utf8");
  for (const r of runs) {
    const cost = r.units.reduce((a, u) => a + u.cost_usd, 0);
    process.stdout.write(`${r.label}: ${r.units.filter((u) => u.ok).length}/${units.length} units, $${cost.toFixed(3)}, lint ${r.units.reduce((a, u) => a + u.final_lint, 0)}${r.error ? `, error: ${r.error}` : ""}\n`);
  }
  process.stdout.write(`report: ${md}\n`);
}

const isEntry = process.argv[1]?.endsWith("/compare.js");
if (isEntry) {
  main().catch((e) => {
    process.stderr.write(`ERROR ${(e as Error).message}\n`);
    process.exitCode = 1;
  });
}
