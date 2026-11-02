import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { fileEntryPath, readEntry, saveEntry } from "../wordbase.js";
import type { Backend, Completion, Turn } from "./backends.js";
import { buildEntry, checkOutput, describeUnit, extractJson, markChangedNotes, renderDescribePrompt, writeEntries } from "./describe.js";
import type { UnitContext } from "./units.js";

const PROMPTS = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "prompts");
const T = ["lib/s/src/s/a.py", "lib/s/src/s/b.py"];

function ctx(targets = T): UnitContext {
  return { unit: { dir: "lib/s/src/s", package: "s", commit: "c".repeat(40), files: targets, targets }, inputs: "=== BEGIN TARGETS ===\nx\n=== END TARGETS ===\n", existing: new Map(), stats: { tokens: 0, budget: 256_000, chars: 0, sourceTokens: 0, tests: [], testsDropped: [], neighbours: [], neighboursDropped: [], outsideLib: [], overBudget: false } };
}

function fake(replies: string[]): Backend & { turns: Turn[][] } {
  const turns: Turn[][] = [];
  return {
    name: "fake",
    turns,
    async complete(t: Turn[]): Promise<Completion> {
      turns.push(t);
      return { text: replies.shift() ?? "{}", model: "fake", input_tokens: 10, output_tokens: 5, cache_read_tokens: 0, cost_usd: 0.01, latency_ms: 3 };
    },
  };
}

const good = JSON.stringify({
  "lib/s/src/s/a.py": { l1: "Parses the frame header and returns its length.", system: "s", symbols: [{ name: "parse", l1: "Reads four bytes." }] },
  "lib/s/src/s/b.py": { l1: "Writes frames to a pipe.", system: "s" },
});

describe("reply parsing and checks", () => {
  it("extracts JSON from fenced or chatty replies", () => {
    expect(extractJson('```json\n{"a": 1}\n```')).toEqual({ a: 1 });
    expect(extractJson('Here it is:\n{"a": {"b": 2}}\nDone.')).toEqual({ a: { b: 2 } });
    expect(() => extractJson("no json")).toThrow();
  });

  it("accepts a valid reply", () => {
    const c = checkOutput(good, T, new Set(), "s");
    expect(c.problems).toEqual([]);
    expect(c.lint.size).toBe(0);
  });

  it("reports missing targets, extra keys, keep without an entry, and multi-sentence l1", () => {
    const reply = JSON.stringify({ "lib/s/src/s/a.py": { keep: true }, "lib/s/src/s/c.py": { l1: "One. Two sentences.", system: "s" } });
    const c = checkOutput(reply, T, new Set(), "s");
    expect(c.problems.join("\n")).toMatch(/entries missing for lib\/s\/src\/s\/b.py/);
    expect(c.problems.join("\n")).toMatch(/keys that are not targets: lib\/s\/src\/s\/c.py/);
    expect(c.problems.join("\n")).toMatch(/keep given to a file without an existing entry/);
    expect(c.problems.join("\n")).toMatch(/l1 must be a single sentence/);
  });

  it("reads the tests map, checks it against the test targets and lints it", () => {
    const tests = ["lib/s/tests/test_a.py", "lib/s/tests/test_b.py"];
    const reply = JSON.parse(good);
    reply.tests = { "lib/s/tests/test_a.py": { l1: "Checks the header parser." }, "lib/s/tests/test_c.py": { l1: "Checks a thing — twice." } };
    const c = checkOutput(JSON.stringify(reply), T, new Set(), "s", tests);
    expect(c.output && Object.keys(c.output)).toEqual(T);
    expect(c.tests["lib/s/tests/test_a.py"]!.l1).toBe("Checks the header parser.");
    expect(c.problems).toEqual(["tests missing an l1: lib/s/tests/test_b.py", "tests that are not test targets: lib/s/tests/test_c.py"]);
    expect(c.lint.get("lib/s/tests/test_c.py")).toEqual(['l1: dash "—"']);
    reply.tests = { "lib/s/tests/test_a.py": { l2: "no l1" } };
    expect(checkOutput(JSON.stringify(reply), T, new Set(), "s", tests).problems[0]).toMatch(/tests map does not match/);
  });

  it("rejects a reply that does not match the schema", () => {
    const c = checkOutput(JSON.stringify({ "lib/s/src/s/a.py": { l2: "no l1" } }), T, new Set(), "s");
    expect(c.output).toBeNull();
    expect(c.problems[0]).toMatch(/schema/);
  });

  it("lints every text field", () => {
    const reply = JSON.stringify({ "lib/s/src/s/a.py": { l1: "Runs the loop — forever.", l2: "Additionally it retries.", system: "s", symbols: [{ name: "f", l1: "It sees the queue." }] }, "lib/s/src/s/b.py": { l1: "Writes frames.", system: "s" } });
    const c = checkOutput(reply, T, new Set(), "s");
    expect(c.lint.get("lib/s/src/s/a.py")).toEqual(['l1: dash "—"', 'l2: cadence-word "Additionally"', 'f.l1: banned-word "sees"']);
  });
});

