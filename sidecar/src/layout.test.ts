import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { CARD, DEFAULT_MIN_SCALE, clip, layoutDiagram, measureEdgeLabel, measureNode, type Box, type LayoutResult } from "./layout.js";
import { Diagram, type DiagramInput } from "./protocol.js";

// STEP_DIA[6] from demo/index.html in the section 6 Diagram format: the demo's coordinates are
// dropped, group membership is the boxes each group rectangle contained, and `at` names the
// function (as in wordbase/prs/10640/diagrams.json).
const G = "lib/shellbox/src/shellbox/http_service_guest.py";
const H = "lib/shellbox/src/shellbox/http_service.py";
const STEP6: DiagramInput = {
  title: "Relay HTTP to the host",
  nodes: [
    { id: "cl", label: "guest client", sub: "HTTP to 127.0.0.1" },
    { id: "sl", label: "slots", sub: "16, non-blocking", at: { path: G, function: "Server.process_request" } },
    { id: "hr", label: "handle_request", sub: "one thread each", at: { path: G, function: "Handler.handle_request" } },
    { id: "em", label: "emit", sub: "JSON line, stdout", at: { path: G, function: "Server.emit" } },
    { id: "rr", label: "receive_responses", sub: "stdin reader", at: { path: G, function: "receive_responses" } },
    { id: "pu", label: "_pump", sub: "FIRST_COMPLETED", at: { path: H, function: "_pump" } },
    { id: "rs", label: "_response", sub: "600 s wait_for", at: { path: H, function: "_response" } },
    { id: "hd", label: "handler", sub: "holds credentials" },
    { id: "wr", label: "session.write", sub: "response frame", at: { path: H, function: "_pump" } },
  ],
  edges: [["cl", "sl"], ["cl", "hr"], ["hr", "em", "request"], ["em", "pu", "stdout"], ["pu", "rs", "task"], ["rs", "hd"], ["pu", "wr"], ["wr", "rr", "stdin"], ["rr", "hr", "ready.set"]],
  groups: [
    { label: "Guest helper in the primary", members: ["cl", "sl", "hr", "em", "rr"] },
    { label: "Host process", members: ["pu", "rs", "hd", "wr"] },
  ],
};

