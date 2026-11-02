// `npm run first-pass`: the first full pass of file descriptions (DESIGN.md section 8). GPT-6.1 Terra
// on OpenRouter's flex tier, pinned to the flex endpoint, effort medium; every source unit and slice
// at the clone's current main, then the orphan test batch. Subsystem pages are not part of it.
//
//   npm run first-pass -- [--dry-run] [--check] [--window <n>] [--max-window <n>] [--cap <usd>]
//                         [--commit-every <units>] [--limit <units>]
//
// --dry-run prints the plan, the protected entries and what is already done, and calls no model.
// --check runs only the completion count. A restart skips units whose entries cover their files at
// the pass's commit. While it runs, `state/first-pass.lock` keeps the poller from ticking.

import { appendFile, mkdir, readdir, rm, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { loadConfig, openRouterKey } from "./config.js";
import { commitWordbase, fileEntryPath, readEntry } from "./wordbase.js";
import { describeUnit, writeEntries } from "./pipeline/describe.js";
import { FIRST_PASS_DEFAULTS, FirstPassRunner, isGenerated, resumeCheck, type PassJob, type PassState, type RunnerOptions } from "./pipeline/firstpass.js";
import { OpenRouterBackend } from "./pipeline/openrouter.js";
import { planJobs, type PassPlan } from "./pipeline/pass.js";
import { isTestPath, MarinRepo } from "./pipeline/repo.js";
import { Ledger, readJson, stateFiles, writeJson } from "./pipeline/state.js";
import { ContextBuilder, describeStats } from "./pipeline/units.js";
import { runChecker } from "./pipeline/validate.js";

const MODEL = "openai/gpt-6.1-terra";
/** Flex prices per million tokens: prompt tokens bill at the cache-write price, as every call so far did. */
const FLEX = { firstInput: 0.625, output: 2.5 };
const OUT_PER_FILE = 637;
const OUT_PER_TEST = 80;

interface Args {
  dryRun: boolean;
  check: boolean;
  limit: number | null;
  opts: RunnerOptions;
}

function parseArgs(argv: string[]): Args {
  const a: Args = { dryRun: false, check: false, limit: null, opts: { ...FIRST_PASS_DEFAULTS } };
  const num = (v: string | undefined, flag: string) => {
    const n = Number(v);
    if (!Number.isFinite(n) || n <= 0) throw new Error(`${flag} needs a positive number`);
    return n;
  };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    const v = () => argv[++i];
    if (f === "--dry-run") a.dryRun = true;
    else if (f === "--check") a.check = true;
    else if (f === "--window") a.opts.window = num(v(), f);
    else if (f === "--max-window") a.opts.maxWindow = num(v(), f);
    else if (f === "--cap") a.opts.capUsd = num(v(), f);
    else if (f === "--commit-every") a.opts.commitEvery = num(v(), f);
    else if (f === "--limit") a.limit = num(v(), f);
    else throw new Error(`unknown flag ${f}`);
  }
  return a;
}

