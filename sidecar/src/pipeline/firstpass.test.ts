import { describe, expect, it } from "vitest";
import type { Backend, Completion } from "./backends.js";
import type { UnitResult } from "./describe.js";
import { FIRST_PASS_DEFAULTS, FirstPassRunner, isCapacityError, isGenerated, resumeCheck, Window, type PassJob, type PassState, type RunnerDeps } from "./firstpass.js";
import { OpenRouterError } from "./openrouter.js";
import type { UnitContext } from "./units.js";

const job = (i: number): PassJob => ({ label: `lib/p/src/p${i}`, unit: { dir: `lib/p/src/p${i}`, package: "p", commit: "c", files: [`lib/p/src/p${i}/a.py`], targets: [`lib/p/src/p${i}/a.py`] }, siblings: [], owned: [`lib/p/src/p${i}/a.py`], estimateUsd: 0.1 });

interface Fake {
  deps: RunnerDeps;
  lines: string[];
  started: string[];
  commits: string[][];
  calls: number;
}

/** A runner world: each call costs `cost`, is served on `tierOf(call)`, and may throw `failOf(call)`. */
function world(opts: { cost?: number; tierOf?: (n: number) => string; failOf?: (n: number) => Error | null; latency?: number } = {}): Fake {
  const f: Fake = { lines: [], started: [], commits: [], calls: 0, deps: null as unknown as RunnerDeps };
  let clock = 0;
  const backend: Backend = {
    name: "fake",
    async complete(): Promise<Completion> {
      const n = ++f.calls;
      await new Promise((r) => setTimeout(r, 1));
      const err = opts.failOf?.(n);
      if (err) throw err;
      return { text: "{}", model: "fake", input_tokens: 10, output_tokens: 5, cache_read_tokens: 0, cost_usd: opts.cost ?? 1, latency_ms: opts.latency ?? 1000, served_tier: opts.tierOf?.(n) ?? "flex", cost_source: "usage.cost" };
    },
  };
  f.deps = {
    backend,
    build: async (j) => {
      f.started.push(j.label);
      return { unit: j.unit, inputs: "", existing: new Map(), stats: { tokens: 100, budget: 256_000, chars: 0, sourceTokens: 0, tests: [], testsDropped: [], neighbours: [], neighboursDropped: [], outsideLib: [], overBudget: false } } satisfies UnitContext;
    },
    describe: async (b, ctx) => {
      const c = await b.complete([{ role: "user", content: ctx.unit.dir }]);
      return { output: {}, tests: {}, lint: new Map(), completions: [c], rewritten: false, rewriteReason: [], cost_usd: c.cost_usd, latency_ms: c.latency_ms } satisfies UnitResult;
    },
    write: async (j) => ({ files: j.owned, tests: 0, linted: 0 }),
    commit: async (files) => {
      f.commits.push(files);
      return `sha${f.commits.length}`;
    },
    saveState: async () => {},
    log: (l) => f.lines.push(l),
    now: () => (clock += 10),
    sleep: async (ms) => {
      clock += ms;
    },
  };
  return f;
}

const state = (): PassState => ({ commit: "c", started: "t", units: {} });
const opts = { ...FIRST_PASS_DEFAULTS, window: 2, maxWindow: 2, commitEvery: 3 };

