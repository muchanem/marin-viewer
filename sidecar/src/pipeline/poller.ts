// The poller (DESIGN.md section 8). Each tick updates the Marin clone, describes the Python files
// that new commits on `main` changed, refreshes their subsystem pages, prepares the PRs that request
// Mark's review (and his own), commits the wordbase, and prints one summary line.

import { appendFile, mkdir, rm } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import type { Config } from "../config.js";
import { commitWordbase, fileEntryPath, readEntry, saveEntry, systemEntryPath } from "../wordbase.js";
import { ClaudeBackend, GlmBackend, type Backend } from "./backends.js";
import { describeUnit, writeEntries } from "./describe.js";
import { Gh } from "./exec.js";
import { BackgroundSessions, fetchHeads, preparePr, searchPrs, type SearchedPr } from "./prepare.js";
import { MarinRepo, type Change } from "./repo.js";
import { refreshSystem } from "./systems.js";
import { Ledger, paceUsd, readJson, stateFiles, writeJson, type MainState, type PrsState, type QueueState } from "./state.js";
import { buildContext, groupByDirectory, loadUnit } from "./units.js";
import { runChecker } from "./validate.js";

export interface PollerOptions {
  intervalSec: number;
  monthlyBudgetUsd: number;
  /** Stop starting description units once a tick has spent this much; the rest are queued. */
  maxTickUsd: number;
  backend: "claude" | "glm";
  describeModel: string;
  prepConcurrency: number;
  prepBudgetUsd: number;
  coldReaderBudgetUsd: number;
  prepEffort: "low" | "medium" | "high" | "xhigh";
  describe: boolean;
  prs: boolean;
  /** Prepare only these PR numbers (others are listed as waiting); a number missing from the search is prepared anyway. */
  onlyPrs: number[];
  /** At most this many preparation runs start per tick; the rest wait for the next tick. */
  maxPreps: number;
  unitConcurrency: number;
  user: string;
}

export const DEFAULTS: PollerOptions = {
  intervalSec: 300,
  monthlyBudgetUsd: 200,
  maxTickUsd: 10,
  backend: "claude",
  describeModel: "claude-sonnet-5-5",
  prepConcurrency: 2,
  prepBudgetUsd: 8,
  coldReaderBudgetUsd: 1.5,
  prepEffort: "high",
  describe: true,
  prs: true,
  onlyPrs: [],
  maxPreps: 2,
  unitConcurrency: 2,
  user: "muchanem",
};

export interface TickSummary {
  started: string;
  main: string;
  newCommits: number;
  describedCommits: number;
  files: number;
  units: number;
  kept: number;
  deleted: number;
  renamed: number;
  queued: number;
  systems: number;
  prsListed: number;
  prsPrepared: number;
  prsFailed: number;
  prsWaiting: number;
  costUsd: number;
  monthUsd: number;
  paceUsd: number;
  ghCalls: number;
  errors: number;
  seconds: number;
  gap: string | null;
  initialised: boolean;
}

/** Run `fn` over `items` with at most `n` at once, in order of start. */
export async function pool<T, R>(items: T[], n: number, fn: (item: T, i: number) => Promise<R>): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  const worker = async () => {
    for (let i = next++; i < items.length; i = next++) out[i] = await fn(items[i]!, i);
  };
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, worker));
  return out;
}

export function gapLine(lastTick: string | undefined, now: Date, intervalSec: number): string | null {
  if (!lastTick) return null;
  const gap = (now.getTime() - Date.parse(lastTick)) / 1000;
  if (!(gap > 2 * intervalSec)) return null;
  return `GAP ${Math.round(gap)} s since the last tick at ${lastTick} (interval ${intervalSec} s)`;
}

export function summaryLine(s: TickSummary, opts: Pick<PollerOptions, "monthlyBudgetUsd">): string {
  const d = s.initialised
    ? `initialised at ${s.main.slice(0, 7)}`
    : `described ${s.describedCommits} commits: ${s.files} files in ${s.units} units` +
      (s.kept || s.deleted || s.renamed || s.queued ? ` (${[s.kept && `${s.kept} kept`, s.deleted && `${s.deleted} deleted`, s.renamed && `${s.renamed} renamed`, s.queued && `${s.queued} queued`].filter(Boolean).join(", ")})` : "");
  return [
    `tick ${s.started}`,
    `main ${s.main.slice(0, 7)} (+${s.newCommits} fetched)`,
    d,
    `systems ${s.systems}`,
    `PRs ${s.prsPrepared} prepared, ${s.prsFailed} failed, ${s.prsWaiting} waiting of ${s.prsListed} listed`,
    `cost $${s.costUsd.toFixed(2)}`,
    `month $${s.monthUsd.toFixed(2)} of $${opts.monthlyBudgetUsd} (pace $${s.paceUsd.toFixed(2)})`,
    `gh ${s.ghCalls} calls`,
    `${s.errors} errors`,
    `${s.seconds} s`,
  ].join(" · ");
}