// Grid cells read off the demo's hand-placed x/y (distinct x positions become columns, distinct
// y bands become rows), for the three diagrams whose picture depends on placement.
const STEP6_CELLS: Record<string, [number, number]> = { cl: [0, 0], sl: [1, 0], rs: [2, 0], hd: [3, 0], hr: [0, 1], pu: [2, 1], em: [0, 2], rr: [1, 2], wr: [3, 2] };
const STEP2: DiagramInput = {
  title: "Start the members",
  layout: { mode: "grid" },
  nodes: [
    { id: "ct", label: "create_task", sub: "checks policy, names", grid: { col: 0, row: 0 } },
    { id: "cp", label: "_create(primary)", sub: "own network namespace", grid: { col: 1, row: 0 } },
    { id: "sk", label: "_start_keeper", sub: "--unshare-net if DENY", grid: { col: 1, row: 1 } },
    { id: "cm", label: "_create(peer=)", sub: "joins primary netns", grid: { col: 2, row: 0 } },
    { id: "mo", label: "monitor task", sub: "ENTRYPOINT + CMD", grid: { col: 3, row: 0 } },
    { id: "cf", label: "_companion_finished", sub: "any exit", grid: { col: 3, row: 1 } },
    { id: "ex", label: "_expire", sub: "TTL", grid: { col: 0, row: 2 } },
    { id: "tc", label: "Task.close", sub: "one shared future", grid: { col: 2, row: 2, span: 2 } },
  ],
  edges: [["ct", "cp"], ["cp", "sk"], ["cp", "cm", "peer"], ["cm", "mo"], ["mo", "cf"], ["cf", "tc"], ["ex", "tc"]],
  groups: [{ label: "Members after the primary", members: ["cm", "mo", "cf"] }],
};
const PR_MAP: DiagramInput = {
  layout: { mode: "grid" },
  nodes: [
    { id: "driver", label: "Host handler", sub: "holds credentials", step: 6, grid: { col: 0, row: 0 } },
    { id: "relay", label: "serve_http relay", sub: "bounded frames", step: 6, grid: { col: 1, row: 0 } },
    { id: "session", label: "ProcessSession", sub: "shared lifecycle", step: 4, grid: { col: 1, row: 1 } },
    { id: "pipes", label: "Local, Docker pipes", sub: "subprocess", step: 4, grid: { col: 0, row: 2 } },
    { id: "daytona", label: "Daytona bridge", sub: "text codec", step: 5, grid: { col: 1, row: 2 } },
    { id: "spec", label: "TaskSpec", sub: "containers, probes", step: 1, grid: { col: 2, row: 0, span: 2 } },
    { id: "group", label: "Primary", sub: "guest helper", step: 2, grid: { col: 2, row: 2 } },
    { id: "runtime", label: "Runtime", sub: "readiness probe", step: 3, grid: { col: 3, row: 2 } },
    { id: "teardown", label: "Teardown", sub: "cancel-safe", step: 7, grid: { col: 2, row: 1, span: 2 } },
    { id: "limits", label: "OCI roots, cgroups", sub: "local only", step: 8, grid: { col: 0, row: 1 } },
  ],
  edges: [["driver", "relay"], ["relay", "session"], ["session", "pipes"], ["session", "daytona"], ["pipes", "group"], ["group", "runtime", "loopback"], ["spec", "teardown"], ["teardown", "group"], ["daytona", "group"]],
  groups: [{ label: "Bubblewrap task, external network denied", members: ["group", "runtime"] }],
};
const STEP6_GRID: DiagramInput = {
  ...STEP6,
  layout: { mode: "grid" },
  nodes: STEP6.nodes.map((n) => ({ ...n, grid: { col: STEP6_CELLS[n.id]![0], row: STEP6_CELLS[n.id]![1] } })),
};

const inside = (a: Box, b: Box, slack = 0.5) => a.x >= b.x - slack && a.y >= b.y - slack && a.x + a.w <= b.x + b.w + slack && a.y + a.h <= b.y + b.h + slack;
const overlap = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
const dist = (p: [number, number], b: Box) => Math.hypot(Math.max(b.x - p[0], 0, p[0] - (b.x + b.w)), Math.max(b.y - p[1], 0, p[1] - (b.y + b.h)));
function checkGeometry(out: LayoutResult, name: string): void {
  const byId = new Map(out.nodes.map((n) => [n.id, n]));
  const CARD_BOX: Box = { x: 0, y: 0, w: out.width, h: out.height };
  expect(out.minScale).toBe(DEFAULT_MIN_SCALE);
  expect(out.scale).toBeGreaterThanOrEqual(out.minScale);
  expect(out.scale).toBeLessThanOrEqual(1);
  if (out.overflow) {
    expect(out.scale).toBe(out.minScale);
    expect(out.width >= CARD.width && out.height >= CARD.height).toBe(true);
    expect(out.width > CARD.width || out.height > CARD.height).toBe(true);
  } else {
    expect([out.width, out.height]).toEqual([CARD.width, CARD.height]);
  }
  for (const n of out.nodes) expect(inside(n, CARD_BOX), `${name}: ${n.id} on the card`).toBe(true);
  for (const a of out.nodes) for (const b of out.nodes) if (a !== b) expect(overlap(a, b), `${name}: ${a.id} vs ${b.id}`).toBe(false);
  out.groups.forEach((g, gi) => {
    expect(inside(g, CARD_BOX), `${name}: group ${g.label} on the card`).toBe(true);
    for (const m of g.members) {
      const n = byId.get(m)!;
      expect(n.group).toBe(gi);
      expect(inside(n, g), `${name}: ${m} inside ${g.label}`).toBe(true);
      expect(overlap(n, g.label_box), `${name}: ${m} clear of the ${g.label} label`).toBe(false);
    }
    for (const n of out.nodes) if (n.group !== gi) expect(overlap(n, g), `${name}: ${n.id} outside ${g.label}`).toBe(false);
    for (const h of out.groups) if (h !== g) expect(overlap(g, h), `${name}: groups ${g.label} / ${h.label}`).toBe(false);
  });
  for (const e of out.edges) {
    expect(e.points.length).toBeGreaterThanOrEqual(2);
    expect(dist(e.points[0]!, byId.get(e.from)!), `${name}: ${e.from}->${e.to} start`).toBeLessThan(1.5);
    expect(dist(e.points.at(-1)!, byId.get(e.to)!), `${name}: ${e.from}->${e.to} end`).toBeLessThan(1.5);
    if (e.label) expect(e.label_box, `${name}: ${e.from}->${e.to} label`).toBeDefined();
  }
}