const stamp = () => new Date().toISOString().replace(/\.\d+Z$/, "Z");

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const config = loadConfig();
  const files = stateFiles(config.state);
  const repo = new MarinRepo(config.marin);
  const commit = await repo.rev("main");
  const sha7 = commit.slice(0, 7);
  await mkdir(files.runs, { recursive: true });
  const logFile = path.join(files.runs, `first-pass-${sha7}.log`);
  const stateFile = path.join(files.runs, `first-pass-${sha7}.json`);
  const lockFile = path.join(config.state, "first-pass.lock");
  const log = (line: string) => {
    const l = `${stamp()} ${line}`;
    process.stdout.write(`${l}\n`);
    if (!args.dryRun) void appendFile(logFile, `${l}\n`, "utf8");
  };
  const by = `${MODEL} first-pass ${sha7}`;

  // Fail closed on a wordbase that lists nothing: a wrong root would read as "nothing is done".
  const listing = await readdir(path.join(config.wordbase, "lib")).catch(() => [] as string[]);
  if (!listing.length) throw new Error(`the wordbase at ${config.wordbase} lists no entries under lib/; check MARIN_VIEWER_ROOT`);

  log(`plan: Marin ${commit} (main of ${config.marin}); wordbase ${config.wordbase}`);
  const builder = new ContextBuilder(repo, commit, { wordbase: config.wordbase, prompts: config.prompts, ignoreExisting: true, mandatoryTests: "owned" });
  const plan = await planJobs(builder, "current", (l) => log(`plan: ${l}`));

  // Entries no model wrote (the #10640 fixture) are never overwritten: their files leave the targets
  // and stay in the prompt as context.
  const protectedFiles: { path: string; by: string }[] = [];
  const jobs: PassJob[] = [];
  const estimates = storedEstimates(path.join(files.reports, "describe-comparison.json"), commit);
  for (const j of plan.jobs) {
    const keep = async (list: string[]) => {
      const out: string[] = [];
      for (const f of list) {
        const e = await readEntry(fileEntryPath(config.wordbase, f));
        if (e && !e.front.deleted && !isGenerated(e.front.by)) protectedFiles.push({ path: f, by: String(e.front.by ?? "(no by:)") });
        else out.push(f);
      }
      return out;
    };
    const targets = await keep(j.unit.targets);
    const testTargets = await keep(j.unit.testTargets ?? []);
    const unit = { ...j.unit, targets, testTargets };
    jobs.push({ label: j.label, unit, siblings: j.siblings, owned: [...targets, ...testTargets], estimateUsd: estimates?.get(j.label) ?? 0 });
  }
  const expectedSource = jobs.reduce((a, j) => a + j.unit.files.length * Number(j.unit.kind !== "orphans"), 0);
  const ownedTests = jobs.reduce((a, j) => a + (j.unit.testTargets ?? []).length, 0);
  log(`plan: ${jobs.length} prompts (${jobs.filter((j) => j.unit.kind !== "orphans").length} source units or slices, ${jobs.filter((j) => j.unit.kind === "orphans").length} orphan batch) covering ${expectedSource} source files and ${ownedTests} test files to write; ${plan.splits.length} split (${plan.splits.map((s) => `${s.dir} into ${s.slices.length}`).join(", ") || "none"}); ${plan.orphans} orphan tests, ${plan.overflow} overflow`);
  log(`plan: ${protectedFiles.length} files keep entries no model wrote and are context only: ${protectedFiles.map((p) => `${p.path} (${p.by})`).join(", ") || "none"}`);
  const estTotal = jobs.reduce((a, j) => a + j.estimateUsd, 0);
  log(estimates ? `plan: estimate $${estTotal.toFixed(2)} on flex from the comparison's sizing at this commit` : "plan: no stored sizing for this commit; the estimate is unknown until units run");

  // Resumption.
  const isDone = async (j: PassJob) => {
    for (const f of j.owned) {
      const e = await readEntry(fileEntryPath(config.wordbase, f));
      if (!e || e.front.deleted || e.front.commit !== commit) return false;
    }
    return true;
  };
  const prior = await readJson<PassState | null>(stateFile, null);
  const { done, verified } = await resumeCheck(jobs, prior, isDone);
  if (verified) {
    const j = jobs.find((x) => x.label === verified)!;
    const e = (await readEntry(fileEntryPath(config.wordbase, j.owned[0]!)))!;
    log(`resume: ${done.size} of ${jobs.length} units already done; verified against ${verified}: ${j.owned[0]} has commit ${String(e.front.commit).slice(0, 7)}, by "${String(e.front.by)}"`);
  } else log(`resume: ${done.size} of ${jobs.length} units already done${prior ? "" : " (no state file yet)"}`);
  const todo = jobs.filter((j) => !done.has(j.label)).slice(0, args.limit ?? undefined);

  if (args.check) {
    await completionCheck(jobs, commit, config.wordbase, prior, protectedFiles.map((p) => p.path), log);
    return;
  }
  if (args.dryRun) {
    for (const j of todo) log(`would run ${j.label}: ${j.unit.files.length} files in the prompt, ${j.unit.targets.length} to write, ${(j.unit.tests ?? []).length} own tests, ${(j.unit.testTargets ?? []).length} test l1s${j.estimateUsd ? `, about $${j.estimateUsd.toFixed(3)}` : ""}`);
    log(`dry run: ${todo.length} units to run, estimated $${todo.reduce((a, j) => a + j.estimateUsd, 0).toFixed(2)} on flex; cap $${args.opts.capUsd}; window ${args.opts.window} (max ${args.opts.maxWindow}); no model called`);
    return;
  }

  if (existsSync(lockFile)) {
    const pid = Number(JSON.parse(readFileSync(lockFile, "utf8")).pid);
    if (pidAlive(pid)) throw new Error(`another first pass (pid ${pid}) holds ${lockFile}`);
  }
  await writeFile(lockFile, JSON.stringify({ pid: process.pid, commit, started: stamp() }), "utf8");
  const state: PassState = prior?.commit === commit ? prior : { commit, started: stamp(), units: {} };
  const ledger = new Ledger(files.spend);
  const backend = new OpenRouterBackend({ model: MODEL, tier: "flex", effort: "medium", key: openRouterKey(config).key, provider: { only: ["openai/flex"], allow_fallbacks: false }, attempts: 1, log: (l) => log(l) });
  const runner = new FirstPassRunner(
    {
      backend,
      build: async (j) => {
        const ctx = await builder.build(j.unit, { siblings: j.siblings });
        if (ctx.stats.overBudget) log(`WARN ${j.label}: ${describeStats(ctx.stats)}`);
        return ctx;
      },
      describe: (b, ctx) => describeUnit(b, config.prompts, ctx, { salvage: true }),
      write: async (j, r) => {
        const w = await writeEntries(config.wordbase, r, { commit, by });
        await ledger.add({ at: new Date().toISOString(), kind: "first-pass", run: `first-pass ${j.label}`, model: MODEL, cost_usd: r.cost_usd, input_tokens: r.completions.reduce((a, c) => a + c.input_tokens, 0), output_tokens: r.completions.reduce((a, c) => a + c.output_tokens, 0), latency_ms: r.latency_ms });
        const linted = [...r.lint.entries()].filter(([p, h]) => h.length && (p in r.output || p in r.tests)).length;
        return { files: w.files, tests: w.tests.length, linted };
      },
      commit: async (written, units) => {
        const chk = await runChecker({ prompts: config.prompts, wordbase: config.wordbase, marin: config.marin, entries: written, cwd: config.root });
        // The pass writes no subsystem pages, so every entry naming a system other than shellbox fails
        // "system X has no entry" until those pages exist. Count those; print anything else in full.
        const noSystem = chk.failures.filter((f) => /: system \S+ has no entry$/.test(f));
        const other = chk.failures.filter((f) => !noSystem.includes(f));
        if (noSystem.length) log(`check_fixture: ${noSystem.length} of ${written.length} entries name a system with no page yet (expected: subsystem pages wait for a model decision)`);
        for (const f of other.slice(0, 20)) log(`ERROR check_fixture: ${f}`);
        if (other.length > 20) log(`ERROR check_fixture: ${other.length - 20} more failures`);
        const title = `Describe ${written.length} files in ${units.length} units of the first pass at ${sha7}`;
        const body = `Writes the first-pass entries that ${MODEL} on the flex tier produced for ${units.length} description units at Marin ${sha7}: ${units.slice(0, 6).join(", ")}${units.length > 6 ? `, and ${units.length - 6} more` : ""}. Source files get full entries and test files a one-sentence l1.`;
        return commitWordbase(config.wordbase, `${title}\n\n${body}`, written);
      },
      saveState: (s) => writeJson(stateFile, s),
      log,
      now: () => Date.now(),
      sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    },
    { ...args.opts, estimateUsd: estTotal || args.opts.estimateUsd },
    state,
  );
  const stopLock = () => rm(lockFile, { force: true });
  process.on("SIGINT", () => {
    log("SIGINT: no new units start; the units in flight finish (send it again to exit at once)");
    if (runner.stopping) process.exit(130);
    runner.stopping = "interrupted";
  });
  log(`run: ${todo.length} units, window ${args.opts.window} (max ${args.opts.maxWindow}), cap $${args.opts.capUsd}, tier flex pinned to openai/flex`);
  try {
    const s = await runner.run(todo);
    log(
      `run ${s.status}: ${s.done} done, ${s.failed} failed, ${s.notStarted} not started · ${s.calls} calls, ${s.retries} capacity retries · spend $${s.spendUsd.toFixed(2)} against $${estTotal.toFixed(2)} estimated · by tier ${Object.entries(s.byTier).map(([t, c]) => `${t} $${c.toFixed(2)}`).join(", ") || "none"} · window peak ${s.peakWindow}, final ${s.finalWindow} · ${(s.wallMs / 60_000).toFixed(1)} min · wordbase commits ${s.commits.map((c) => c.slice(0, 7)).join(", ") || "none"}`,
    );
    await completionCheck(jobs, commit, config.wordbase, state, protectedFiles.map((p) => p.path), log);
    if (s.status !== "complete") process.exitCode = 2;
  } finally {
    await stopLock();
  }
}