describe("describeUnit", () => {
  it("renders the prompt with every placeholder filled", async () => {
    const p = await renderDescribePrompt(PROMPTS, ctx());
    expect(p).not.toMatch(/\{\{/);
    expect(p).not.toMatch(/<!--/);
    expect(p).toMatch(/The unit is `lib\/s\/src\/s` at commit `c{40}`/);
    expect(p).toMatch(/Backwards English/); // the style rules are inlined
  });

  it("sends one rewrite turn on lint hits and keeps the remaining hits", async () => {
    const bad = good.replace("Writes frames to a pipe.", "Writes frames — to a pipe.");
    const b = fake([bad, bad]);
    const r = await describeUnit(b, PROMPTS, ctx());
    expect(b.turns).toHaveLength(2);
    expect(b.turns[1]![2]!.content).toMatch(/dash/);
    expect(r.rewritten).toBe(true);
    expect(r.lint.get("lib/s/src/s/b.py")).toEqual(['l1: dash "—"']);
    expect(r.cost_usd).toBeCloseTo(0.02);
  });

  it("does not rewrite a clean reply", async () => {
    const b = fake([good]);
    const r = await describeUnit(b, PROMPTS, ctx());
    expect(b.turns).toHaveLength(1);
    expect(r.rewritten).toBe(false);
  });

  it("rejects output that still fails validation after one retry", async () => {
    const b = fake(["not json", "still not json"]);
    await expect(describeUnit(b, PROMPTS, ctx())).rejects.toThrow(/failed validation after one rewrite/);
    expect(b.turns).toHaveLength(2);
  });
});

describe("writing entries", () => {
  const dirs: string[] = [];
  afterEach(() => {
    for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
  });

  it("marks notes about changed symbols", () => {
    const notes = [{ text: "2026-11-01 · abc1234 · session x · `Task.close`: waits on one future." }, { text: "2026-11-01 · abc1234 · session x · unrelated" }];
    const out = markChangedNotes(notes, ["Task.close"], "def5678aaaa");
    expect(out[0]!.text).toMatch(/\(code changed at def5678\)$/);
    expect(out[1]!.text).not.toMatch(/code changed/);
    expect(markChangedNotes(out, ["Task.close"], "def5678aaaa")[0]!.text.match(/code changed/g)).toHaveLength(1);
  });

  it("keeps notes and other sections, replaces layers and symbols, and records lint", async () => {
    const wb = mkdtempSync(path.join(tmpdir(), "wb-"));
    dirs.push(wb);
    const file = fileEntryPath(wb, "lib/s/src/s/a.py");
    await saveEntry(file, { front: { kind: "file", path: "lib/s/src/s/a.py", commit: "old", l1: "Old text.", system: "s" }, preamble: "", symbols: [{ name: "old", fields: { l1: "x" } }], notes: [{ text: "2026-11-01 · abc1234 · session x · `parse`: note" }], other: [{ heading: "Extra", body: "kept" }] });
    const result = { tests: {}, output: JSON.parse(good.replace('"system":"s","symbols"', '"system":"s","changed_symbols":["parse"],"symbols"')), lint: new Map([["lib/s/src/s/b.py", ['l1: dash "x"']]]), completions: [], rewritten: false, rewriteReason: [], cost_usd: 0, latency_ms: 0 };
    const w = await writeEntries(wb, result, { commit: "n".repeat(40), by: "fake poll nnnnnnn", now: "2026-11-01T00:00:00Z" });
    expect(w.files).toHaveLength(2);
    expect(w.l1Changed.sort()).toEqual(T);
    expect(w.lintHits).toBe(1);
    const a = (await readEntry(file))!;
    expect(a.front.l1).toBe("Parses the frame header and returns its length.");
    expect(a.front.commit).toBe("n".repeat(40));
    expect(a.symbols.map((s) => s.name)).toEqual(["parse"]);
    expect(a.notes[0]!.text).toMatch(/code changed at nnnnnnn/);
    expect(a.other).toEqual([{ heading: "Extra", body: "kept" }]);
    const b = (await readEntry(fileEntryPath(wb, "lib/s/src/s/b.py")))!;
    expect(b.front.lint).toEqual(['l1: dash "x"']);
  });

  it("writes a test file's entry as its l1 alone and keeps its notes", async () => {
    const wb = mkdtempSync(path.join(tmpdir(), "wb-"));
    dirs.push(wb);
    const file = fileEntryPath(wb, "lib/s/tests/test_a.py");
    await saveEntry(file, { front: { kind: "file", path: "lib/s/tests/test_a.py", l1: "Old.", l2: "Old paragraph.", system: "s" }, preamble: "", symbols: [{ name: "test_x", fields: { l1: "x" } }], notes: [{ text: "a note" }], other: [] });
    const result = { output: {}, tests: { "lib/s/tests/test_a.py": { l1: "Checks that `parse` rejects a short header." } }, lint: new Map(), completions: [], rewritten: false, rewriteReason: [], cost_usd: 0, latency_ms: 0 };
    const w = await writeEntries(wb, result, { commit: "n".repeat(40), by: "fake", now: "2026-11-02T00:00:00Z" });
    expect(w.tests).toEqual(["lib/s/tests/test_a.py"]);
    const e = (await readEntry(file))!;
    expect(e.front.l1).toBe("Checks that `parse` rejects a short header.");
    expect(e.front.l2).toBeUndefined();
    expect(e.front.test).toBe(true);
    expect(e.symbols).toEqual([]);
    expect(e.notes.map((n) => n.text)).toEqual(["a note"]);
  });

  it("builds an entry without empty layers", () => {
    const e = buildEntry(null, "lib/s/src/s/a.py", { l1: "Does a thing.", system: "s" }, { commit: "c", by: "b", now: "t" });
    expect(Object.keys(e.front)).toEqual(["kind", "path", "commit", "updated", "by", "l1", "system"]);
  });
});