export interface PollerDeps {
  repo?: MarinRepo;
  gh?: Gh;
  backend?: Backend;
  out?: (line: string) => void;
  now?: () => Date;
  checker?: typeof runChecker;
}

export class Poller {
  readonly files: ReturnType<typeof stateFiles>;
  readonly repo: MarinRepo;
  readonly ledger: Ledger;
  private backendInstance: Backend | null;
  private sessions: BackgroundSessions | null = null;
  private readonly out: (line: string) => void;
  private readonly now: () => Date;

  constructor(
    readonly config: Config,
    readonly opts: PollerOptions,
    private readonly deps: PollerDeps = {},
  ) {
    this.files = stateFiles(config.state);
    this.repo = deps.repo ?? new MarinRepo(config.marin);
    this.ledger = new Ledger(this.files.spend);
    this.backendInstance = deps.backend ?? null;
    this.out = deps.out ?? ((l) => process.stdout.write(`${l}\n`));
    this.now = deps.now ?? (() => new Date());
  }

  private get backend(): Backend {
    this.backendInstance ??= this.opts.backend === "glm" ? new GlmBackend({ log: (l) => this.print(`  ${l}`) }) : new ClaudeBackend(this.config, this.opts.describeModel);
    return this.backendInstance;
  }

  print(line: string): void {
    this.out(line);
    void mkdir(path.dirname(this.files.log), { recursive: true })
      .then(() => appendFile(this.files.log, `${this.now().toISOString()} ${line}\n`))
      .catch(() => undefined);
  }

  async tick(): Promise<TickSummary> {
    const t0 = this.now();
    const gh = this.deps.gh ?? new Gh();
    const gh0 = gh.calls;
    const main = await readJson<MainState>(this.files.main, { described: null });
    const s: TickSummary = {
      started: t0.toISOString().replace(/\.\d+Z$/, "Z"),
      main: "",
      newCommits: 0,
      describedCommits: 0,
      files: 0,
      units: 0,
      kept: 0,
      deleted: 0,
      renamed: 0,
      queued: 0,
      systems: 0,
      prsListed: 0,
      prsPrepared: 0,
      prsFailed: 0,
      prsWaiting: 0,
      costUsd: 0,
      monthUsd: 0,
      paceUsd: 0,
      ghCalls: 0,
      errors: 0,
      seconds: 0,
      gap: gapLine(main.last_tick, t0, this.opts.intervalSec),
      initialised: false,
    };
    if (s.gap) this.print(s.gap);
    main.last_tick = t0.toISOString();
    await writeJson(this.files.main, main);
    const error = (what: string, e: unknown) => {
      s.errors++;
      this.print(`ERROR ${what}: ${e instanceof Error ? e.message : String(e)}`);
    };

    // 1. Update Marin.
    try {
      const { before, after } = await this.repo.updateMain();
      s.newCommits = before === after ? 0 : await this.repo.commitCount(before, after);
      if (s.newCommits) this.print(`fetch: main ${before.slice(0, 7)} -> ${after.slice(0, 7)} (${s.newCommits} commits)`);
    } catch (e) {
      error("updating main (going on with the old main)", e);
    }
    const head = await this.repo.rev("HEAD");
    s.main = head;

    // 2. Describe new commits.
    if (this.opts.describe) {
      try {
        await this.describe(main, head, s);
      } catch (e) {
        error("describing new commits", e);
      }
    }

    // 3. Prepare PRs.
    if (this.opts.prs) {
      try {
        await this.preparePrs(gh, s);
      } catch (e) {
        error("preparing PRs", e);
      }
    }

    s.monthUsd = await this.ledger.monthToDate(this.now());
    s.paceUsd = paceUsd(this.opts.monthlyBudgetUsd, this.now());
    s.ghCalls = gh.calls - gh0;
    s.seconds = Math.round((this.now().getTime() - t0.getTime()) / 1000);
    this.print(summaryLine(s, this.opts));
    return s;
  }

