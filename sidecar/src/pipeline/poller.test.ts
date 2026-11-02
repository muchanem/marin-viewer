import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Config } from "../config.js";
import { fileEntryPath, readEntry } from "../wordbase.js";
import type { Backend, Completion, Turn } from "./backends.js";
import { Gh } from "./exec.js";
import { firstPassLock, gapLine, pool, Poller, summaryLine, DEFAULTS, type TickSummary } from "./poller.js";

const PROMPTS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "prompts");

describe("tick output", () => {
  it("prints a GAP line only when the last tick is more than twice the interval ago", () => {
    const now = new Date("2026-11-01T12:00:00Z");
    expect(gapLine(undefined, now, 300)).toBeNull();
    expect(gapLine("2026-11-01T11:51:00Z", now, 300)).toBeNull();
    expect(gapLine("2026-11-01T11:49:00Z", now, 300)).toBe("GAP 660 s since the last tick at 2026-11-01T11:49:00Z (interval 300 s)");
  });

  it("summarises a tick on one line", () => {
    const s = { started: "2026-11-01T12:00:00Z", main: "1d274b52c6", newCommits: 2, describedCommits: 3, files: 5, units: 2, kept: 1, deleted: 0, renamed: 0, queued: 0, systems: 1, prsListed: 4, prsPrepared: 1, prsFailed: 0, prsWaiting: 2, costUsd: 0.4321, monthUsd: 3.2, paceUsd: 6.5, ghCalls: 4, errors: 0, seconds: 61, gap: null, initialised: false } satisfies TickSummary;
    expect(summaryLine(s, { monthlyBudgetUsd: 200 })).toBe(
      "tick 2026-11-01T12:00:00Z · main 1d274b5 (+2 fetched) · described 3 commits: 5 files in 2 units (1 kept) · systems 1 · PRs 1 prepared, 0 failed, 2 waiting of 4 listed · cost $0.43 · month $3.20 of $200 (pace $6.50) · gh 4 calls · 0 errors · 61 s",
    );
  });

  it("sees a live first pass's lock, ignores a dead one, and fails closed on an unreadable one", () => {
    const dir = mkdtempSync(path.join(tmpdir(), "lock-"));
    const file = path.join(dir, "first-pass.lock");
    expect(firstPassLock(dir)).toBeNull();
    writeFileSync(file, JSON.stringify({ pid: process.pid, commit: "abc1234", started: "t" }));
    expect(firstPassLock(dir)?.pid).toBe(process.pid);
    writeFileSync(file, JSON.stringify({ pid: 2 ** 22 + 12345, commit: "abc1234", started: "t" }));
    expect(firstPassLock(dir)).toBeNull();
    writeFileSync(file, "{not json");
    expect(firstPassLock(dir)?.commit).toBe("unreadable");
    // The subsystem-page run's lock reads the same way under its own name.
    expect(firstPassLock(dir, "system-pages.lock")).toBeNull();
    writeFileSync(path.join(dir, "system-pages.lock"), JSON.stringify({ pid: process.pid, commit: "abc1234", started: "t" }));
    expect(firstPassLock(dir, "system-pages.lock")?.pid).toBe(process.pid);
    rmSync(dir, { recursive: true, force: true });
  });

  it("runs at most n tasks at once", async () => {
    let running = 0;
    let peak = 0;
    const out = await pool([1, 2, 3, 4, 5], 2, async (x) => {
      running++;
      peak = Math.max(peak, running);
      await new Promise((r) => setTimeout(r, 5));
      running--;
      return x * 2;
    });
    expect(out).toEqual([2, 4, 6, 8, 10]);
    expect(peak).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// End to end over temporary repositories: upstream -> clone (the "Marin clone") -> poller.

const git = (cwd: string, ...args: string[]) => execFileSync("git", ["-C", cwd, ...args], { encoding: "utf8" }).trim();

class FakeBackend implements Backend {
  readonly name = "fake-model";
  prompts: string[] = [];
  async complete(turns: Turn[]): Promise<Completion> {
    const p = turns[0]!.content;
    this.prompts.push(p);
    let text: string;
    if (p.startsWith("# Cold reader")) text = '{"gaps": []}';
    else if (p.startsWith("# Describe a subsystem")) text = JSON.stringify({ l1: "Frames bytes for pipes." });
    else {
      const list = (name: string) => /=== BEGIN (.+?) ===\n([\s\S]*?)\n=== END \1 ===/g;
      const block = (name: string) => [...p.matchAll(list(name))].find((m) => m[1] === name)?.[2] ?? "none";
      const targets = block("TARGETS") === "none" ? [] : block("TARGETS").split("\n");
      const tests = block("TEST TARGETS") === "none" ? [] : block("TEST TARGETS").split("\n");
      const out: Record<string, unknown> = Object.fromEntries(targets.map((t) => [t, { l1: `Handles ${path.basename(t)} at this commit.`, system: "pkg" }]));
      if (tests.length) out.tests = Object.fromEntries(tests.map((t) => [t, { l1: `Checks ${path.basename(t)}.` }]));
      text = JSON.stringify(out);
    }
    return { text, model: this.name, input_tokens: 100, output_tokens: 10, cache_read_tokens: 0, cost_usd: 0.01, latency_ms: 1 };
  }
}

describe("Poller.tick", () => {
  let root: string;
  let upstream: string;
  let config: Config;
  const lines: string[] = [];
  const env = { ...process.env };

  beforeAll(() => {
    Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@e", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@e" });
    root = mkdtempSync(path.join(tmpdir(), "poller-"));
    upstream = path.join(root, "upstream");
    mkdirSync(path.join(upstream, "lib/pkg/src/pkg"), { recursive: true });
    git(root, "init", "-q", "-b", "main", upstream);
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/a.py"), "def a():\n    return 1\n");
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/b.py"), "from pkg.a import a\n\ndef b():\n    return a()\n");
    writeFileSync(path.join(upstream, "lib/pkg/README.md"), "# pkg\n");
    mkdirSync(path.join(upstream, "lib/pkg/src/pkg/sub"));
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/sub/d.py"), "from pkg.a import a\n\nclass D:\n    def run(self):\n        return a()\n");
    git(upstream, "add", ".");
    git(upstream, "commit", "-q", "-m", "first");
    git(root, "clone", "-q", upstream, path.join(root, "marin"));
    mkdirSync(path.join(root, "wordbase"));
    git(path.join(root, "wordbase"), "init", "-q");
    config = { root, marin: path.join(root, "marin"), wordbase: path.join(root, "wordbase"), state: path.join(root, "state"), prompts: PROMPTS, envFile: path.join(root, ".env") };
  });
  afterAll(() => {
    process.env = env;
    rmSync(root, { recursive: true, force: true });
  });

  const make = (gh: Gh, backend: Backend) =>
    new Poller(config, { ...DEFAULTS, intervalSec: 300 }, { gh, backend, out: (l) => lines.push(l), checker: async () => ({ ok: true, failures: [], output: "OK" }) });
  const emptyGh = () => new Gh(async () => ({ code: 0, stdout: "[]", stderr: "" }));

  it("initialises on the first tick, then a quiet tick describes nothing", async () => {
    const backend = new FakeBackend();
    const s1 = await make(emptyGh(), backend).tick();
    expect(s1.initialised).toBe(true);
    expect(s1.ghCalls).toBe(2);
    const s2 = await make(emptyGh(), backend).tick();
    expect(s2.initialised).toBe(false);
    expect(s2.describedCommits).toBe(0);
    expect(s2.files).toBe(0);
    expect(backend.prompts).toHaveLength(0);
    expect(lines.at(-1)).toMatch(/described 0 commits: 0 files in 0 units · systems 0 · PRs 0 prepared, 0 failed, 0 waiting of 0 listed · cost \$0.00 .* gh 2 calls · 0 errors/);
  });

  it("fetches a new commit, describes the changed file with its directory, creates the subsystem page and commits the wordbase", async () => {
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/a.py"), "def a():\n    return 2\n");
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/c.py"), "");
    git(upstream, "commit", "-q", "-am", "second");
    const backend = new FakeBackend();
    const s = await make(emptyGh(), backend).tick();
    expect(s.newCommits).toBe(1);
    expect(s.describedCommits).toBe(1);
    expect(s.files).toBe(1);
    expect(s.units).toBe(1);
    expect(s.systems).toBe(1);
    const unitPrompt = backend.prompts.find((p) => p.startsWith("# Describe a unit"))!;
    expect(unitPrompt).toMatch(/=== BEGIN SOURCE lib\/pkg\/src\/pkg\/b.py ===/); // the sibling is context
    expect(unitPrompt).toMatch(/=== BEGIN TARGETS ===\nlib\/pkg\/src\/pkg\/a.py\n=== END TARGETS ===/);
    expect(unitPrompt).toMatch(/=== BEGIN NEIGHBOUR lib\/pkg\/src\/pkg\/sub\/d.py \(imports the unit\) ===\nfrom pkg.a import a\n\nclass D:\n    def run\(self\):/); // d imports a from another directory, in full
    expect(unitPrompt).toMatch(/return 2/);
    const e = (await readEntry(fileEntryPath(config.wordbase, "lib/pkg/src/pkg/a.py")))!;
    expect(e.front.commit).toBe(git(config.marin, "rev-parse", "HEAD"));
    expect(e.front.by).toMatch(/^fake-model poll [0-9a-f]{7}$/);
    expect((await readEntry(path.join(config.wordbase, "systems/pkg.md")))!.front.l1).toBe("Frames bytes for pipes.");
    expect(git(config.wordbase, "log", "-1", "--format=%s")).toMatch(/^Describe 1 files changed on main through [0-9a-f]{7}$/);
    expect(git(config.wordbase, "log", "-1", "--format=%b")).not.toMatch(/Co-Authored-By/i);
    const main = JSON.parse(readFileSync(path.join(config.state, "main.json"), "utf8"));
    expect(main.described).toBe(git(config.marin, "rev-parse", "HEAD"));
    expect(main.in_progress).toBeUndefined();
  });

  it("marks deleted files and moves renamed entries", async () => {
    git(upstream, "mv", "lib/pkg/src/pkg/a.py", "lib/pkg/src/pkg/a2.py");
    git(upstream, "commit", "-q", "-m", "rename");
    const s = await make(emptyGh(), new FakeBackend()).tick();
    expect(s.renamed).toBe(1);
    expect((await readEntry(fileEntryPath(config.wordbase, "lib/pkg/src/pkg/a2.py")))!.front.path).toBe("lib/pkg/src/pkg/a2.py");
    expect(await readEntry(fileEntryPath(config.wordbase, "lib/pkg/src/pkg/a.py"))).toBeNull();
    git(upstream, "rm", "-q", "lib/pkg/src/pkg/a2.py");
    git(upstream, "commit", "-q", "-m", "delete");
    const s2 = await make(emptyGh(), new FakeBackend()).tick();
    expect(s2.deleted).toBe(1);
    expect((await readEntry(fileEntryPath(config.wordbase, "lib/pkg/src/pkg/a2.py")))!.front.deleted).toBe(git(config.marin, "rev-parse", "HEAD"));
  });

  it("plans without calling a model or changing state on --dry-run, and stops at --describe-to", async () => {
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/b.py"), "def b():\n    return 3\n");
    git(upstream, "commit", "-q", "-am", "third");
    const third = git(upstream, "rev-parse", "HEAD");
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/sub/d.py"), "class D:\n    pass\n");
    git(upstream, "commit", "-q", "-am", "fourth");
    const mainFile = path.join(config.state, "main.json");
    const before = readFileSync(mainFile, "utf8");
    const dry = new FakeBackend();
    const poller = (opts: object, backend: Backend) =>
      new Poller(config, { ...DEFAULTS, ...opts }, { gh: emptyGh(), backend, out: (l) => lines.push(l), checker: async () => ({ ok: true, failures: [], output: "OK" }) });
    const s = await poller({ dryRun: true }, dry).tick();
    expect(dry.prompts).toHaveLength(0);
    expect(s.describedCommits).toBe(2);
    expect(lines.some((l) => l.startsWith("  would describe lib/pkg/src/pkg: 1 targets, 0 test targets; "))).toBe(true);
    expect(lines.some((l) => l.startsWith("  would describe lib/pkg/src/pkg/sub: 1 targets, 0 test targets; "))).toBe(true);
    expect(JSON.parse(readFileSync(mainFile, "utf8")).described).toBe(JSON.parse(before).described);
    const real = new FakeBackend();
    const s2 = await poller({ describeTo: third }, real).tick();
    expect(s2.describedCommits).toBe(1);
    expect(s2.files).toBe(1);
    expect(JSON.parse(readFileSync(mainFile, "utf8")).described).toBe(third);
    await expect(poller({ describeTo: "no-such-rev" }, real).tick().then((x) => x.errors)).resolves.toBe(1);
  });

  it("stops model work for the tick when the API is out of credit, and queues the files", async () => {
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/b.py"), "def b():\n    return 4\n");
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/sub/d.py"), "class D:\n    x = 1\n");
    git(upstream, "commit", "-q", "-am", "fifth");
    let calls = 0;
    const broke: Backend = {
      name: "broke",
      async complete() {
        calls++;
        throw new Error('400 {"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}');
      },
    };
    const before = lines.length;
    const s = await new Poller(config, { ...DEFAULTS, unitConcurrency: 1 }, { gh: emptyGh(), backend: broke, out: (l) => lines.push(l), checker: async () => ({ ok: true, failures: [], output: "OK" }) }).tick();
    expect(calls).toBe(1);
    expect(s.files).toBe(0);
    expect(lines.slice(before).filter((l) => l.includes("out of credit"))).toHaveLength(1);
    const queue = JSON.parse(readFileSync(path.join(config.state, "queue.json"), "utf8"));
    expect(queue.files.map((f: { path: string }) => f.path).sort()).toEqual(["lib/pkg/src/pkg/b.py", "lib/pkg/src/pkg/sub/d.py"]);
  });

  it("reports a gh failure as an error, never as an empty PR list", async () => {
    const gh = new Gh(async () => ({ code: 1, stdout: "", stderr: "HTTP 401: Bad credentials" }));
    const s = await make(gh, new FakeBackend()).tick();
    expect(s.errors).toBe(1);
    expect(s.prsListed).toBe(0);
    expect(lines.some((l) => /^ERROR preparing PRs: gh search prs failed.*Bad credentials/.test(l))).toBe(true);
  });

  it("writes a changed test's l1 with its owner unit, and sends the rest to an orphan batch", async () => {
    mkdirSync(path.join(upstream, "lib/pkg/tests"), { recursive: true });
    writeFileSync(path.join(upstream, "lib/pkg/src/pkg/e.py"), "def e():\n    return 5\n");
    writeFileSync(path.join(upstream, "lib/pkg/tests/test_e.py"), "from pkg.e import e\n\ndef test_e():\n    assert e() == 5\n");
    writeFileSync(path.join(upstream, "lib/pkg/tests/conftest.py"), "import pytest\n");
    git(upstream, "add", ".");
    git(upstream, "commit", "-q", "-m", "tests");
    const backend = new FakeBackend();
    await make(emptyGh(), backend).tick();
    const unit = backend.prompts.find((p) => p.startsWith("# Describe a unit") && p.includes("=== BEGIN TARGETS ===\nlib/pkg/src/pkg/e.py"))!;
    expect(unit).toMatch(/=== BEGIN TEST lib\/pkg\/tests\/test_e.py \(one of the unit's own tests\) ===/);
    expect(unit).toMatch(/=== BEGIN TEST TARGETS ===\nlib\/pkg\/tests\/test_e.py\n=== END TEST TARGETS ===/);
    const orphans = backend.prompts.filter((p) => p.includes("a batch of test files that import none of the described code"));
    expect(orphans).toHaveLength(1);
    expect(orphans[0]).toMatch(/=== BEGIN TEST TARGETS ===\nlib\/pkg\/tests\/conftest.py\n=== END TEST TARGETS ===/);
    expect(orphans[0]).not.toMatch(/BEGIN NEIGHBOUR/);
    const t = (await readEntry(fileEntryPath(config.wordbase, "lib/pkg/tests/test_e.py")))!;
    expect(t.front.l1).toBe("Checks test_e.py.");
    expect(t.front.l2).toBeUndefined();
    expect(t.symbols).toEqual([]);

    // A test that changes while its owner does not goes to the orphan batch.
    writeFileSync(path.join(upstream, "lib/pkg/tests/test_e.py"), "from pkg.e import e\n\ndef test_e():\n    assert e() > 4\n");
    git(upstream, "commit", "-q", "-am", "test only");
    const again = new FakeBackend();
    await make(emptyGh(), again).tick();
    const units = again.prompts.filter((p) => p.startsWith("# Describe a unit"));
    expect(units).toHaveLength(1);
    expect(units[0]).toMatch(/a batch of test files/);
    expect(units[0]).toMatch(/=== BEGIN TEST TARGETS ===\nlib\/pkg\/tests\/test_e.py\n=== END TEST TARGETS ===/);
  });

  it("goes on with the old main when the fetch fails", async () => {
    git(config.marin, "remote", "set-url", "origin", path.join(root, "missing"));
    const s = await make(emptyGh(), new FakeBackend()).tick();
    expect(s.errors).toBe(1);
    expect(lines.some((l) => l.startsWith("ERROR updating main (going on with the old main)"))).toBe(true);
    expect(s.main).toBe(git(config.marin, "rev-parse", "HEAD"));
    git(config.marin, "remote", "set-url", "origin", upstream);
  });
});
