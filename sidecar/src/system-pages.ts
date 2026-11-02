// `npm run system-pages`: one subsystem page per package under `lib/` (DESIGN.md sections 6 and 8),
// written by Claude Fable 5.1 and read cold by Claude Opus 5.5, both on the Console API key. Packages
// go in dependency waves, so a page sees the fresh `l1` of every package it uses.
//
//   npm run system-pages -- [--dry-run] [--only a,b] [--redo a,b] [--cap <usd>] [--concurrency <n>]
//                           [--budget <tokens>] [--excerpt-budget <tokens>] [--excerpt-full-max <tokens>]
//
// --dry-run builds every prompt, counts it with the API's token counter and prints the estimate,
// calling no model. A page whose `by:` names no model run (the #10640 fixture's shellbox page) is
// kept. A restart skips pages this run already wrote at this commit. While it runs,
// `state/system-pages.lock` keeps the poller from ticking.

import { appendFile, mkdir, readdir, rm, writeFile } from "node:fs/promises";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import Anthropic from "@anthropic-ai/sdk";
import { loadConfig } from "./config.js";
import { commitWordbase, readEntry, systemEntryPath } from "./wordbase.js";
import { apiKey, ClaudeBackend } from "./pipeline/backends.js";
import { isGenerated } from "./pipeline/firstpass.js";
import { renderPrompt } from "./pipeline/prompts.js";
import { importGraph, MarinRepo } from "./pipeline/repo.js";
import { PRICES } from "./pipeline/pricing.js";
import { Ledger, readJson, stateFiles, writeJson } from "./pipeline/state.js";
import { dependencyGraph, dependencyWaves, describeSystemStats, neighbourLookup, saveSystemPage, SpendStop, SYSTEM_BUDGET, systemInputs, writeSystemPage, type SystemInputs, type SystemPageResult } from "./pipeline/systems.js";
import { runChecker } from "./pipeline/validate.js";

const WRITER = "claude-fable-5-1";
const READER = "claude-opus-5-5";
/** Output assumed per call for the estimate, thinking included, from the dupekit trial: writer, rewrite, cold reader. */
const OUT = { writer: 2_500, rewrite: 2_000, reader: 1_500 };
/** Opus 5.5 counted the dupekit inputs at 0.71 of Fable 5.1's count. */
const READER_TOKENS = 0.72;

interface Args {
  dryRun: boolean;
  only: string[] | null;
  /** Pages to write again although this run already wrote them. */
  redo: string[];
  capUsd: number;
  concurrency: number;
  budget: number;
  excerptBudget: number | null;
  excerptFullMax: number | null;
}

function parseArgs(argv: string[]): Args {
  const a: Args = { dryRun: false, only: null, redo: [], capUsd: 25, concurrency: 4, budget: SYSTEM_BUDGET, excerptBudget: null, excerptFullMax: null };
  const num = (v: string | undefined, flag: string) => {
    const n = Number(v);
    if (!Number.isFinite(n) || n <= 0) throw new Error(`${flag} needs a positive number`);
    return n;
  };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    const v = () => argv[++i];
    if (f === "--dry-run") a.dryRun = true;
    else if (f === "--only") a.only = (v() ?? "").split(",").filter(Boolean);
    else if (f === "--redo") a.redo = (v() ?? "").split(",").filter(Boolean);
    else if (f === "--cap") a.capUsd = num(v(), f);
    else if (f === "--concurrency") a.concurrency = num(v(), f);
    else if (f === "--budget") a.budget = num(v(), f);
    else if (f === "--excerpt-budget") a.excerptBudget = num(v(), f);
    else if (f === "--excerpt-full-max") a.excerptFullMax = num(v(), f);
    else throw new Error(`unknown flag ${f}`);
  }
  return a;
}

const stamp = () => new Date().toISOString().replace(/\.\d+Z$/, "Z");