describe("first pass runner", () => {
  it("runs every unit within the window and commits the wordbase in batches", async () => {
    const f = world();
    const s = await new FirstPassRunner(f.deps, opts, state()).run([1, 2, 3, 4, 5, 6, 7].map(job));
    expect(s.status).toBe("complete");
    expect(s.done).toBe(7);
    expect(s.spendUsd).toBe(7);
    expect(s.byTier).toEqual({ flex: 7 });
    expect(f.commits.map((c) => c.length)).toEqual([3, 3, 1]);
    expect(s.commits).toEqual(["sha1", "sha2", "sha3"]);
    expect(f.lines.some((l) => l.startsWith("progress ") === false && l.startsWith("unit lib/p/src/p1 ·"))).toBe(true);
  });

  it("stops starting units when a call is served on another tier, and lets the units in flight finish", async () => {
    const f = world({ tierOf: (n) => (n === 3 ? "default" : "flex") });
    const s = await new FirstPassRunner(f.deps, opts, state()).run([1, 2, 3, 4, 5, 6].map(job));
    expect(s.status).toBe("tier");
    expect(f.lines.filter((l) => l.startsWith('ERROR tier: a call was served on "default"'))).toHaveLength(1);
    // Units 1-3 started before the third call came back; unit 4 was already in flight beside it.
    expect(f.started.length).toBeLessThanOrEqual(4);
    expect(s.notStarted).toBe(6 - f.started.length);
    expect(s.byTier.default).toBe(1);
  });

  it("starts no unit once reported spend reaches the cap", async () => {
    const f = world({ cost: 10 });
    const s = await new FirstPassRunner(f.deps, { ...opts, capUsd: 35 }, state()).run([1, 2, 3, 4, 5, 6, 7, 8].map(job));
    expect(s.status).toBe("cap");
    // With two in flight, the check before each start sees at most 30 spent: four or five units run.
    expect(s.done).toBeGreaterThanOrEqual(4);
    expect(s.done).toBeLessThanOrEqual(5);
    expect(s.spendUsd).toBeGreaterThanOrEqual(35);
    expect(s.notStarted).toBe(8 - s.done);
    expect(f.lines.some((l) => l.startsWith("ERROR spend cap: $"))).toBe(true);
  });

  it("retries capacity errors with backoff, halves the window, and fails other errors without retry", async () => {
    const f = world({ failOf: (n) => (n === 1 ? new OpenRouterError("OpenRouter answered 503: flex capacity", 503) : n === 3 ? new OpenRouterError("OpenRouter answered 400: bad request", 400) : null) });
    const r = new FirstPassRunner(f.deps, { ...opts, window: 8, maxWindow: 8 }, state());
    const s = await r.run([1, 2, 3].map(job));
    expect(s.done).toBe(2);
    expect(s.failed).toBe(1);
    expect(f.lines.some((l) => l.startsWith("retry 1 of 7 in "))).toBe(true);
    expect(f.lines.some((l) => l.startsWith("window 8 -> 4 after a capacity error (OpenRouter answered 503: flex capacity); new calls pause "))).toBe(true);
    expect(f.lines.some((l) => l.startsWith("ERROR unit ") && l.includes("400"))).toBe(true);
    expect(isCapacityError(new OpenRouterError("x", 429))).toBe(true);
    expect(isCapacityError(new Error("fetch failed"))).toBe(true);
    expect(isCapacityError(new OpenRouterError("x", 400))).toBe(false);
  });

  it("counts a burst of capacity errors once and holds retries to the halved window", async () => {
    let live = 0;
    let maxAfter = 0;
    let failedOnce = false;
    const f = world({ failOf: (n) => (n <= 16 ? new OpenRouterError("OpenRouter answered 502: Flex processing is temporarily unavailable", 502) : null) });
    const inner = f.deps.backend;
    f.deps.backend = {
      name: inner.name,
      async complete(turns, o) {
        live++;
        if (failedOnce) maxAfter = Math.max(maxAfter, live);
        try {
          return await inner.complete(turns, o);
        } catch (e) {
          failedOnce = true;
          throw e;
        } finally {
          live--;
        }
      },
    };
    const s = await new FirstPassRunner(f.deps, { ...opts, window: 16, maxWindow: 16 }, state()).run([...Array(16).keys()].map(job));
    expect(s.done).toBe(16);
    expect(s.retries).toBe(16);
    expect(f.lines.filter((l) => l.startsWith("window ") && l.includes("after a capacity error"))).toHaveLength(1);
    expect(f.lines.some((l) => l.startsWith("window 16 -> 8 after"))).toBe(true);
    expect(maxAfter).toBeLessThanOrEqual(8);
  });

  it("stops at once when OpenRouter refuses payment", async () => {
    const f = world({ failOf: () => new OpenRouterError("OpenRouter answered 402: insufficient credits", 402) });
    const s = await new FirstPassRunner(f.deps, opts, state()).run([1, 2, 3, 4].map(job));
    expect(s.status).toBe("credit");
    expect(s.notStarted).toBeGreaterThanOrEqual(2);
  });

  it("grows the window after a full window of clean calls", () => {
    const lines: string[] = [];
    const w = new Window(4, 10, (l) => lines.push(l));
    for (let i = 0; i < 4; i++) w.ok(1000);
    expect(w.size).toBe(6);
    for (let i = 0; i < 6; i++) w.ok(5000); // more than twice the first round's median: hold
    expect(w.size).toBe(6);
    w.error("x");
    expect(w.size).toBe(4);
    expect(w.peak).toBe(6);
  });
});

describe("resumption", () => {
  const jobs = [1, 2, 3].map(job);

  it("skips units whose files all have entries at the pass's commit", async () => {
    const r = await resumeCheck(jobs, { commit: "c", started: "t", units: { [jobs[0]!.label]: { status: "done", at: "t", cost_usd: 1, files: 1 } } }, async (j) => j.label === jobs[0]!.label);
    expect([...r.done]).toEqual([jobs[0]!.label]);
    expect(r.verified).toBe(jobs[0]!.label);
  });

  it("fails closed when a unit the state records as done does not read as done", async () => {
    const st: PassState = { commit: "c", started: "t", units: { [jobs[1]!.label]: { status: "done", at: "t", cost_usd: 1, files: 1 } } };
    await expect(resumeCheck(jobs, st, async () => false)).rejects.toThrow(/records as done do not read as done/);
  });

  it("treats an empty plan as an error, not as nothing to do", async () => {
    await expect(resumeCheck([], null, async () => true)).rejects.toThrow(/empty listing/);
  });

  it("protects entries that no model wrote", () => {
    expect(isGenerated("openai/gpt-6.1-terra first-pass 1d274b5")).toBe(true);
    expect(isGenerated("claude-sonnet-5-5 poll 41a4198")).toBe(true);
    expect(isGenerated("hand-written demo fixture")).toBe(false);
    expect(isGenerated(undefined)).toBe(false);
  });
});