function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/** Per-prompt flex estimates from the comparison's `--estimate` sizing, when it was made at this commit. */
function storedEstimates(file: string, commit: string): Map<string, number> | null {
  if (!existsSync(file)) return null;
  const res = JSON.parse(readFileSync(file, "utf8")) as { pass?: { current: PassPlan } };
  const cur = res.pass?.current;
  if (!cur || cur.commit !== commit) return null;
  return new Map(cur.prompts.map((q) => [q.label, (q.tokens * FLEX.firstInput + (q.files * OUT_PER_FILE + q.tests * OUT_PER_TEST) * FLEX.output) / 1e6]));
}

/**
 * Count files with entries at the pass's commit against files expected, source and tests apart, and
 * list each missing file with the reason its unit gives. The count, not the exit code, says done.
 */
export async function completionCheck(jobs: PassJob[], commit: string, wordbase: string, state: PassState | null, protectedFiles: string[], log: (l: string) => void): Promise<{ missing: number }> {
  const owner = new Map<string, string>();
  const expected = { source: new Set<string>(), tests: new Set<string>() };
  for (const j of jobs) {
    if (j.unit.kind !== "orphans") for (const f of j.unit.files) expected.source.add(f);
    for (const t of j.unit.testTargets ?? []) expected.tests.add(t);
    for (const f of j.owned) owner.set(f, j.label);
  }
  const prot = new Set(protectedFiles);
  for (const p of prot) (isTestPath(p) ? expected.tests : expected.source).add(p);
  const missing: string[] = [];
  let linted = 0;
  const counts = { source: 0, tests: 0, protectedSource: 0, protectedTests: 0 };
  for (const [kind, set] of [["source", expected.source], ["tests", expected.tests]] as const) {
    for (const f of [...set].sort()) {
      if (prot.has(f)) {
        counts[kind === "source" ? "protectedSource" : "protectedTests"]++;
        continue;
      }
      const e = await readEntry(fileEntryPath(wordbase, f));
      if (e && !e.front.deleted && e.front.commit === commit) {
        counts[kind]++;
        if (Array.isArray(e.front.lint) && e.front.lint.length) linted++;
        continue;
      }
      const label = owner.get(f);
      const u = label ? state?.units[label] : undefined;
      const why = !label ? "no unit owns it" : !u ? "its unit has not run" : u.status === "failed" ? `its unit failed: ${u.error ?? "unknown"}` : u.problems?.length ? `missing from the reply after the rewrite (${u.problems.slice(0, 2).join("; ")})` : `its unit is ${u.status} but wrote no entry`;
      missing.push(`${f}: ${why}${label ? ` [${label}]` : ""}`);
    }
  }
  log(
    `check: source files ${counts.source} written + ${counts.protectedSource} hand-written kept of ${expected.source.size} expected; test files ${counts.tests} written + ${counts.protectedTests} kept of ${expected.tests.size} expected; ${missing.length} missing; ${linted} entries carry a lint: field`,
  );
  for (const m of missing) log(`missing ${m}`);
  return { missing: missing.length };
}

const isEntry = process.argv[1]?.endsWith("/first-pass.js");
if (isEntry) {
  main().catch((e) => {
    process.stderr.write(`ERROR ${(e as Error).message}\n`);
    process.exitCode = 1;
  });
}
