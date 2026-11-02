// The first full pass (DESIGN.md section 8, "First full pass"): every source unit and slice under
// `lib/`, then the orphan test batch, described with GPT-6.1 Terra on OpenRouter's flex tier. This
// module holds the parts that decide what runs and when, with every effect injected so the tier
// guard, the spend cap, the window and resumption can be tested without a network or a repository.
//
// - Sliding window: up to `window` units in flight; the window grows while calls come back clean
//   and quick, and halves on a capacity error, which is retried with backoff.
// - Tier guard: a call served on any tier other than the one requested stops new work; the units in
//   flight finish, and the run ends with status "tier".
// - Spend cap: no unit starts once reported spend (OpenRouter `usage.cost`) reaches the cap.
// - Resumption: a unit is done when every file it owns has an entry at the pass's commit. A unit the
//   run's state file records as done must also read as done, or the run refuses to start.

import type { Backend, Completion, Turn } from "./backends.js";
import type { UnitResult } from "./describe.js";
import type { Unit, UnitContext } from "./units.js";

export interface PassJob {
  label: string;
  unit: Unit;
  siblings: string[];
  /** The files this unit writes: source targets and test targets, less protected entries. */
  owned: string[];
  /** What the estimate expects this unit to cost, for the running comparison. */
  estimateUsd: number;
}

export type UnitStatus = "done" | "failed" | "skipped";

export interface PassState {
  commit: string;
  started: string;
  units: Record<string, { status: UnitStatus; at: string; cost_usd: number; files: number; error?: string; problems?: string[] }>;
}

export interface Written {
  files: string[];
  tests: number;
  /** Entries written with a `lint:` field. */
  linted: number;
}

export interface RunnerDeps {
  backend: Backend;
  build(job: PassJob): Promise<UnitContext>;
  describe(backend: Backend, ctx: UnitContext): Promise<UnitResult>;
  write(job: PassJob, result: UnitResult): Promise<Written>;
  /** Commit the wordbase files written since the last commit. */
  commit(files: string[], units: string[]): Promise<string | null>;
  saveState(state: PassState): Promise<void>;
  log(line: string): void;
  now(): number;
  sleep(ms: number): Promise<void>;
}

export interface RunnerOptions {
  tier: string;
  window: number;
  maxWindow: number;
  capUsd: number;
  /** The whole pass's estimate, for the progress lines. */
  estimateUsd: number;
  commitEvery: number;
  /** Attempts per call for capacity errors (429, 5xx, flex capacity, dropped connections). */
  attempts: number;
  /** A GAP line after this long with no unit finishing. */
  gapMs: number;
  /** Stop after this many units fail in a row with none succeeding in between. */
  maxConsecutiveFailures: number;
}

export const FIRST_PASS_DEFAULTS: RunnerOptions = {
  tier: "flex",
  window: 128,
  maxWindow: 256,
  capUsd: 35,
  estimateUsd: 17,
  commitEvery: 20,
  attempts: 8,
  gapMs: 5 * 60_000,
  maxConsecutiveFailures: 8,
};

export type StopReason = "complete" | "cap" | "tier" | "credit" | "failures" | "interrupted";

export interface RunSummary {
  status: StopReason;
  spendUsd: number;
  /** Reported cost by the tier that served each call. */
  byTier: Record<string, number>;
  calls: number;
  /** Capacity errors retried. */
  retries: number;
  done: number;
  failed: number;
  notStarted: number;
  peakWindow: number;
  finalWindow: number;
  commits: string[];
  wallMs: number;
}

/** A capacity or transport failure worth retrying: 429, 5xx, flex capacity, a dropped stream. */
export function isCapacityError(e: unknown): boolean {
  const status = (e as { status?: number | null }).status;
  if (typeof status === "number") return status === 429 || status === 408 || status >= 500;
  const m = (e as Error).message ?? "";
  return /capacity|rate.?limit|overloaded|temporarily|try again|timed? ?out|ECONNRESET|ETIMEDOUT|fetch failed|socket|terminated|network/i.test(m);
}

/** Out of OpenRouter credit (402): every later call fails the same way. */
export function isPaymentError(e: unknown): boolean {
  const status = (e as { status?: number | null }).status;
  return status === 402 || /insufficient credits|payment required/i.test((e as Error).message ?? "");
}