describe("auto mode on the demo's step-6 diagram", async () => {
  const unwrapped = await layoutDiagram(STEP6, { wrapping: false });
  const out = await layoutDiagram(STEP6);
  const aspect = (o: LayoutResult) => o.natural.width / o.natural.height;
  console.log(
    `step 6 auto: before wrapping ${unwrapped.natural.width}x${unwrapped.natural.height} (aspect ${aspect(unwrapped).toFixed(2)}), ` +
      `after ${out.natural.width}x${out.natural.height} (aspect ${aspect(out).toFixed(2)}), drawn ${out.width}x${out.height} at scale ${out.scale}${out.overflow ? " (overflow)" : ""}`,
  );

  it("wraps into the card's shape", () => {
    expect(out.mode).toBe("auto");
    expect(aspect(unwrapped)).toBeGreaterThan(3.2);
    expect(aspect(out)).toBeGreaterThanOrEqual(1.6);
    expect(aspect(out)).toBeLessThanOrEqual(3.2);
    const fit = Math.min(1, (CARD.width - 8) / out.natural.width, (CARD.height - 8) / out.natural.height);
    expect(out.overflow).toBe(fit < DEFAULT_MIN_SCALE);
    expect(out.scale).toBeCloseTo(Math.max(fit, DEFAULT_MIN_SCALE), 3);
  });

  it("keeps boxes apart, members inside their groups, and edges on their boxes", () => {
    checkGeometry(out, "step 6 auto");
    expect(out.nodes.map((n) => n.id)).toEqual(STEP6.nodes.map((n) => n.id));
    expect(out.nodes.find((n) => n.id === "pu")?.at).toEqual({ path: H, function: "_pump" });
    expect(out.edges.filter((e) => e.label).map((e) => e.label)).toEqual(["request", "stdout", "task", "stdin", "ready.set"]);
  });

  it("is deterministic", async () => {
    expect(await layoutDiagram(STEP6)).toEqual(out);
  });
});