  private async describe(main: MainState, head: string, s: TickSummary): Promise<void> {
    if (!main.described) {
      // A fresh poller starts from the current main. Describing all of lib/ is the first pass's job.
      main.described = head;
      main.last_run = { from: null, to: head, read_started: s.started, finished: new Date().toISOString(), files: 0 };
      await writeJson(this.files.main, main);
      s.initialised = true;
      this.print(`init: no state/main.json; recording ${head.slice(0, 7)} as described`);
      return;
    }
    const from = main.described;
    if (!(await this.repo.hasCommit(from))) throw new Error(`state/main.json describes ${from}, which the clone does not have`);
    const queue = await readJson<QueueState>(this.files.queue, { files: [] });
    if (from === head && !queue.files.length) return;

    const readStarted = new Date().toISOString();
    main.in_progress = { from, to: head, read_started: readStarted };
    await writeJson(this.files.main, main);
    s.describedCommits = from === head ? 0 : await this.repo.commitCount(from, head);
    const changes: Change[] = from === head ? [] : await this.repo.changedPython(from, head);
    if (changes.length || s.describedCommits) this.print(`describe: ${s.describedCommits} commits ${from.slice(0, 7)}..${head.slice(0, 7)} change ${changes.length} Python files under lib/`);
    const touched = new Set<string>();
    const systems = new Set<string>();

    // Deletions and renames move or mark entries; they need no model.
    for (const c of changes) {
      if (c.status === "deleted") {
        const file = fileEntryPath(this.config.wordbase, c.path);
        const e = await readEntry(file);
        if (e && !e.front.deleted) {
          e.front.deleted = head;
          e.front.updated = new Date().toISOString().replace(/\.\d+Z$/, "Z");
          await saveEntry(file, e);
          touched.add(file);
          s.deleted++;
          this.print(`  deleted: ${c.path} (entry marked deleted: ${head.slice(0, 7)})`);
        }
      } else if (c.status === "renamed" && c.from) {
        const oldFile = fileEntryPath(this.config.wordbase, c.from);
        const newFile = fileEntryPath(this.config.wordbase, c.path);
        const e = await readEntry(oldFile);
        if (e) {
          e.front.path = c.path;
          await saveEntry(newFile, e);
          await rm(oldFile);
          touched.add(oldFile);
          touched.add(newFile);
          s.renamed++;
          this.print(`  renamed: ${c.from} -> ${c.path} (entry moved)`);
        }
      }
    }

    // Regenerations: changed files plus the deferred queue.
    const fresh = changes.filter((c) => c.status !== "deleted").map((c) => c.path);
    const wanted = [...new Set([...queue.files.map((q) => q.path), ...fresh])];
    const monthUsd = await this.ledger.monthToDate(this.now());
    const pace = paceUsd(this.opts.monthlyBudgetUsd, this.now());
    let deferred: string[] = [];
    let units = groupByDirectory(wanted, head);
    if (monthUsd > pace && units.length) {
      this.print(`  budget: month $${monthUsd.toFixed(2)} is ahead of pace $${pace.toFixed(2)}; deferring ${wanted.length} regenerations`);
      deferred = wanted;
      units = [];
    }
    const loaded = [];
    for (const u of units) {
      const l = await loadUnit(this.repo, u);
      if (l.targets.length) loaded.push(l);
    }
    let tickCost = 0;
    const results = await pool(loaded, this.opts.unitConcurrency, async (unit) => {
      if (tickCost >= this.opts.maxTickUsd) {
        deferred.push(...unit.targets);
        return null;
      }
      try {
        const ctx = await buildContext(this.repo, unit, { wordbase: this.config.wordbase, diffFrom: from === head ? null : from });
        const r = await describeUnit(this.backend, this.config.prompts, ctx);
        tickCost += r.cost_usd;
        await this.ledger.add({
          at: new Date().toISOString(),
          kind: "describe",
          run: `poll ${unit.dir}`,
          model: this.backend.name,
          cost_usd: r.cost_usd,
          input_tokens: r.completions.reduce((a, c) => a + c.input_tokens, 0),
          output_tokens: r.completions.reduce((a, c) => a + c.output_tokens, 0),
          latency_ms: r.latency_ms,
        });
        const w = await writeEntries(this.config.wordbase, r, { commit: head, by: `${this.backend.name} poll ${head.slice(0, 7)}` });
        for (const f of w.files) touched.add(f);
        if (w.l1Changed.length) systems.add(unit.package);
        for (const f of w.files) if (!existsSync(systemEntryPath(this.config.wordbase, unit.package))) systems.add(unit.package);
        this.print(
          `  unit ${unit.dir}: ${w.files.length} written, ${w.kept.length} kept, ${unit.files.length - unit.targets.length} siblings in context, ${ctx.stats.chars} chars, ${r.rewritten ? "rewritten once, " : ""}lint ${w.lintHits}, $${r.cost_usd.toFixed(3)}, ${(r.latency_ms / 1000).toFixed(0)} s`,
        );
        s.units++;
        s.files += w.files.length;
        s.kept += w.kept.length;
        return w;
      } catch (e) {
        tickCost += (e as { cost_usd?: number }).cost_usd ?? 0;
        s.errors++;
        this.print(`ERROR unit ${unit.dir}: ${(e as Error).message}`);
        deferred.push(...unit.targets);
        return null;
      }
    });
    s.costUsd += tickCost;

    // Subsystem pages, once each, at the end of the tick.
    for (const system of [...systems].sort()) {
      try {
        const r = await refreshSystem({ repo: this.repo, commit: head, wordbase: this.config.wordbase, prompts: this.config.prompts, backend: this.backend, system, by: `${this.backend.name} poll ${head.slice(0, 7)}` });
        s.costUsd += r.cost_usd;
        await this.ledger.add({ at: new Date().toISOString(), kind: "system", run: `poll ${system}`, model: this.backend.name, cost_usd: r.cost_usd });
        touched.add(r.file);
        s.systems++;
        this.print(`  system ${system}: ${r.created ? "created" : "refreshed"}, cold reader ${r.gaps.length} gaps, lint ${r.lint.length}, $${r.cost_usd.toFixed(3)}`);
      } catch (e) {
        s.errors++;
        this.print(`ERROR system ${system}: ${(e as Error).message}`);
      }
    }

    // check_fixture.py over the entries this tick wrote.
    const entries = [...touched].filter((f) => f.endsWith(".md") && existsSync(f));
    if (entries.length) {
      const c = await (this.deps.checker ?? runChecker)({ prompts: this.config.prompts, wordbase: this.config.wordbase, marin: this.config.marin, entries, cwd: this.config.root });
      if (c.ok) this.print(`  check_fixture: ${entries.length} entries OK`);
      else for (const f of c.failures) (s.errors++, this.print(`ERROR check_fixture: ${f}`));
    }

    // Persist the queue, commit the wordbase, then advance `described`.
    const keep = new Set(deferred);
    const now = new Date().toISOString();
    queue.files = [...keep].map((p) => ({ path: p, commit: head, change: "modified" as const, queued: now }));
    await writeJson(this.files.queue, queue);
    s.queued = queue.files.length;
    if (touched.size) {
      const written = results.filter(Boolean).length;
      const title = `Describe ${s.files} files changed on main through ${head.slice(0, 7)}`;
      const body = [
        `Regenerates the wordbase entries for the Python files under lib/ that commits ${from.slice(0, 7)}..${head.slice(0, 7)} changed, with ${this.backend.name} over ${written} directory units${s.systems ? `, and refreshes ${s.systems} subsystem pages` : ""}.`,
        [
          s.deleted ? `${s.deleted} entries are marked deleted.` : "",
          s.renamed ? `${s.renamed} entries moved with their files.` : "",
          s.queued ? `${s.queued} files wait in the regeneration queue.` : "",
          `The run cost $${s.costUsd.toFixed(2)}.`,
        ]
          .filter(Boolean)
          .join(" "),
      ].join("\n\n");
      const commit = await commitWordbase(this.config.wordbase, `${title}\n\n${body}`, [...touched]);
      if (commit) this.print(`  wordbase commit ${commit.slice(0, 7)}: ${title}`);
    }
    main.described = head;
    main.last_run = { from, to: head, read_started: readStarted, finished: new Date().toISOString(), files: s.files };
    delete main.in_progress;
    await writeJson(this.files.main, main);
  }