/**
 * The window of calls in flight. It starts at `start`; after `size` clean completions since the
 * last change, with the median latency of those no worse than twice the first round's, it grows by
 * half. A capacity error halves it (not below 4), restarts the count and pauses every new call for
 * the backoff. Every attempt, a retry included, takes a slot with `acquire`, so a halved window
 * holds the calls in flight to the new size rather than only the units started after it.
 *
 * Errors from one burst count once: a call reports the epoch it started in, and only an error from
 * the current epoch halves the window. Without that, 128 calls failing together halve it to 4 in a
 * second (the first live run, 2026-11-02).
 */
export class Window {
  size: number;
  peak: number;
  inFlight = 0;
  epoch = 0;
  private clean: number[] = [];
  private baseline: number | null = null;
  private pausedUntil = 0;
  private waiters: (() => void)[] = [];

  constructor(
    start: number,
    private readonly max: number,
    private readonly log: (line: string) => void,
    private readonly clock: { now(): number; sleep(ms: number): Promise<void> } = { now: Date.now, sleep: (ms) => new Promise((r) => setTimeout(r, ms)) },
  ) {
    this.size = Math.min(start, max);
    this.peak = this.size;
  }

  /** Wait for a slot and for any pause to end; returns the epoch the call starts in. */
  async acquire(): Promise<number> {
    for (;;) {
      const pause = this.pausedUntil - this.clock.now();
      if (pause > 0) {
        await this.clock.sleep(pause);
        continue;
      }
      if (this.inFlight < this.size) {
        this.inFlight++;
        return this.epoch;
      }
      await new Promise<void>((r) => this.waiters.push(r));
    }
  }

  release(): void {
    this.inFlight = Math.max(0, this.inFlight - 1);
    this.waiters.shift()?.();
  }

  ok(latencyMs: number): void {
    this.clean.push(latencyMs);
    if (this.clean.length < this.size) return;
    const med = median(this.clean);
    this.baseline ??= med;
    if (med <= 2 * this.baseline && this.size < this.max) {
      const next = Math.min(this.max, Math.ceil(this.size * 1.5));
      this.log(`window ${this.size} -> ${next} (${this.clean.length} clean calls, median ${(med / 1000).toFixed(0)} s against ${(this.baseline / 1000).toFixed(0)} s at first)`);
      this.size = next;
      this.peak = Math.max(this.peak, next);
      for (const w of this.waiters.splice(0)) w();
    }
    this.clean = [];
  }

  /** A capacity error from a call that started in `epoch`. Returns whether it changed the window. */
  error(what: string, epoch = this.epoch, pauseMs = 0): boolean {
    if (epoch !== this.epoch) return false;
    this.epoch++;
    const next = Math.max(4, Math.floor(this.size / 2));
    this.log(`window ${this.size} -> ${next} after ${what}${pauseMs ? `; new calls pause ${(pauseMs / 1000).toFixed(0)} s` : ""} (${this.inFlight} in flight)`);
    this.size = next;
    this.clean = [];
    this.pausedUntil = Math.max(this.pausedUntil, this.clock.now() + pauseMs);
    return true;
  }
}

export function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? s[Math.floor(s.length / 2)]! : 0;
}

class Stop extends Error {}

export class FirstPassRunner {
  spendUsd = 0;
  byTier: Record<string, number> = {};
  calls = 0;
  retries = 0;
  stopping: StopReason | null = null;
  readonly window: Window;
  private lastFinish: number;
  private gapReported = false;

  constructor(
    private readonly deps: RunnerDeps,
    private readonly opts: RunnerOptions,
    private readonly state: PassState,
  ) {
    this.window = new Window(opts.window, opts.maxWindow, (l) => deps.log(l), { now: () => deps.now(), sleep: (ms) => deps.sleep(ms) });
    this.lastFinish = deps.now();
  }

  /** A tier or credit stop: calls in flight finish, but no further call is sent. */
  private halted(): boolean {
    return this.stopping === "tier" || this.stopping === "credit";
  }

  private stop(reason: StopReason, line: string): void {
    if (this.stopping) return;
    this.stopping = reason;
    this.deps.log(line);
  }