describe("grid mode", () => {
  const cases: [string, DiagramInput][] = [["step 6", STEP6_GRID], ["step 2", STEP2], ["PR map", PR_MAP]];
  it.each(cases)("%s from the demo's placement", async (name, d) => {
    const out = await layoutDiagram(d);
    expect(out.mode).toBe("grid");
    expect(out.warnings).toEqual([]);
    checkGeometry(out, name);
  });

  it("keeps the demo's arrangement: guest beside host, rows in order, spans wider", async () => {
    const out = await layoutDiagram(STEP6_GRID);
    const n = Object.fromEntries(out.nodes.map((x) => [x.id, x]));
    expect(out.groups[0]!.x + out.groups[0]!.w).toBeLessThan(out.groups[1]!.x);
    expect(n.cl!.y).toBe(n.rs!.y);
    expect(n.cl!.y).toBeLessThan(n.hr!.y);
    expect(n.hr!.y).toBeLessThan(n.em!.y);
    expect(n.cl!.x).toBe(n.hr!.x); // one column, one x
    const s2 = await layoutDiagram(STEP2);
    const tc = s2.nodes.find((x) => x.id === "tc")!, cm = s2.nodes.find((x) => x.id === "cm")!, mo = s2.nodes.find((x) => x.id === "mo")!;
    expect(tc.x).toBeCloseTo(cm.x, 0);
    expect(tc.x + tc.w).toBeCloseTo(mo.x + mo.w, 0);
  });

  it("draws edges as straight segments clipped to the box borders", async () => {
    const out = await layoutDiagram(STEP6_GRID);
    for (const e of out.edges) expect(e.points).toHaveLength(2);
    const [p, q] = clip({ x: 0, y: 0, w: 100, h: 20 }, { x: 200, y: 0, w: 100, h: 20 });
    expect(p).toEqual([100, 10]);
    expect(q).toEqual([200, 10]);
  });

  it("lays out the fixture's grid-mode diagrams when they have cells", async () => {
    const file = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../wordbase/prs/10640/diagrams.json");
    let all: { pr: DiagramInput; steps: Record<string, DiagramInput> };
    try {
      all = JSON.parse(readFileSync(file, "utf8"));
    } catch {
      return; // fixture not built on this machine
    }
    const grid = [["pr", all.pr] as const, ...Object.entries(all.steps)].filter(([, d]) => d.layout?.mode === "grid");
    for (const [name, d] of grid) checkGeometry(await layoutDiagram(d), `fixture ${name}`);
    // Every fixture diagram lays out in its declared mode.
    for (const [name, d] of [["pr", all.pr] as const, ...Object.entries(all.steps)]) {
      const out = await layoutDiagram(d);
      expect(out.nodes.length, `fixture ${name}`).toBe(d.nodes.length);
    }
  });

  it("rejects missing cells and collisions with readable errors", async () => {
    const missing = { ...STEP2, nodes: STEP2.nodes.map((n, i) => (i === 3 ? { id: n.id, label: n.label } : n)) };
    const r = Diagram.safeParse(missing);
    expect(!r.success && r.error.issues[0]!.message).toBe('grid layout needs a grid cell on every node; missing on "cm"');
    await expect(layoutDiagram(missing)).rejects.toThrow(/missing on "cm"/);
    await expect(layoutDiagram(STEP6, { mode: "grid" })).rejects.toThrow(/missing on "cl", "sl"/);
    const clash = { ...STEP2, nodes: STEP2.nodes.map((n) => (n.id === "ex" ? { ...n, grid: { col: 1, row: 1 } } : n)) };
    await expect(layoutDiagram(clash)).rejects.toThrow(/grid cell \(col 1, row 1\) is taken by both "sk" and "ex"/);
  });

  it("warns when a group's box swallows a non-member", async () => {
    const d: DiagramInput = {
      layout: { mode: "grid" },
      nodes: [{ id: "a", label: "A", grid: { col: 0, row: 0 } }, { id: "b", label: "B", grid: { col: 1, row: 0 } }, { id: "c", label: "C", grid: { col: 2, row: 0 } }],
      groups: [{ label: "ends", members: ["a", "c"] }],
    };
    expect((await layoutDiagram(d)).warnings).toEqual(['node "b" lies inside group "ends" without being a member']);
  });
});

