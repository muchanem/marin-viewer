import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { pricePass } from "./pass.js";
import { excludedPath, type MarinRepo } from "./repo.js";
import { assignOwners, ContextBuilder, diversityOrder, fillBudget, packOrphans, planSlices, type Candidate } from "./units.js";

const cand = (p: string, pkg: string, score: number, test = false, tokens = 10): Candidate => ({ path: p, tokens, package: pkg, test, score, relation: "imports the unit" });

describe("choosing neighbours", () => {
  it("puts non-test code first and goes round-robin over packages, the unit's own package first", () => {
    const order = diversityOrder(
      [
        cand("lib/a/x.py", "a", 1),
        cand("lib/a/y.py", "a", 5),
        cand("lib/a/z.py", "a", 3),
        cand("lib/b/u.py", "b", 2),
        cand("experiments/e1.py", "experiments", 9),
        cand("experiments/e2.py", "experiments", 1),
        cand("lib/a/tests/test_t.py", "a", 50, true),
        cand("scripts/s.py", "scripts", 1),
      ],
      "a",
    ).map((c) => c.path);
    expect(order).toEqual([
      // round 1: home package, then the others by their best score
      "lib/a/y.py",
      "experiments/e1.py",
      "lib/b/u.py",
      "scripts/s.py",
      // round 2
      "lib/a/z.py",
      "experiments/e2.py",
      // round 3
      "lib/a/x.py",
      // test code last, however high its score
      "lib/a/tests/test_t.py",
    ]);
  });

  it("fills the budget in order and skips what does not fit, so a later small module can still go in", () => {
    const r = fillBudget(100, [{ tokens: 60, id: 1 }, { tokens: 50, id: 2 }, { tokens: 30, id: 3 }, { tokens: 20, id: 4 }]);
    expect(r.included.map((c) => c.id)).toEqual([1, 3]);
    expect(r.dropped.map((c) => c.id)).toEqual([2, 4]);
    expect(r.used).toBe(90);
  });
});