  /** The backend every unit uses: retries capacity errors, meters cost by served tier, guards the tier. */
  private metered(): Backend {
    const inner = this.deps.backend;
    return {
      name: inner.name,
      complete: async (turns: Turn[], o?: { maxTokens?: number; system?: string }): Promise<Completion> => {
        for (let attempt = 1; ; attempt++) {
          const epoch = await this.window.acquire();
          let released = false;
          if (this.halted()) {
            this.window.release();
            throw new Stop(`stopped (${this.stopping}) before the call`);
          }
          try {
            const c = await inner.complete(turns, o);
            this.calls++;
            this.spendUsd += c.cost_usd;
            const served = c.served_tier ?? "unreported";
            this.byTier[served] = (this.byTier[served] ?? 0) + c.cost_usd;
            if (served !== this.opts.tier) this.stop("tier", `ERROR tier: a call was served on "${served}", not "${this.opts.tier}" ($${c.cost_usd.toFixed(4)}); no new units start, and the run stops when the units in flight finish`);
            this.window.ok(c.latency_ms);
            return c;
          } catch (e) {
            if (isPaymentError(e)) {
              this.stop("credit", `ERROR credit: OpenRouter refused payment (${(e as Error).message.slice(0, 200)}); stopping`);
              throw e;
            }
            if (!isCapacityError(e) || attempt >= this.opts.attempts) throw e;
            const wait = Math.min(120_000, 5_000 * 2 ** (attempt - 1)) * (0.75 + Math.random() * 0.5);
            this.window.release();
            released = true;
            this.window.error(`a capacity error (${(e as Error).message.slice(0, 120)})`, epoch, wait);
            this.retries++;
            this.deps.log(`retry ${attempt} of ${this.opts.attempts - 1} in ${(wait / 1000).toFixed(0)} s: ${(e as Error).message.slice(0, 160)}`);
            await this.deps.sleep(wait);
            if (this.halted()) throw new Stop(`stopped (${this.stopping}) while retrying`);
          } finally {
            if (!released) this.window.release();
          }
        }
      },
    };
  }