interface PageState {
  status: "done" | "failed";
  at: string;
  tokens: number;
  claudeTokens?: number;
  cost_usd: number;
  costByModel: Record<string, number>;
  gapsBefore: number | null;
  gapsAfter: number | null;
  gaps?: { before: unknown[] | null; after: unknown[] | null };
  /** After a rewrite, which version was saved. */
  kept?: "draft" | "rewrite" | null;
  lint: string[];
  problems: string[];
  coldErrors: string[];
  error?: string;
}

interface RunState {
  commit: string;
  started: string;
  pages: Record<string, PageState>;
}

/** What a page should cost: the first call writes the prompt to the cache, the rewrite reads it, and the cold reader reads it twice uncached. */
export function estimatePage(claudeTokens: number): number {
  const w = PRICES[WRITER]!;
  const r = PRICES[READER]!;
  const writer = claudeTokens * w.cacheWrite + OUT.writer * w.output;
  const rewrite = claudeTokens * w.cacheRead + (OUT.writer + 1_500) * w.cacheWrite + OUT.rewrite * w.output;
  const ro = claudeTokens * READER_TOKENS;
  const cold = ro * r.cacheWrite + ro * r.cacheRead + 2 * (2_000 * r.input + OUT.reader * r.output);
  return (writer + rewrite + cold) / 1e6;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const config = loadConfig();
  const files = stateFiles(config.state);
  const repo = new MarinRepo(config.marin);
  const commit = await repo.rev("main");
  const sha7 = commit.slice(0, 7);
  await mkdir(files.runs, { recursive: true });
  const logFile = path.join(files.runs, `system-pages-${sha7}.log`);
  const stateFile = path.join(files.runs, `system-pages-${sha7}.json`);
  const lockFile = path.join(config.state, "system-pages.lock");
  const transcripts = path.join(files.runs, `system-pages-${sha7}`);
  const log = (line: string) => {
    const l = `${stamp()} ${line}`;
    process.stdout.write(`${l}\n`);
    if (!args.dryRun) void appendFile(logFile, `${l}\n`, "utf8");
  };
  const by = `${WRITER} system-pages ${sha7}`;

  const listing = await readdir(path.join(config.wordbase, "lib")).catch(() => [] as string[]);
  if (!listing.length) throw new Error(`the wordbase at ${config.wordbase} lists no entries under lib/; check MARIN_VIEWER_ROOT`);

  const graph = await dependencyGraph(repo, commit);
  const packages = [...graph.keys()].sort();
  log(`plan: Marin ${commit}; ${packages.length} packages under lib/: ${packages.join(", ")}`);
  for (const p of packages) log(`plan: ${p} uses ${graph.get(p)!.uses.join(", ") || "none"}; used by ${graph.get(p)!.used_by.join(", ") || "none"}`);

  // Pages no model wrote are kept; pages this run wrote at this commit are done.
  const state: RunState = (await readJson<RunState | null>(stateFile, null)) ?? { commit, started: stamp(), pages: {} };
  const kept: string[] = [];
  const done: string[] = [];
  const todo: string[] = [];
  for (const p of packages) {
    const e = await readEntry(systemEntryPath(config.wordbase, p));
    const pageBy = e?.front.by;
    if (e && !isGenerated(pageBy)) {
      kept.push(p);
      log(`plan: keep systems/${p}.md: by "${String(pageBy ?? "(none)")}" names no model run`);
    } else if (e && pageBy === by && e.front.commit === commit && !args.redo.includes(p)) done.push(p);
    else {
      if (state.pages[p]?.status === "done" && !args.redo.includes(p)) throw new Error(`the state file records ${p} as done, but systems/${p}.md has by "${String(pageBy)}"; the resume check or the wordbase is wrong`);
      if (e) log(`plan: rewrite systems/${p}.md: by "${String(pageBy)}"`);
      todo.push(p);
    }
  }
  const selected = args.only ? todo.filter((p) => args.only!.includes(p)) : todo;
  if (args.only) for (const o of args.only) if (!packages.includes(o)) throw new Error(`--only names ${o}, which is not a package under lib/`);
  log(`plan: ${selected.length} pages to write, ${done.length} done at ${sha7}${done.length ? ` (${done.join(", ")})` : ""}, ${kept.length} kept (${kept.join(", ") || "none"})`);
  const waves = dependencyWaves(graph, selected);
  log(`plan: ${waves.length} waves: ${waves.map((w, i) => `${i + 1}: ${w.join(", ")}`).join(" · ")}`);

  const t0 = Date.now();
  const imports = await importGraph(repo, commit);
  log(`plan: import graph over ${imports.files.length} files in ${((Date.now() - t0) / 1000).toFixed(0)} s`);
  const neighbourL1 = neighbourLookup(repo, commit, config.wordbase);
  const build = (system: string) =>
    systemInputs({ repo, commit, wordbase: config.wordbase, prompts: config.prompts, system, graph, imports, neighbourL1, budget: args.budget, ...(args.excerptBudget ? { excerptBudget: args.excerptBudget } : {}), ...(args.excerptFullMax ? { excerptFullMax: args.excerptFullMax } : {}) });

  const client = new Anthropic({ apiKey: apiKey(config), maxRetries: 3 });
  const claudeTokens = async (system: string, inputs: SystemInputs) => {
    const prompt = `${await renderPrompt(config.prompts, "describe-system.md", { system, commit })}\n\n${inputs.inputs}`;
    const r = await client.messages.countTokens({ model: WRITER, messages: [{ role: "user", content: prompt }] });
    return r.input_tokens;
  };

  if (args.dryRun) {
    let total = 0;
    for (const wave of waves)
      for (const p of wave) {
        const inputs = await build(p);
        const ct = await claudeTokens(p, inputs);
        const est = estimatePage(ct);
        total += est;
        log(`dry-run ${p}: ${describeSystemStats(inputs.stats)}; ${ct} Claude tokens; estimate $${est.toFixed(2)}`);
        for (const l of inputs.leftOut) log(`dry-run ${p}: left out ${l}`);
      }
    log(`dry-run: ${selected.length} pages, estimate $${total.toFixed(2)} against the $${args.capUsd} cap (writer ${WRITER}, cold reader ${READER})`);
    return;
  }

  if (existsSync(lockFile)) {
    const pid = Number(JSON.parse(readFileSync(lockFile, "utf8")).pid);
    if (pidAlive(pid)) throw new Error(`another subsystem-page run (pid ${pid}) holds ${lockFile}`);
  }
  for (const other of ["first-pass.lock"]) {
    const f = path.join(config.state, other);
    if (existsSync(f) && pidAlive(Number(JSON.parse(readFileSync(f, "utf8")).pid))) throw new Error(`a first pass holds ${f}; two drivers must not write one wordbase`);
  }
  await writeFile(lockFile, JSON.stringify({ pid: process.pid, commit, started: stamp() }), "utf8");
  await writeJson(stateFile, state); // its `started` dates the run for the cap
  const stopLock = () => rm(lockFile, { force: true });
  process.on("SIGINT", () => {
    log("SIGINT: exiting; pages written so far are on disk and the next run resumes after them");
    void stopLock().then(() => process.exit(130));
  });

  const writer = new ClaudeBackend(config, WRITER, "medium");
  const reader = new ClaudeBackend(config, READER, "medium");
  const ledger = new Ledger(files.spend);
  // The cap covers the whole run at this commit, earlier invocations included: their calls are in the ledger.
  const earlier = (await ledger.all()).filter((r) => r.kind === "system" && r.run.startsWith("system-pages ") && r.at >= state.started);
  let spend = earlier.reduce((s, r) => s + r.cost_usd, 0);
  const byModel: Record<string, number> = {};
  for (const r of earlier) byModel[r.model] = (byModel[r.model] ?? 0) + r.cost_usd;
  if (earlier.length) log(`spend: $${spend.toFixed(2)} from ${earlier.length} earlier calls of this run counts toward the cap`);
  let stopped: string | null = null;
  const commits: string[] = [];
  const results = new Map<string, SystemPageResult>();

  const runPage = async (p: string) => {
    const t = Date.now();
    const inputs = await build(p);
    const ct = await claudeTokens(p, inputs);
    log(`page ${p}: ${describeSystemStats(inputs.stats)}; ${ct} Claude tokens; estimate $${estimatePage(ct).toFixed(2)}`);
    for (const l of inputs.leftOut) log(`page ${p}: left out ${l}`);
    const est = { writer: (ct * PRICES[WRITER]!.cacheWrite + OUT.writer * PRICES[WRITER]!.output) / 1e6, reader: ((ct * READER_TOKENS + 2_000) * PRICES[READER]!.cacheWrite + OUT.reader * PRICES[READER]!.output) / 1e6 };
    try {
      const r = await writeSystemPage({
        inputs,
        prompts: config.prompts,
        writer,
        reader,
        beforeCall: (role) => {
          const next = role.startsWith("cold") ? est.reader : role === "writer" ? est.writer : est.writer / 4;
          if (stopped) throw new SpendStop(stopped);
          if (spend + next > args.capUsd) {
            stopped = `spend cap: $${spend.toFixed(2)} spent and the next ${role} call for ${p} would cost about $${next.toFixed(2)}, past the $${args.capUsd} cap`;
            log(`ERROR ${stopped}; no new calls start`);
            throw new SpendStop(stopped);
          }
        },
        afterCall: (c) => {
          spend += c.completion.cost_usd;
          byModel[c.completion.model] = (byModel[c.completion.model] ?? 0) + c.completion.cost_usd;
          void ledger.add({ at: new Date().toISOString(), kind: "system", run: `system-pages ${p} ${c.role}`, model: c.completion.model, cost_usd: c.completion.cost_usd, input_tokens: c.completion.input_tokens, output_tokens: c.completion.output_tokens, latency_ms: c.completion.latency_ms });
          log(`call ${p} ${c.role}: ${c.completion.model} · ${c.completion.input_tokens} in (${c.completion.cache_read_tokens} cached) · ${c.completion.output_tokens} out · $${c.completion.cost_usd.toFixed(3)} · ${(c.completion.latency_ms / 1000).toFixed(0)} s · spend $${spend.toFixed(2)}`);
        },
      });
      const file = await saveSystemPage(config.wordbase, inputs, r, by);
      await mkdir(transcripts, { recursive: true });
      await writeJson(path.join(transcripts, `${p}.json`), { system: p, calls: r.calls.map((c) => ({ role: c.role, model: c.completion.model, text: c.completion.text })) });
      results.set(p, r);
      state.pages[p] = {
        status: "done",
        at: stamp(),
        tokens: inputs.stats.tokens,
        claudeTokens: ct,
        cost_usd: r.cost_usd,
        costByModel: r.costByModel,
        gapsBefore: r.gapsBefore?.length ?? null,
        gapsAfter: r.gapsAfter?.length ?? (r.rewritten ? null : (r.gapsBefore?.length ?? null)),
        gaps: { before: r.gapsBefore, after: r.gapsAfter },
        kept: r.kept,
        lint: r.lint,
        problems: r.problems,
        coldErrors: r.coldErrors,
      };
      await writeJson(stateFile, state);
      log(
        `page ${p} written to ${path.relative(config.wordbase, file)}: cold reader ${r.gapsBefore?.length ?? "failed"} gaps before, ${r.rewritten ? `${r.gapsAfter?.length ?? "failed"} after the rewrite${r.kept === "draft" ? " (kept the first draft)" : ""}` : "no rewrite"} · lint ${r.lint.length} · problems ${r.problems.length}${r.diagramDropped ? " (map dropped)" : ""}${r.coldErrors.length ? ` · ERROR cold reader: ${r.coldErrors.join("; ")}` : ""} · $${r.cost_usd.toFixed(2)} (${Object.entries(r.costByModel).map(([m, c]) => `${m} $${c.toFixed(2)}`).join(", ")}) · ${((Date.now() - t) / 1000).toFixed(0)} s`,
      );
      log(`page ${p} l1: ${r.page.l1}`);
    } catch (e) {
      state.pages[p] = { status: "failed", at: stamp(), tokens: inputs.stats.tokens, claudeTokens: ct, cost_usd: 0, costByModel: {}, gapsBefore: null, gapsAfter: null, lint: [], problems: [], coldErrors: [], error: (e as Error).message.slice(0, 400) };
      await writeJson(stateFile, state);
      log(`ERROR page ${p}: ${(e as Error).message.slice(0, 400)}`);
    }
  };

  try {
    for (const [i, wave] of waves.entries()) {
      if (stopped) break;
      log(`wave ${i + 1} of ${waves.length}: ${wave.join(", ")}`);
      const queue = [...wave];
      await Promise.all(
        Array.from({ length: Math.min(args.concurrency, queue.length) }, async () => {
          for (let p = queue.shift(); p; p = queue.shift()) if (!stopped) await runPage(p);
        }),
      );
      const written = wave.filter((p) => state.pages[p]?.status === "done" && results.has(p));
      if (!written.length) continue;
      const entries = written.map((p) => systemEntryPath(config.wordbase, p));
      const chk = await runChecker({ prompts: config.prompts, wordbase: config.wordbase, marin: config.marin, entries, cwd: config.root });
      log(chk.ok ? `check_fixture: ${entries.length} pages OK` : `ERROR check_fixture: ${chk.failures.join(" | ")}`);
      const lines = written.map((p) => {
        const s = state.pages[p]!;
        return `${p}: cold-reader gaps ${s.gapsBefore ?? "?"} before and ${s.gapsAfter ?? "?"} after the rewrite, ${s.lint.length} lint hits left, $${s.cost_usd.toFixed(2)}.`;
      });
      const named = `Write the subsystem pages for ${written.join(", ")} at ${sha7}`;
      const title = named.length <= 72 ? named : `Write ${written.length} subsystem pages at ${sha7}`;
      const body = `${WRITER} wrote these pages from each package's file entries, README, entry-point source and neighbours, and ${READER} read each one cold before and after one rewrite.\n\n${lines.join("\n")}`;
      const sha = await commitWordbase(config.wordbase, `${title}\n\n${body}`, entries);
      if (sha) {
        commits.push(sha);
        log(`wordbase commit ${sha.slice(0, 7)}: ${written.length} pages`);
      }
    }
  } finally {
    await stopLock();
  }
  const failed = Object.entries(state.pages).filter(([, s]) => s.status === "failed").map(([p]) => p);
  log(
    `run ${stopped ? "cap" : failed.length ? "incomplete" : "complete"}: ${results.size} pages written, ${failed.length} failed${failed.length ? ` (${failed.join(", ")})` : ""} · spend $${spend.toFixed(2)} of the $${args.capUsd} cap · by model ${Object.entries(byModel).map(([m, c]) => `${m} $${c.toFixed(2)}`).join(", ") || "none"} · ${((Date.now() - t0) / 60_000).toFixed(1)} min · wordbase commits ${commits.map((c) => c.slice(0, 7)).join(", ") || "none"}`,
  );
  if (stopped || failed.length) process.exitCode = 2;
}

function pidAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

const isEntry = process.argv[1]?.endsWith("/system-pages.js");
if (isEntry)
  main().catch((e) => {
    process.stderr.write(`system-pages: ${(e as Error).stack ?? e}\n`);
    process.exit(1);
  });