  private async preparePrs(gh: Gh, s: TickSummary): Promise<void> {
    let listed: SearchedPr[];
    try {
      listed = await searchPrs(gh, this.opts.user);
    } catch (e) {
      throw new Error(`gh search prs failed, so no PR list this tick: ${(e as Error).message}`);
    }
    for (const n of this.opts.onlyPrs) if (!listed.some((p) => p.number === n)) listed.push({ number: n, title: "", author: "", reasons: ["named with --pr"] });
    s.prsListed = listed.length;
    this.print(`prs: ${listed.length} listed (${listed.map((p) => `#${p.number} ${p.reasons.join("+")}`).join(", ") || "none"})`);
    if (!listed.length) return;
    const heads = await fetchHeads(this.repo, listed.map((p) => p.number));
    const state = await readJson<PrsState>(this.files.prs, { prs: {} });
    const due = listed.filter((p) => {
      const rec = state.prs[p.number];
      const head = heads.get(p.number)!;
      return !rec || (rec.head !== head && rec.failed_head !== head);
    });
    const selected = (this.opts.onlyPrs.length ? due.filter((p) => this.opts.onlyPrs.includes(p.number)) : due).slice(0, this.opts.maxPreps);
    s.prsWaiting = due.length - selected.length;
    for (const p of listed) if (!due.includes(p)) this.print(`  pr #${p.number}: ${state.prs[p.number]?.status ?? "?"} at ${heads.get(p.number)!.slice(0, 7)}, nothing to do`);
    const waiting = due.filter((p) => !selected.includes(p));
    if (waiting.length) {
      const why = this.opts.onlyPrs.length ? "not named with --pr" : `over --max-preps ${this.opts.maxPreps} for this tick`;
      this.print(`  waiting (${why}): ${waiting.map((p) => `#${p.number}@${heads.get(p.number)!.slice(0, 7)}`).join(", ")}`);
    }
    if (!selected.length) return;
    this.sessions ??= new BackgroundSessions(this.config);
    await pool(selected, this.opts.prepConcurrency, async (p) => {
      const head = heads.get(p.number)!;
      const prior = state.prs[p.number];
      this.print(`  pr #${p.number}: ${prior?.status === "prepared" ? "update" : "prepare"} at ${head.slice(0, 7)} (${p.reasons.join(", ")})`);
      const r = await preparePr(
        {
          config: this.config,
          repo: this.repo,
          gh,
          ledger: this.ledger,
          sessions: this.sessions!,
          log: (l) => this.print(l),
          budgetUsd: this.opts.prepBudgetUsd,
          coldReaderBudgetUsd: this.opts.coldReaderBudgetUsd,
          effort: this.opts.prepEffort,
          user: this.opts.user,
        },
        p,
        head,
        prior,
      );
      state.prs[p.number] = r.record;
      await writeJson(this.files.prs, state);
      s.costUsd += r.record.cost_usd ?? 0;
      if (r.record.status === "prepared") s.prsPrepared++;
      else {
        s.prsFailed++;
        s.errors++;
      }
      const v = r.validation;
      this.print(
        `  pr #${p.number}: ${r.record.status}${v ? `, ${v.counts.steps} steps, ${v.counts.diagrams} diagrams, ${v.counts.notes} notes, ${v.counts.files} files, ${v.problems.length + r.checker.length} validation failures, lint ${v.lint.length}` : ""}, cold reader ${r.gaps.length} gaps, $${(r.record.cost_usd ?? 0).toFixed(2)}${r.commit ? `, wordbase ${r.commit.slice(0, 7)}` : ""}${r.record.error ? `, error: ${r.record.error.slice(0, 200)}` : ""}`,
      );
    });
  }

  async shutdown(): Promise<void> {
    await this.sessions?.manager.shutdown();
  }

  /** Tick every `intervalSec` until `signal` aborts. A tick that overruns starts the next at once. */
  async loop(signal: AbortSignal): Promise<void> {
    while (!signal.aborted) {
      const started = Date.now();
      try {
        await this.tick();
      } catch (e) {
        this.print(`ERROR tick: ${(e as Error).message}`);
      }
      const wait = Math.max(0, this.opts.intervalSec * 1000 - (Date.now() - started));
      await new Promise<void>((resolve) => {
        const t = setTimeout(resolve, wait);
        signal.addEventListener("abort", () => (clearTimeout(t), resolve()), { once: true });
      });
    }
  }
}