  async run(jobs: PassJob[]): Promise<RunSummary> {
    const started = this.deps.now();
    const backend = this.metered();
    const queue = [...jobs];
    const running = new Set<Promise<void>>();
    const pendingFiles: string[] = [];
    const pendingUnits: string[] = [];
    const commits: string[] = [];
    let done = 0;
    let failed = 0;
    let finished = 0;
    let estimateDone = 0;
    let failStreak = 0;
    let chain: Promise<void> = Promise.resolve();
    const serial = (f: () => Promise<void>) => (chain = chain.then(f, f));
    const flush = () =>
      serial(async () => {
        if (!pendingUnits.length) return;
        const files = pendingFiles.splice(0);
        const units = pendingUnits.splice(0);
        try {
          const sha = await this.deps.commit(files, units);
          if (sha) {
            commits.push(sha);
            this.deps.log(`wordbase commit ${sha.slice(0, 7)}: ${files.length} entries from ${units.length} units`);
          }
        } catch (e) {
          this.deps.log(`ERROR wordbase commit: ${(e as Error).message}`);
        }
      });
    const save = () => serial(() => this.deps.saveState(this.state));

    const gapTimer = setInterval(() => {
      const idle = this.deps.now() - this.lastFinish;
      if (idle > this.opts.gapMs && !this.gapReported) {
        this.gapReported = true;
        this.deps.log(`GAP no unit finished for ${(idle / 1000).toFixed(0)} s (${running.size} in flight, window ${this.window.size})`);
      }
    }, Math.min(30_000, this.opts.gapMs));
    gapTimer.unref?.();

    const runOne = async (job: PassJob) => {
      const t0 = this.deps.now();
      const spent0 = this.spendUsd;
      try {
        const ctx = await this.deps.build(job);
        const r = await this.deps.describe(backend, ctx);
        const w = await this.deps.write(job, r);
        done++;
        failStreak = 0;
        estimateDone += job.estimateUsd;
        this.state.units[job.label] = { status: "done", at: new Date(this.deps.now()).toISOString(), cost_usd: r.cost_usd, files: w.files.length, ...(r.problems?.length ? { problems: r.problems } : {}) };
        pendingFiles.push(...w.files);
        pendingUnits.push(job.label);
        const calls = r.completions.map((c) => `${(c.latency_ms / 1000).toFixed(0)} s ${c.served_tier ?? "unreported"}`).join(", ");
        this.deps.log(
          `unit ${job.label} · ${ctx.stats.tokens} tokens · $${r.cost_usd.toFixed(4)} · ${((this.deps.now() - t0) / 1000).toFixed(0)} s (calls: ${calls}) · ${r.rewritten ? "rewritten · " : ""}lint ${[...r.lint.values()].reduce((a, h) => a + h.length, 0)} in ${w.linted} entries · ${w.files.length - w.tests} files + ${w.tests} tests written${r.problems?.length ? ` · ${r.problems.length} validation problems kept: ${r.problems.slice(0, 2).join("; ")}` : ""} · window ${this.window.size}, ${running.size} in flight · spend $${this.spendUsd.toFixed(2)}`,
        );
      } catch (e) {
        failed++;
        failStreak++;
        const msg = (e as Error).message;
        this.state.units[job.label] = { status: "failed", at: new Date(this.deps.now()).toISOString(), cost_usd: this.spendUsd - spent0, files: 0, error: msg.slice(0, 400) };
        this.deps.log(`ERROR unit ${job.label}: ${msg.slice(0, 300)}`);
        if (failStreak >= this.opts.maxConsecutiveFailures) this.stop("failures", `ERROR ${failStreak} units failed in a row with none finishing in between; stopping`);
      } finally {
        finished++;
        this.lastFinish = this.deps.now();
        this.gapReported = false;
        await save();
        if (pendingUnits.length >= this.opts.commitEvery) await flush();
        if (finished % 10 === 0)
          this.deps.log(
            `progress ${finished} of ${jobs.length} units (${done} done, ${failed} failed) · spend $${this.spendUsd.toFixed(2)} against $${estimateDone.toFixed(2)} estimated for the units done · pass estimate $${this.opts.estimateUsd.toFixed(2)}, cap $${this.opts.capUsd.toFixed(2)} · window ${this.window.size}, ${this.window.inFlight} calls in flight, ${this.retries} retries · by tier ${Object.entries(this.byTier).map(([t, c]) => `${t} $${c.toFixed(2)}`).join(", ") || "none"}`,
          );
      }
    };

    try {
      while (queue.length || running.size) {
        while (!this.stopping && queue.length && running.size < this.window.size) {
          if (this.spendUsd >= this.opts.capUsd) {
            this.stop("cap", `ERROR spend cap: $${this.spendUsd.toFixed(2)} reported reaches the $${this.opts.capUsd.toFixed(2)} cap; no new units start`);
            break;
          }
          const job = queue.shift()!;
          const p: Promise<void> = runOne(job).finally(() => running.delete(p));
          running.add(p);
        }
        if (!running.size) break;
        await Promise.race(running);
      }
    } finally {
      clearInterval(gapTimer);
    }
    await flush();
    await save();
    await chain;
    return {
      status: this.stopping ?? "complete",
      spendUsd: this.spendUsd,
      byTier: this.byTier,
      calls: this.calls,
      retries: this.retries,
      done,
      failed,
      notStarted: queue.length,
      peakWindow: this.window.peak,
      finalWindow: this.window.size,
      commits,
      wallMs: this.deps.now() - started,
    };
  }
}

/** Whether an entry's `by:` names a model run. Anything else, a hand-written fixture included, is protected. */
export function isGenerated(by: unknown): boolean {
  return typeof by === "string" && /^(claude-[\w.-]+|glm-[\w.-]+|[\w.-]+\/[\w.:-]+) (poll|prep|first-pass|compare|system-pages)\b/.test(by);
}

/**
 * Which planned jobs are already done, checked against the run's state file. A unit the state
 * records as done that does not read as done means the check or the tree is wrong: fail closed.
 */
export async function resumeCheck(jobs: PassJob[], state: PassState | null, isDone: (job: PassJob) => Promise<boolean>): Promise<{ done: Set<string>; verified: string | null }> {
  if (!jobs.length) throw new Error("the plan holds no units; refusing to treat an empty listing as nothing to do");
  const done = new Set<string>();
  for (const j of jobs) if (await isDone(j)) done.add(j.label);
  const recorded = Object.entries(state?.units ?? {}).filter(([, u]) => u.status === "done").map(([l]) => l);
  const lost = recorded.filter((l) => jobs.some((j) => j.label === l) && !done.has(l));
  if (lost.length) throw new Error(`${lost.length} units the state file records as done do not read as done (${lost.slice(0, 3).join(", ")}); the resume check or the wordbase is wrong`);
  const verified = recorded.find((l) => done.has(l) && (jobs.find((j) => j.label === l)?.owned.length ?? 0) > 0) ?? null;
  return { done, verified };
}
