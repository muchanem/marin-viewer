import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import type { Backend, Completion, CompleteOptions, Turn } from "./backends.js";
import {
  checkPage,
  dependencyWaves,
  normaliseDiagram,
  PAGE_SCHEMA,
  parsePage,
  readmeOpening,
  scriptModules,
  SpendStop,
  writeSystemPage,
  type DepGraph,
  type SystemInputs,
} from "./systems.js";

const prompts = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../prompts");

const graph: DepGraph = new Map([
  ["rigging", { uses: [], used_by: ["iris", "zephyr"] }],
  ["iris", { uses: ["rigging"], used_by: ["zephyr"] }],
  ["zephyr", { uses: ["iris", "rigging"], used_by: [] }],
  ["shellbox", { uses: ["iris"], used_by: [] }],
]);

describe("dependency waves", () => {
  it("puts a package after every package it uses, counting kept pages as done", () => {
    expect(dependencyWaves(graph, ["zephyr", "iris", "rigging"])).toEqual([["rigging"], ["iris"], ["zephyr"]]);
    expect(dependencyWaves(graph, ["zephyr", "shellbox"])).toEqual([["shellbox", "zephyr"]]);
  });

  it("throws on a cycle", () => {
    const cyc: DepGraph = new Map([
      ["a", { uses: ["b"], used_by: ["b"] }],
      ["b", { uses: ["a"], used_by: ["a"] }],
    ]);
    expect(() => dependencyWaves(cyc, ["a", "b"])).toThrow(/cycle/);
  });
});

describe("inputs", () => {
  it("takes the README's first prose paragraph", () => {
    expect(readmeOpening("# Iris\n\n![badge](x)\n\nIris schedules jobs on clusters of machines and keeps their state.\n\nMore.")).toBe("Iris schedules jobs on clusters of machines and keeps their state.");
    expect(readmeOpening("# Title\n\n```\ncode only\n```\n")).toBeNull();
  });

  it("reads script modules from pyproject.toml", () => {
    expect(scriptModules('[project]\nname="x"\n\n[project.scripts]\niris = "iris.cli.main:cli"\nfoo = \'foo.bar\'\n\n[tool.x]\na = "b:c"\n')).toEqual(["iris.cli.main", "foo.bar"]);
    expect(scriptModules("[project]\n")).toEqual([]);
  });
});

const box = (id: string, col: number, row: number, extra: Record<string, unknown> = {}) => ({ id, label: id, sub: "a part", paths: [`lib/${id}/`], grid: { col, row }, ...extra });
const ctx = { system: "iris", uses: ["rigging"], used_by: ["zephyr", "shellbox"], paths: new Set(["lib/iris/src/iris/", "lib/iris/src/iris/a.py"]) };