describe("splitting and owners", () => {
  it("cuts an oversized directory into balanced slices under the capacity", () => {
    const items = Array.from({ length: 10 }, (_, i) => ({ path: `d/f${i}.py`, tokens: 100 }));
    expect(planSlices(items, 2000)).toEqual([items.map((i) => i.path)]);
    const s = planSlices(items, 400);
    expect(s).toHaveLength(3);
    for (const slice of s) expect(slice.length * 100).toBeLessThanOrEqual(400);
    expect(s.flat()).toEqual(items.map((i) => i.path));
    // A file over the capacity gets a slice of its own, and the small files on either side share one.
    const big = planSlices([{ path: "d/a.py", tokens: 50 }, { path: "d/b.py", tokens: 900 }, { path: "d/c.py", tokens: 50 }], 400);
    expect(big).toEqual([["d/a.py", "d/c.py"], ["d/b.py"]]);
  });

  it("gives each test to the directory it imports the most names from, and marks orphans", () => {
    const names = new Map([
      ["lib/p/tests/test_a.py", new Map([["lib/p/src/p/a.py", 1], ["lib/q/src/q/b.py", 3]])],
      ["lib/p/tests/test_tie.py", new Map([["lib/p/src/p/a.py", 2], ["lib/q/src/q/b.py", 2]])],
      ["lib/p/tests/conftest.py", new Map([["lib/p/tests/helpers.py", 1]])],
    ]);
    const dirOf = new Map([["lib/p/src/p/a.py", "lib/p/src/p"], ["lib/q/src/q/b.py", "lib/q/src/q"]]);
    const owners = assignOwners(["lib/p/tests/test_a.py", "lib/p/tests/test_tie.py", "lib/p/tests/conftest.py"], names, dirOf);
    expect(owners.get("lib/p/tests/test_a.py")).toBe("lib/q/src/q");
    expect(owners.get("lib/p/tests/test_tie.py")).toBe("lib/p/src/p"); // a tie goes to the test's own package
    expect(owners.get("lib/p/tests/conftest.py")).toBeNull();
  });

  it("packs orphan tests by directory within the room", () => {
    const b = packOrphans([{ path: "lib/b/tests/x.py", tokens: 40 }, { path: "lib/a/tests/y.py", tokens: 40 }, { path: "lib/a/tests/x.py", tokens: 40 }], 100);
    expect(b).toEqual([["lib/a/tests/x.py", "lib/a/tests/y.py"], ["lib/b/tests/x.py"]]);
  });

  it("prices a planned pass from its prompt tokens and flags prompts past 272K", () => {
    const base = { kind: "source" as const, neighbours: 0, neighboursDropped: 0, testsInPrompt: 0, testsDropped: 0, outsideLib: 0, overBudget: false };
    const c = pricePass(
      [
        { ...base, label: "a", tokens: 100_000, files: 4, tests: 2 },
        { ...base, label: "b", tokens: 271_000, files: 1, tests: 0 },
      ],
      { tokenRatio: 1.01, outPerFile: 1000, outPerTest: 80, rewriteRate: 0.5 },
      { firstInput: 1, cachedInput: 0.1, output: 10 },
    );
    expect(c.over272k).toEqual(["b"]);
    expect(c.outputTokens).toBe(5160);
    expect(c.inputTokens).toBeCloseTo(371_000 * 1.01 * 1.5);
    expect(c.usd).toBeCloseTo((371_000 * 1.01 * (1 + 0.05) + 5160 * 10) / 1e6);
  });

  it("leaves vendored trees out of the graph", () => {
    expect(excludedPath("vendor/harbor/src/harbor/job.py")).toBe(true);
    expect(excludedPath("experiments/vendor_notes.py")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// The builder over an in-memory repository. Tokens are counted as characters.

class FakeRepo {
  constructor(private files: Record<string, string>) {}
  async show(_c: string, p: string) {
    return this.files[p] ?? null;
  }
  async lsTree(_c: string, prefix: string) {
    return Object.keys(this.files).filter((p) => prefix === "." || p.startsWith(prefix));
  }
  async sizes(_c: string, prefix: string) {
    return new Map(Object.entries(this.files).filter(([p]) => prefix === "." || p.startsWith(prefix)).map(([p, t]) => [p, t.length]));
  }
  async ignored() {
    return [];
  }
  async diff() {
    return "";
  }
  async grep(_c: string, _pattern: string, specs: string[]) {
    const out: { path: string; line: number; text: string }[] = [];
    const excluded = specs.filter((s) => s.startsWith(":(exclude)")).map((s) => s.slice(":(exclude)".length));
    for (const [p, t] of Object.entries(this.files)) {
      if (!p.endsWith(".py") || excluded.some((e) => p.startsWith(e))) continue;
      t.split("\n").forEach((text, i) => {
        if (/^\s*(from|import)\s/.test(text)) out.push({ path: p, line: i + 1, text });
      });
    }
    return out;
  }
}

const dirs: string[] = [];
afterAll(() => {
  for (const d of dirs) rmSync(d, { recursive: true, force: true });
});

function setup(files: Record<string, string>, budget: number) {
  const prompts = mkdtempSync(path.join(tmpdir(), "prompts-"));
  const wordbase = mkdtempSync(path.join(tmpdir(), "wb-"));
  dirs.push(prompts, wordbase);
  writeFileSync(path.join(prompts, "describe-unit.md"), "U {{unit}} {{package}} {{commit}} {{unit_kind}}\n");
  const repo = new FakeRepo(files) as unknown as MarinRepo;
  return new ContextBuilder(repo, "c0ffee", { wordbase, prompts, budget, tokens: (t) => t.length, ignoreExisting: true });
}

const pad = (n: number) => `# ${"x".repeat(n)}\n`;

describe("ContextBuilder", () => {
  const files: Record<string, string> = {
    "lib/p/README.md": `# p\n${"r".repeat(30_000)}\n`, // longer than the old 20,000-character cut
    "lib/p/src/p/a.py": "def a():\n    return 1\n\ndef a2():\n    return 2\n",
    "lib/p/src/p/b.py": "from p.a import a\n\ndef b():\n    return a()\n",
    "lib/p/tests/test_a.py": "from p.a import a, a2\n\ndef test_a():\n    assert a() == 1\n",
    "lib/q/tests/test_uses_p.py": "from p.b import b\nfrom q.m import m\nfrom q.m import n\n\ndef test_q():\n    assert b()\n",
    "lib/q/src/q/m.py": `from p.a import a\n${pad(200)}`,
    "experiments/run_p.py": `from p.b import b\n${pad(300)}`,
    "scripts/tool.py": `from p.a import a\n${pad(100)}`,
    "vendor/up/mod.py": "from p.a import a\n",
    "lib/p/tests/conftest.py": "import pytest\n",
  };

  it("gives every file in full, the unit's own tests first, and callers from outside lib/, but nothing from vendor/", async () => {
    const b = setup(files, 1_000_000);
    const unit = { dir: "lib/p/src/p", package: "p", commit: "c0ffee", files: ["lib/p/src/p/a.py", "lib/p/src/p/b.py"], targets: ["lib/p/src/p/a.py", "lib/p/src/p/b.py"], testTargets: ["lib/p/tests/test_a.py"] };
    const planned = await b.plan(unit);
    expect(planned.units).toHaveLength(1);
    expect(planned.units[0]!.tests).toEqual(["lib/p/tests/test_a.py"]);
    const ctx = await b.build(planned.units[0]!);
    const text = ctx.inputs;
    expect(text).toContain("r".repeat(30_000)); // the README is not cut
    const at = (s: string) => text.indexOf(s);
    expect(at("=== BEGIN TEST lib/p/tests/test_a.py (one of the unit's own tests) ===")).toBeGreaterThan(at("=== BEGIN README ==="));
    expect(at("=== BEGIN TEST lib/q/tests/test_uses_p.py (imports the unit) ===")).toBeGreaterThan(at("=== BEGIN TEST lib/p/tests/test_a.py"));
    expect(at("=== BEGIN NEIGHBOUR")).toBeGreaterThan(at("=== BEGIN TEST lib/q/tests/test_uses_p.py"));
    expect(text).toContain(`=== BEGIN NEIGHBOUR experiments/run_p.py (imports the unit) ===\nfrom p.b import b\n${pad(300)}`);
    expect(text).not.toContain("vendor/up/mod.py");
    expect(text).toMatch(/=== BEGIN TEST TARGETS ===\nlib\/p\/tests\/test_a.py\n=== END TEST TARGETS ===/);
    expect(ctx.stats.outsideLib.sort()).toEqual(["experiments/run_p.py", "scripts/tool.py"]);
    expect(ctx.stats.neighboursDropped).toEqual([]);
    expect(ctx.stats.tokens).toBe(ctx.header!.length + 2 + ctx.inputs.length);
  });

  it("drops neighbours before tests when the budget is short, and lists what it left out", async () => {
    const full = await setup(files, 1_000_000).build({ dir: "lib/p/src/p", package: "p", commit: "c0ffee", files: ["lib/p/src/p/a.py", "lib/p/src/p/b.py"], targets: ["lib/p/src/p/a.py"], tests: ["lib/p/tests/test_a.py"] });
    // Room for the tests and about one neighbour.
    const b = setup(files, full.stats.tokens + 1500 - 400);
    const ctx = await b.build({ dir: "lib/p/src/p", package: "p", commit: "c0ffee", files: ["lib/p/src/p/a.py", "lib/p/src/p/b.py"], targets: ["lib/p/src/p/a.py"], tests: ["lib/p/tests/test_a.py"] });
    expect(ctx.stats.tokens).toBeLessThanOrEqual(ctx.stats.budget);
    expect(ctx.stats.tests).toEqual(["lib/p/tests/test_a.py", "lib/q/tests/test_uses_p.py"]);
    expect(ctx.stats.neighboursDropped.length).toBeGreaterThan(0);
    for (const p of ctx.stats.neighboursDropped) expect(ctx.inputs).toMatch(new RegExp(`=== BEGIN LEFT OUT ===[\\s\\S]*${p.replace(/[./]/g, "\\$&")}`));
    expect([...ctx.stats.neighbours, ...ctx.stats.neighboursDropped].sort()).toEqual(["experiments/run_p.py", "lib/q/src/q/m.py", "scripts/tool.py"]);
  });

  it("splits a unit whose files and own tests pass the budget, each test riding with the file it imports most from", async () => {
    const big: Record<string, string> = { "lib/p/README.md": "# p\n" };
    for (const n of ["a", "b", "c", "d"]) {
      big[`lib/p/src/p/${n}.py`] = `def ${n}():\n    return 1\n${pad(3000)}`;
      big[`lib/p/tests/test_${n}.py`] = `from p.${n} import ${n}\n${pad(1000)}`;
    }
    const b = setup(big, 12_000);
    const files = ["a", "b", "c", "d"].map((n) => `lib/p/src/p/${n}.py`);
    const planned = await b.plan({ dir: "lib/p/src/p", package: "p", commit: "c0ffee", files, targets: files, testTargets: ["lib/p/tests/test_b.py", "lib/p/tests/test_d.py"] });
    expect(planned.units.length).toBeGreaterThan(1);
    expect(planned.units.flatMap((u) => u.files)).toEqual(files);
    for (const u of planned.units) {
      expect(u.slice).toEqual({ index: planned.units.indexOf(u) + 1, of: planned.units.length });
      expect(u.tests).toEqual(u.files.map((f) => f.replace("src/p/", "tests/test_")));
      expect(u.targets).toEqual(u.files);
      expect(u.testTargets).toEqual(u.tests!.filter((t) => t.endsWith("_b.py") || t.endsWith("_d.py")));
    }
    expect(planned.overflow).toEqual([]);
    const { contexts } = await b.contexts({ dir: "lib/p/src/p", package: "p", commit: "c0ffee", files, targets: files });
    for (const c of contexts) expect(c.stats.tokens).toBeLessThanOrEqual(12_000);
  });

  it("sends an owned test that cannot fit beside its file to the overflow, and builds orphan batches without neighbours", async () => {
    const b = setup({ "lib/p/src/p/a.py": "def a():\n    return 1\n", "lib/p/tests/test_a.py": `from p.a import a\n${pad(9000)}`, "lib/p/tests/conftest.py": "import pytest\n", "lib/p/tests/helpers.py": "import os\n" }, 8000);
    const planned = await b.plan({ dir: "lib/p/src/p", package: "p", commit: "c0ffee", files: ["lib/p/src/p/a.py"], targets: ["lib/p/src/p/a.py"], testTargets: ["lib/p/tests/test_a.py"] });
    expect(planned.units[0]!.tests).toEqual([]);
    expect(planned.overflow).toEqual(["lib/p/tests/test_a.py"]);
    const orphans = [...(await b.owners())].filter(([, d]) => d === null).map(([t]) => t);
    expect(orphans).toEqual(["lib/p/tests/conftest.py", "lib/p/tests/helpers.py"]);
    const batches = await b.orphanBatches(orphans);
    expect(batches).toHaveLength(1);
    const ctx = await b.build(batches[0]!);
    expect(ctx.inputs).not.toMatch(/BEGIN NEIGHBOUR/);
    expect(ctx.inputs).toMatch(/=== BEGIN TEST TARGETS ===\nlib\/p\/tests\/conftest.py\nlib\/p\/tests\/helpers.py\n=== END TEST TARGETS ===/);
  });
});