describe("grid table sizing", () => {
  const box = (id: string, label: string, col: number, row: number, span?: number) => ({ id, label, grid: { col, row, ...(span ? { span } : {}) } });
  const sizes = { a: { w: 100, h: 30 }, b: { w: 60, h: 20 }, c: { w: 80, h: 40 }, wide: { w: 400, h: 20 }, narrow: { w: 50, h: 20 } };

  it("gives each column its widest single-span box and each row its tallest box", async () => {
    // a b / c . ; columns 100 and 60, rows 30 and 40, gaps 20 and 18, margin 8.
    const out = await layoutDiagram({ layout: { mode: "grid" }, nodes: [box("a", "A", 0, 0), box("b", "B", 1, 0), box("c", "C", 0, 1)] }, { sizes });
    expect(out.natural).toEqual({ width: 8 + 100 + 20 + 60 + 8, height: 8 + 30 + 18 + 40 + 8 });
    const n = Object.fromEntries(out.nodes.map((x) => [x.id, x]));
    expect([n.a!.w, n.b!.w, n.c!.w]).toEqual([100, 60, 100]);
    expect([n.a!.h, n.b!.h, n.c!.h]).toEqual([30, 30, 40]);
    expect(out.scale).toBe(1);
  });

  it("covers a spanning box with its columns and gaps, widening only the last column when short", async () => {
    const base = [box("a", "A", 0, 0), box("b", "B", 1, 0)];
    const fits = await layoutDiagram({ layout: { mode: "grid" }, nodes: [...base, box("narrow", "N", 0, 1, 2)] }, { sizes });
    expect(fits.natural.width).toBe(8 + 100 + 20 + 60 + 8);
    expect(fits.nodes.find((x) => x.id === "narrow")!.w).toBe(100 + 20 + 60);
    const short = await layoutDiagram({ layout: { mode: "grid" }, nodes: [...base, box("wide", "W", 0, 1, 2)] }, { sizes });
    const n = Object.fromEntries(short.nodes.map((x) => [x.id, x]));
    expect(n.a!.w).toBe(100 * short.scale); // first column untouched
    expect(n.b!.w).toBeCloseTo((400 - 100 - 20) * short.scale, 1); // last column widened
    expect(n.wide!.w).toBeCloseTo(400 * short.scale, 1);
  });

  it("uses measured sizes when given and the calibrated estimate otherwise", async () => {
    expect(measureNode("serve_http relay", "bounded frames")).toEqual({ w: 112, h: 34 }); // demo: 116 x 34
    const est = await layoutDiagram({ layout: { mode: "grid" }, nodes: [box("a", "serve_http relay", 0, 0)] });
    expect(est.nodes[0]!.w).toBe(112);
    const measured = await layoutDiagram({ layout: { mode: "grid" }, nodes: [box("a", "serve_http relay", 0, 0)] }, { sizes: { a: { w: 131, h: 36 }, zz: { w: 1, h: 1 } } });
    expect([measured.nodes[0]!.w, measured.nodes[0]!.h]).toEqual([131, 36]);
    expect(measured.warnings).toEqual(['sizes names unknown node "zz"']);
    const auto = await layoutDiagram({ nodes: [{ id: "a", label: "x" }, { id: "b", label: "y" }], edges: [["a", "b"]] }, { sizes: { a: { w: 150, h: 40 } } });
    expect([auto.nodes[0]!.w, auto.nodes[0]!.h]).toEqual([150, 40]);
  });

  it("widens the gap a labelled edge crosses so its measured label clears both boxes", async () => {
    // The PR map's Primary -> Runtime "loopback" edge inside one group: the fixed 32 px gap is
    // narrower than the label, which then covered the boxes.
    const diagram: DiagramInput = {
      layout: { mode: "grid" },
      nodes: [box("a", "Primary", 0, 0), box("b", "Runtime", 1, 0), box("c", "Below", 0, 1)],
      edges: [["a", "b", "loopback"], ["a", "c", "probes"]],
      groups: [{ label: "G", members: ["a", "b", "c"] }],
    };
    const plain = await layoutDiagram({ ...diagram, edges: [["a", "b"], ["a", "c"]] }, { sizes });
    const out = await layoutDiagram(diagram, { sizes, edgeLabels: { loopback: { w: 50, h: 13 }, probes: { w: 40, h: 13 }, unused: { w: 1, h: 1 } } });
    const n = Object.fromEntries(out.nodes.map((x) => [x.id, x]));
    const gap = (n.b!.x - (n.a!.x + n.a!.w)) / out.scale;
    expect(gap).toBeCloseTo(50 + 12, 1);
    expect(out.natural.width).toBeCloseTo(plain.natural.width + (50 + 12 - 32), 1);
    const loopback = out.edges.find((e) => e.label === "loopback")!.label_box!;
    expect(loopback.w).toBeCloseTo(50 * out.scale, 1);
    expect(loopback.x).toBeGreaterThanOrEqual(n.a!.x + n.a!.w);
    expect(loopback.x + loopback.w).toBeLessThanOrEqual(n.b!.x);
    // A vertical edge's label sits beside the line, clear of both boxes.
    const probes = out.edges.find((e) => e.label === "probes")!.label_box!;
    expect(probes.y).toBeGreaterThanOrEqual(n.a!.y + n.a!.h);
    expect(probes.y + probes.h).toBeLessThanOrEqual(n.c!.y);
    expect(out.warnings).toContain('edgeLabels names unknown label "unused"');
  });

  it("estimates an edge label from the demo's 8.5 px font when the app sends no size", async () => {
    expect(measureEdgeLabel("loopback")).toEqual({ w: 47, h: 14 });
  });

  it("never shrinks below minScale: a too-wide diagram overflows at minScale", async () => {
    const nodes = Array.from({ length: 8 }, (_, i) => box(`n${i}`, `node${i}`, i, 0));
    const wideSizes = Object.fromEntries(nodes.map((n) => [n.id, { w: 120, h: 34 }]));
    const out = await layoutDiagram({ layout: { mode: "grid" }, nodes }, { sizes: wideSizes });
    expect(out.natural.width).toBe(8 + 8 * 120 + 7 * 20 + 8);
    expect(out.overflow).toBe(true);
    expect(out.scale).toBe(0.8);
    expect(out.width).toBeCloseTo(out.natural.width * 0.8 + 8, 1);
    expect(out.height).toBe(CARD.height);
    expect(out.nodes[0]!.w).toBeCloseTo(96, 1);
    const lower = await layoutDiagram({ layout: { mode: "grid" }, nodes }, { sizes: wideSizes, minScale: 0.3 });
    expect(lower.overflow).toBe(false);
    expect(lower.width).toBe(CARD.width);
    await expect(layoutDiagram({ nodes: [] }, { minScale: 0 })).rejects.toThrow(/minScale/);
  });
});