describe("page checks", () => {
  it("accepts a map whose boxes cover every neighbour, one of them through systems", () => {
    const d = {
      layout: { mode: "grid" },
      nodes: [box("zephyr", 0, 0), { id: "users", label: "Others", sub: "shellbox", paths: ["lib/shellbox/"], systems: ["shellbox"], grid: { col: 1, row: 0 } }, box("iris", 0, 1), box("rigging", 1, 1), { id: "core", label: "Core", sub: "the parts", paths: ["lib/iris/src/iris/"], grid: { col: 0, row: 2 } }],
      edges: [["zephyr", "iris"], ["iris", "rigging"], ["iris", "core"]],
    };
    // One package under systems is its own box by name.
    expect(checkPage({ l1: "Runs jobs.", diagram: d }, ctx)).toEqual(["diagram: box users stands for the one package shellbox; give it the id shellbox and drop systems"]);
    d.nodes[1] = box("shellbox", 1, 0);
    expect(checkPage({ l1: "Runs jobs.", diagram: d }, ctx)).toEqual([]);
  });

  it("names every problem a map has", () => {
    const nodes = Array.from({ length: 11 }, (_, i) => ({ id: `n${i}`, label: `N${i}`, sub: "a part", paths: ["lib/iris/src/iris/"], grid: { col: i % 5, row: Math.floor(i / 5) } }));
    nodes[1]!.grid = { col: 0, row: 0 };
    nodes[2]!.paths = ["lib/iris/missing.py"];
    nodes[3]!.sub = "far too many words in this one sub line";
    const p = checkPage({ l1: "Runs jobs. Then more.", diagram: { layout: { mode: "grid" }, nodes, edges: [["n0", "nope"]] } }, ctx);
    expect(p).toContain("l1: must be a single sentence");
    expect(p).toContain("diagram: 11 boxes, more than 10");
    expect(p).toContain("diagram: box n1 takes row 0 col 0, already taken by n0");
    expect(p).toContain("diagram: box n2 names path lib/iris/missing.py, which is not in the package at this commit");
    expect(p).toContain("diagram: box n3 has a sub of 9 words; give it one to four");
    expect(p).toContain("diagram: grid is 5 columns by 3 rows; the card allows 4 by 3");
    expect(p).toContain("diagram: no box has the id iris");
    expect(p).toContain("diagram: neighbour rigging has no box (give it one, or list it under a box's systems)");
    expect(p).toContain('diagram: edge ["n0","nope"] names a box that does not exist');
  });

  it("requires a map on a fresh page", () => {
    expect(checkPage({ l1: "Runs jobs." }, { ...ctx, requireDiagram: true })[0]).toMatch(/has no "diagram" object/);
    expect(checkPage({ l1: "Runs jobs." }, ctx)).toEqual([]);
  });

  it("turns the schema's edge objects into the wordbase's arrays", () => {
    const d = normaliseDiagram({ nodes: [{ id: "a", label: "A", sub: "x", paths: [], grid: { col: 0, row: 0 } }], edges: [{ from: "a", to: "b" }, { from: "a", to: "c", label: "calls" }] }) as Record<string, unknown>;
    expect(d.layout).toEqual({ mode: "grid" });
    expect(d.edges).toEqual([["a", "b"], ["a", "c", "calls"]]);
    expect((d.nodes as Record<string, unknown>[])[0]!.paths).toBeUndefined();
    expect(parsePage('```json\n{"l1": "Runs jobs.", "diagram": {"nodes": [], "edges": [{"from": "a", "to": "b"}]}}\n```').diagram).toEqual({ layout: { mode: "grid" }, nodes: [], edges: [["a", "b"]] });
    expect((PAGE_SCHEMA.required as string[]).includes("diagram")).toBe(true);
  });
});

/** A backend that answers each call from a list and records the options it was given. */
function scripted(name: string, replies: (string | Error)[]): Backend & { opts: CompleteOptions[]; turns: Turn[][] } {
  const b = {
    name,
    opts: [] as CompleteOptions[],
    turns: [] as Turn[][],
    async complete(turns: Turn[], opts: CompleteOptions = {}): Promise<Completion> {
      b.turns.push(turns);
      b.opts.push(opts);
      const r = replies.shift();
      if (r === undefined) throw new Error(`${name}: no reply left`);
      if (r instanceof Error) throw r;
      return { text: r, model: name, input_tokens: 100, output_tokens: 10, cache_read_tokens: 0, cost_usd: name === "writer" ? 1 : 0.25, latency_ms: 5 };
    },
  };
  return b;
}

const inputs: SystemInputs = {
  system: "iris",
  commit: "c0ffee",
  uses: ["rigging"],
  used_by: [],
  inputs: "=== BEGIN FILES ===\n- lib/iris/src/iris/a.py: Runs a.\n=== END FILES ===\n",
  paths: new Set(["lib/iris/src/iris/", "lib/iris/src/iris/a.py"]),
  stats: { tokens: 1, budget: 2, files: 1, filesWithL2: 0, l2Dropped: 0, tests: 0, testsDropped: 0, readmeTokens: 0, readmeCut: false, excerpts: [], excerptsDropped: [], neighbours: 1 },
  leftOut: [],
};
const goodMap = { nodes: [box("iris", 0, 1), box("rigging", 1, 1), { id: "core", label: "Core", sub: "jobs", paths: ["lib/iris/src/iris/"], grid: { col: 0, row: 2 } }], edges: [{ from: "iris", to: "rigging" }] };
const page = (l1: string, diagram: unknown = goodMap) => JSON.stringify({ l1, l2: "It runs `a`.", diagram });

describe("writing a page", () => {
  it("reads the page cold, rewrites once for gaps and map problems, and reads it again", async () => {
    const writer = scripted("writer", [page("Runs jobs.", { nodes: [box("iris", 0, 1)], edges: [] }), page("Runs jobs on machines.")]);
    const reader = scripted("reader", ['{"gaps": [{"where": "l1", "claim": "jobs", "problem": "not shown"}]}', '{"gaps": []}']);
    const r = await writeSystemPage({ inputs, prompts, writer, reader });
    expect(r.gapsBefore).toHaveLength(1);
    expect(r.gapsAfter).toEqual([]);
    expect(r.rewritten).toBe(true);
    expect(r.problems).toEqual([]);
    expect(r.page.l1).toBe("Runs jobs on machines.");
    expect(r.cost_usd).toBe(2.5);
    expect(r.costByModel).toEqual({ writer: 2, reader: 0.5 });
    // The rewrite turn carries the gap and the map problem, and both writer calls ask for the schema.
    const rewrite = writer.turns[1]!.at(-1)!.content;
    expect(rewrite).toMatch(/l1: "jobs": not shown/);
    expect(rewrite).toMatch(/neighbour rigging has no box/);
    expect(writer.opts.every((o) => o.jsonSchema === PAGE_SCHEMA)).toBe(true);
    // The cold reader's code half is a cache prefix shared by both reads.
    expect(reader.opts[0]!.cachePrefix).toBeTruthy();
    expect(reader.opts[0]!.cachePrefix).toBe(reader.opts[1]!.cachePrefix);
    expect(reader.turns[0]![0]!.content.indexOf("=== BEGIN CODE ===")).toBeLessThan(reader.turns[0]![0]!.content.indexOf("=== BEGIN DESCRIPTION ==="));
  });

  it("skips the rewrite when the page is clean, and records a failed cold read as null", async () => {
    const clean = await writeSystemPage({ inputs, prompts, writer: scripted("writer", [page("Runs jobs.")]), reader: scripted("reader", ['{"gaps": []}']) });
    expect(clean.rewritten).toBe(false);
    expect(clean.gapsBefore).toEqual([]);
    expect(clean.gapsAfter).toBeNull();

    const failed = await writeSystemPage({ inputs, prompts, writer: scripted("writer", [page("Runs jobs."), page("Runs jobs.")]), reader: scripted("reader", [new Error("overloaded"), '{"gaps": []}']) });
    expect(failed.gapsBefore).toBeNull();
    expect(failed.coldErrors).toEqual(["cold-before: overloaded"]);
  });

  it("keeps a clean first draft when the rewrite reads worse, and records both counts", async () => {
    const gap = (w: string) => ({ where: w, claim: "c", problem: "p" });
    const r = await writeSystemPage({
      inputs,
      prompts,
      writer: scripted("writer", [page("Runs jobs."), page("Runs jobs and more.")]),
      reader: scripted("reader", [JSON.stringify({ gaps: [gap("l1")] }), JSON.stringify({ gaps: [gap("l1"), gap("l2"), gap("l2")] })]),
    });
    expect(r.kept).toBe("draft");
    expect(r.page.l1).toBe("Runs jobs.");
    expect(r.gapsBefore).toHaveLength(1);
    expect(r.gapsAfter).toHaveLength(3);

    // A draft with a map problem is never kept over the rewrite.
    const bad = await writeSystemPage({
      inputs,
      prompts,
      writer: scripted("writer", [page("Runs jobs.", { nodes: [box("iris", 0, 1)], edges: [] }), page("Runs jobs and more.")]),
      reader: scripted("reader", [JSON.stringify({ gaps: [] }), JSON.stringify({ gaps: [gap("l1")] })]),
    });
    expect(bad.kept).toBe("rewrite");
    expect(bad.page.l1).toBe("Runs jobs and more.");
  });

  it("drops a map that still fails after the rewrite and keeps the reason", async () => {
    const bad = { nodes: [box("iris", 0, 1)], edges: [] };
    const r = await writeSystemPage({ inputs, prompts, writer: scripted("writer", [page("Runs jobs.", bad), page("Runs jobs.", bad)]), reader: scripted("reader", ['{"gaps": []}', '{"gaps": []}']) });
    expect(r.diagramDropped).toBe(true);
    expect(r.page.diagram).toBeUndefined();
    expect(r.problems).toEqual(["diagram: neighbour rigging has no box (give it one, or list it under a box's systems)"]);
  });

  it("stops at the spend cap before the call that would pass it", async () => {
    let spent = 0;
    const writer = scripted("writer", [page("Runs jobs.", { nodes: [], edges: [] }), page("Runs jobs.")]);
    const run = writeSystemPage({
      inputs,
      prompts,
      writer,
      reader: scripted("reader", ['{"gaps": []}']),
      beforeCall: (role) => {
        if (role === "rewrite" && spent >= 1) throw new SpendStop("cap");
      },
      afterCall: (c) => (spent += c.completion.cost_usd),
    });
    await expect(run).rejects.toBeInstanceOf(SpendStop);
    expect(writer.turns).toHaveLength(1);
  });
});