describe("input checks", () => {
  it("rejects edges and groups that name unknown nodes", async () => {
    await expect(layoutDiagram({ nodes: [{ id: "a", label: "A" }], edges: [["a", "b"]] })).rejects.toThrow(/unknown node "b"/);
    await expect(layoutDiagram({ nodes: [{ id: "a", label: "A" }], groups: [{ label: "G", members: ["z"] }] })).rejects.toThrow(/unknown node "z"/);
    await expect(layoutDiagram({ nodes: [{ id: "a", label: "A" }, { id: "a", label: "B" }] })).rejects.toThrow(/duplicate/);
  });
  it("lays out an empty and a top-down diagram, and keeps paths", async () => {
    expect((await layoutDiagram({ nodes: [] })).nodes).toEqual([]);
    const d = await layoutDiagram({ layout: { mode: "auto", direction: "DOWN" }, nodes: [{ id: "a", label: "A", paths: ["lib/a.py"] }, { id: "b", label: "B" }], edges: [["a", "b"]] }, { wrapping: false });
    expect(d.nodes[1]!.y).toBeGreaterThan(d.nodes[0]!.y);
    expect(d.nodes[0]!.paths).toEqual(["lib/a.py"]);
    expect(d.scale).toBe(1); // small diagrams are not enlarged
  });
});
