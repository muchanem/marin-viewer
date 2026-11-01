// Layout for section 6 Diagrams. The agent writes nodes, edges, groups and (in grid mode) cells;
// the sidecar measures boxes from their text, places them, routes edges, and fits the result to
// the strip's card (460×196) by uniform scaling. Every coordinate in the result is in card space.
//
// - auto: ELK layered with aspectRatio 2.35 and MULTI_EDGE wrapping. ELK skips wrapping on
//   hierarchical graphs, so groups are laid out in two levels: each group's members on their own,
//   then the group boxes and loose nodes together. Edges inside one ELK graph keep ELK's routes;
//   edges that cross a group border are straight segments clipped to the boxes.
// - grid: table-style sizing from the agent's col/row/span. Each column is as wide as its widest
//   single-span box and each row as tall as its tallest box; a spanning box covers its columns
//   plus the gaps between them and widens the last of them only if it still does not fit. Gaps
//   are fixed. Group boxes enclose their members; every edge is a straight clipped segment, like
//   the demo's clip().
//
// Box sizes come from the app's measured text (`sizes`) when it sends them, else from an
// estimate calibrated to the demo's fonts. Fitting never shrinks below `minScale` (default 0.8):
// a diagram that would need more shrinking comes back at minScale with `overflow: true`, and the
// app scrolls the card or opens a larger view.

import ElkModule from "elkjs/lib/elk.bundled.js";
import type { ELK as ElkApi, ElkExtendedEdge, ElkNode } from "elkjs/lib/elk-api.js";
import type { Diagram, DiagramInput } from "./protocol.js";
import { Diagram as DiagramSchema } from "./protocol.js";

export interface Box {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface LaidOutNode extends Box {
  id: string;
  label: string;
  sub?: string;
  step?: number;
  at?: { path: string; function?: string | undefined };
  paths?: string[];
  /** Index into `groups`, when the node belongs to one. */
  group?: number;
}

export interface LaidOutGroup extends Box {
  label: string;
  members: string[];
  label_box: Box;
}

export interface LaidOutEdge {
  from: string;
  to: string;
  label?: string;
  /** Polyline from the source box border to the target box border. */
  points: [number, number][];
  label_box?: Box;
}

export interface LayoutResult {
  title?: string;
  mode: "auto" | "grid";
  /**
   * Extent of the drawing: every coordinate lies inside [0, width] × [0, height]. Equal to the
   * card (460×196) unless `overflow`, when it is the natural size at `minScale` plus margins.
   */
  width: number;
  height: number;
  /** Card units per layout unit; the app scales text by the same factor. In [minScale, 1]. */
  scale: number;
  minScale: number;
  /** True when fitting the card would have needed a scale below minScale. */
  overflow: boolean;
  /** Size before fitting. */
  natural: { width: number; height: number };
  nodes: LaidOutNode[];
  groups: LaidOutGroup[];
  edges: LaidOutEdge[];
  warnings: string[];
}

export interface LayoutOptions {
  mode?: "auto" | "grid" | undefined;
  direction?: "RIGHT" | "DOWN" | undefined;
  /** Measured box sizes from the app's font, by node id, in layout units (scale 1). */
  sizes?: Record<string, { w: number; h: number }> | undefined;
  /** Smallest scale fitting may use; default 0.8. */
  minScale?: number | undefined;
  /** auto mode only; false turns ELK wrapping off (for comparison). */
  wrapping?: boolean | undefined;
}

export const CARD = { width: 460, height: 196 } as const;
export const ASPECT = 2.35;
export const DEFAULT_MIN_SCALE = 0.8;

// Estimates for when the app sends no measured sizes, calibrated to the demo's fonts: labels at
// 10.5 px (about 6 px per character), sub-labels and group labels at 9 px, edge labels at 8.5 px.
const LABEL_CHAR = 6;
const SUB_CHAR = (6 * 9) / 10.5;
const EDGE_CHAR = (6 * 8.5) / 10.5;
const PAD_X = 16; // the demo insets text 8 px on each side
export const GROUP_HEADER = 22;
const GROUP_PAD = 10;
const CARD_MARGIN = 4;

export function measureNode(label: string, sub?: string): { w: number; h: number } {
  const w = Math.max(label.length * LABEL_CHAR, (sub ?? "").length * SUB_CHAR) + PAD_X;
  return { w: Math.round(Math.min(240, Math.max(56, w))), h: sub ? 34 : 26 };
}

type SizeOf = (n: Diagram["nodes"][number]) => { w: number; h: number };

const r = (n: number | undefined) => Math.round((n ?? 0) * 10) / 10;

// elkjs is CommonJS: under Node ESM the default import is the constructor itself, while its
// typings describe `{ default: constructor }`. Accept both.
type ElkCtor = new () => ElkApi;
const ElkConstructor: ElkCtor = (ElkModule as unknown as { default?: ElkCtor }).default ?? (ElkModule as unknown as ElkCtor);
let elk: ElkApi | null = null;

// ---------------------------------------------------------------------------

export async function layoutDiagram(input: DiagramInput | Diagram, options: LayoutOptions = {}): Promise<LayoutResult> {
  const parsed = DiagramSchema.safeParse(input);
  if (!parsed.success) {
    throw new Error(`invalid diagram: ${parsed.error.issues.slice(0, 5).map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`).join("; ")}`);
  }
  const d = parsed.data;
  const mode = options.mode ?? d.layout?.mode ?? "auto";
  const direction = options.direction ?? d.layout?.direction ?? "RIGHT";
  const groupOf = validate(d);
  if (mode === "grid") {
    const missing = d.nodes.filter((n) => !n.grid).map((n) => JSON.stringify(n.id));
    if (missing.length) throw new Error(`grid layout needs a grid cell on every node; missing on ${missing.join(", ")}`);
  }
  const warnings: string[] = [];
  const ids = new Set(d.nodes.map((n) => n.id));
  const sizes = options.sizes ?? {};
  for (const [id, sz] of Object.entries(sizes)) {
    if (!ids.has(id)) warnings.push(`sizes names unknown node ${JSON.stringify(id)}`);
    else if (!(sz.w > 0 && sz.h > 0)) throw new Error(`sizes for ${JSON.stringify(id)} must be positive`);
  }
  const sizeOf: SizeOf = (n) => sizes[n.id] ?? measureNode(n.label, n.sub);
  const minScale = options.minScale ?? DEFAULT_MIN_SCALE;
  if (!(minScale > 0 && minScale <= 1)) throw new Error(`minScale must be in (0, 1], got ${minScale}`);
  const natural = mode === "grid" ? layoutGrid(d, groupOf, sizeOf) : await layoutAuto(d, groupOf, direction, options.wrapping ?? true, sizeOf);
  natural.warnings.unshift(...warnings);
  return fitToCard(d, mode, natural, minScale);
}

function validate(d: Diagram): Map<string, number> {
  const ids = new Set<string>();
  for (const n of d.nodes) {
    if (ids.has(n.id)) throw new Error(`duplicate node id ${JSON.stringify(n.id)}`);
    ids.add(n.id);
  }
  const groupOf = new Map<string, number>();
  d.groups.forEach((g, gi) => {
    for (const m of g.members) {
      if (!ids.has(m)) throw new Error(`group ${JSON.stringify(g.label)} names unknown node ${JSON.stringify(m)}`);
      if (groupOf.has(m)) throw new Error(`node ${JSON.stringify(m)} is in more than one group`);
      groupOf.set(m, gi);
    }
  });
  for (const [a, b] of d.edges) {
    for (const end of [a, b]) if (!ids.has(end)) throw new Error(`edge ${a} -> ${b} names unknown node ${JSON.stringify(end)}`);
  }
  return groupOf;
}

/** Positions in layout units, before fitting. */
interface Natural {
  width: number;
  height: number;
  boxes: Map<string, Box>;
  groups: Box[];
  /** Routed edges by index; missing ones are drawn straight. */
  routes: Map<number, { points: [number, number][]; label_box?: Box }>;
  warnings: string[];
}

// ---------------------------------------------------------------------------
// Straight edges, as the demo's clip(): from border to border along the centre line.

export function clip(a: Box, b: Box): [[number, number], [number, number]] {
  const ax = a.x + a.w / 2, ay = a.y + a.h / 2, bx = b.x + b.w / 2, by = b.y + b.h / 2;
  const f = (n: Box, dx: number, dy: number) => Math.min(dx ? n.w / 2 / Math.abs(dx) : Infinity, dy ? n.h / 2 / Math.abs(dy) : Infinity);
  const dx = bx - ax, dy = by - ay;
  if (!dx && !dy) return [[ax, ay], [bx, by]];
  const ta = f(a, dx, dy), tb = f(b, dx, dy);
  return [[ax + dx * ta, ay + dy * ta], [bx - dx * tb, by - dy * tb]];
}

function straight(a: Box, b: Box, label?: string): { points: [number, number][]; label_box?: Box } {
  const [p, q] = clip(a, b);
  if (!label) return { points: [p, q] };
  const w = label.length * EDGE_CHAR + 8;
  return { points: [p, q], label_box: { x: (p[0] + q[0]) / 2 - w / 2, y: (p[1] + q[1]) / 2 - 16, w, h: 14 } };
}

// ---------------------------------------------------------------------------
// auto

function elkOptions(direction: string, wrapping: boolean, padding: string): Record<string, string> {
  return {
    "elk.algorithm": "layered",
    "elk.direction": direction,
    "elk.aspectRatio": String(ASPECT),
    ...(wrapping ? { "elk.layered.wrapping.strategy": "MULTI_EDGE" } : {}),
    "elk.edgeRouting": "ORTHOGONAL",
    "elk.spacing.nodeNode": "18",
    "elk.layered.spacing.nodeNodeBetweenLayers": "30",
    "elk.spacing.edgeLabel": "2",
    "elk.edgeLabels.placement": "CENTER",
    "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX",
    // Back edges are the ones that point against the order the agent listed nodes in.
    "elk.layered.cycleBreaking.strategy": "MODEL_ORDER",
    "elk.layered.considerModelOrder.strategy": "NODES_AND_EDGES",
    "elk.padding": padding,
  };
}

interface FlatNode {
  id: string;
  width: number;
  height: number;
}

/** One flat ELK run. Returns node positions and routes for edges whose ends are both in it. */
async function runFlat(nodes: FlatNode[], edges: { i: number; from: string; to: string; label?: string | undefined }[], direction: string, wrapping: boolean, padding: string) {
  elk ??= new ElkConstructor();
  const graph: ElkNode = {
    id: "root",
    layoutOptions: elkOptions(direction, wrapping, padding),
    children: nodes.map((n) => ({ id: n.id, width: n.width, height: n.height })),
    edges: edges.map((e): ElkExtendedEdge => ({
      id: `e${e.i}`,
      sources: [e.from],
      targets: [e.to],
      ...(e.label ? { labels: [{ text: e.label, width: Math.round(e.label.length * EDGE_CHAR + 8), height: 14 }] } : {}),
    })),
  };
  const out = await elk.layout(graph);
  const boxes = new Map<string, Box>();
  for (const c of out.children ?? []) boxes.set(c.id, { x: c.x ?? 0, y: c.y ?? 0, w: c.width ?? 0, h: c.height ?? 0 });
  const routes = new Map<number, { points: [number, number][]; label_box?: Box }>();
  for (const e of out.edges ?? []) {
    const points: [number, number][] = [];
    for (const s of e.sections ?? []) {
      for (const pt of [s.startPoint, ...(s.bendPoints ?? []), s.endPoint]) {
        const last = points.at(-1);
        if (!last || last[0] !== pt.x || last[1] !== pt.y) points.push([pt.x, pt.y]);
      }
    }
    const lab = e.labels?.[0];
    routes.set(Number(e.id.slice(1)), { points, ...(lab ? { label_box: { x: lab.x ?? 0, y: lab.y ?? 0, w: lab.width ?? 0, h: lab.height ?? 0 } } : {}) });
  }
  return { width: out.width ?? 0, height: out.height ?? 0, boxes, routes };
}

async function layoutAuto(d: Diagram, groupOf: Map<string, number>, direction: string, wrapping: boolean, sizeOf: SizeOf): Promise<Natural> {
  const size = new Map(d.nodes.map((n) => [n.id, sizeOf(n)]));
  const edgeList = d.edges.map(([from, to, label], i) => ({ i, from, to, label }));
  const boxes = new Map<string, Box>();
  const routes: Natural["routes"] = new Map();
  const groupBoxes: Box[] = [];

  // Level 1: each group on its own, with room for its header.
  const inner = await Promise.all(
    d.groups.map(async (_g, gi) => {
      const members = d.nodes.filter((n) => groupOf.get(n.id) === gi);
      const own = edgeList.filter((e) => groupOf.get(e.from) === gi && groupOf.get(e.to) === gi);
      const res = await runFlat(members.map((n) => ({ id: n.id, width: size.get(n.id)!.w, height: size.get(n.id)!.h })), own, direction, wrapping, `[top=${GROUP_HEADER + 4},left=${GROUP_PAD},bottom=${GROUP_PAD},right=${GROUP_PAD}]`);
      const minW = d.groups[gi]!.label.length * SUB_CHAR + 2 * GROUP_PAD;
      return { ...res, width: Math.max(res.width, minW) };
    }),
  );

  // Level 2: group boxes and loose nodes; edges between them lifted to the group boxes.
  const gid = (gi: number) => `__group_${gi}`;
  const lift = (id: string) => (groupOf.has(id) ? gid(groupOf.get(id)!) : id);
  const top: FlatNode[] = [];
  const seenGroup = new Set<number>();
  for (const n of d.nodes) {
    const gi = groupOf.get(n.id);
    if (gi === undefined) top.push({ id: n.id, width: size.get(n.id)!.w, height: size.get(n.id)!.h });
    else if (!seenGroup.has(gi)) {
      seenGroup.add(gi);
      top.push({ id: gid(gi), width: inner[gi]!.width, height: inner[gi]!.height });
    }
  }
  for (let gi = 0; gi < d.groups.length; gi++) if (!seenGroup.has(gi)) top.push({ id: gid(gi), width: inner[gi]!.width, height: inner[gi]!.height });
  const pairs = new Set<string>();
  const topEdges: typeof edgeList = [];
  for (const e of edgeList) {
    const a = lift(e.from), b = lift(e.to);
    if (a === b && groupOf.has(e.from)) continue; // inside one group
    const bothLoose = !groupOf.has(e.from) && !groupOf.has(e.to);
    const key = `${a}->${b}`;
    if (!bothLoose && pairs.has(key)) continue;
    pairs.add(key);
    topEdges.push(bothLoose ? e : { i: -1 - e.i, from: a, to: b, label: undefined });
  }
  const outer = await runFlat(top, topEdges, direction, wrapping, "[top=8,left=8,bottom=8,right=8]");

  d.groups.forEach((_g, gi) => {
    const at = outer.boxes.get(gid(gi))!;
    groupBoxes.push(at);
    for (const [id, b] of inner[gi]!.boxes) boxes.set(id, { ...b, x: b.x + at.x, y: b.y + at.y });
    for (const [i, rt] of inner[gi]!.routes) {
      routes.set(i, {
        points: rt.points.map(([x, y]) => [x + at.x, y + at.y]),
        ...(rt.label_box ? { label_box: { ...rt.label_box, x: rt.label_box.x + at.x, y: rt.label_box.y + at.y } } : {}),
      });
    }
  });
  for (const [id, b] of outer.boxes) if (!id.startsWith("__group_")) boxes.set(id, b);
  for (const [i, rt] of outer.routes) if (i >= 0) routes.set(i, rt);

  return { width: outer.width, height: outer.height, boxes, groups: groupBoxes, routes, warnings: [] };
}

// ---------------------------------------------------------------------------
// grid

function layoutGrid(d: Diagram, groupOf: Map<string, number>, sizeOf: SizeOf): Natural {
  const hasGroups = d.groups.length > 0;
  const gapX = hasGroups ? 2 * GROUP_PAD + 12 : 20;
  const gapY = hasGroups ? GROUP_HEADER + GROUP_PAD + 8 : 18;
  const margin = 8 + (hasGroups ? GROUP_PAD : 0);
  const marginTop = 8 + (hasGroups ? GROUP_HEADER + 4 : 0);

  // Cells taken, and the table's extent.
  const taken = new Map<string, string>();
  let nCols = 0, nRows = 0;
  for (const n of d.nodes) {
    const { col, row } = n.grid!;
    const span = n.grid!.span ?? 1;
    for (let c = col; c < col + span; c++) {
      const k = `${c},${row}`;
      const other = taken.get(k);
      if (other) throw new Error(`grid cell (col ${c}, row ${row}) is taken by both ${JSON.stringify(other)} and ${JSON.stringify(n.id)}`);
      taken.set(k, n.id);
    }
    nCols = Math.max(nCols, col + span);
    nRows = Math.max(nRows, row + 1);
  }

  // Table sizing: single-span boxes set column widths, every box sets its row's height, then
  // spanning boxes (narrowest span first) widen the last of their columns only when short.
  const colW = new Array<number>(nCols).fill(0);
  const rowH = new Array<number>(nRows).fill(0);
  for (const n of d.nodes) {
    const m = sizeOf(n);
    rowH[n.grid!.row] = Math.max(rowH[n.grid!.row]!, m.h);
    if ((n.grid!.span ?? 1) === 1) colW[n.grid!.col] = Math.max(colW[n.grid!.col]!, m.w);
  }
  const spanning = d.nodes
    .filter((n) => (n.grid!.span ?? 1) > 1)
    .sort((a, b) => a.grid!.span! - b.grid!.span! || a.grid!.col - b.grid!.col || a.grid!.row - b.grid!.row);
  const spanWidth = (col: number, span: number) => colW.slice(col, col + span).reduce((a, b) => a + b, 0) + (span - 1) * gapX;
  for (const n of spanning) {
    const { col } = n.grid!;
    const span = n.grid!.span!;
    const short = sizeOf(n).w - spanWidth(col, span);
    if (short > 0) colW[col + span - 1]! += short;
  }

  const colX: number[] = [];
  const rowY: number[] = [];
  for (let c = 0, x = margin; c < nCols; c++) {
    colX.push(x);
    x += colW[c]! + gapX;
  }
  for (let r = 0, y = marginTop; r < nRows; r++) {
    rowY.push(y);
    y += rowH[r]! + gapY;
  }
  const boxes = new Map<string, Box>();
  for (const n of d.nodes) {
    const { col, row } = n.grid!;
    boxes.set(n.id, { x: colX[col]!, y: rowY[row]!, w: spanWidth(col, n.grid!.span ?? 1), h: rowH[row]! });
  }

  const groups: Box[] = d.groups.map((g) => {
    const ms = g.members.map((m) => boxes.get(m)!);
    if (!ms.length) return { x: margin, y: marginTop, w: 0, h: 0 };
    const x0 = Math.min(...ms.map((b) => b.x)) - GROUP_PAD;
    const y0 = Math.min(...ms.map((b) => b.y)) - GROUP_HEADER - 4;
    const x1 = Math.max(...ms.map((b) => b.x + b.w)) + GROUP_PAD;
    const y1 = Math.max(...ms.map((b) => b.y + b.h)) + GROUP_PAD;
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  });

  const warnings: string[] = [];
  const hit = (a: Box, b: Box) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
  d.groups.forEach((g, gi) => {
    for (const n of d.nodes) if (groupOf.get(n.id) !== gi && hit(boxes.get(n.id)!, groups[gi]!)) warnings.push(`node ${JSON.stringify(n.id)} lies inside group ${JSON.stringify(g.label)} without being a member`);
    for (let gj = gi + 1; gj < d.groups.length; gj++) if (hit(groups[gi]!, groups[gj]!)) warnings.push(`groups ${JSON.stringify(g.label)} and ${JSON.stringify(d.groups[gj]!.label)} overlap`);
  });

  const width = nCols ? colX[nCols - 1]! + colW[nCols - 1]! + margin : 2 * margin;
  const height = nRows ? rowY[nRows - 1]! + rowH[nRows - 1]! + margin : marginTop + margin;
  return { width, height, boxes, groups, routes: new Map(), warnings };
}

// ---------------------------------------------------------------------------
// Fit to the card

function fitToCard(d: Diagram, mode: "auto" | "grid", n: Natural, minScale: number): LayoutResult {
  const availW = CARD.width - 2 * CARD_MARGIN, availH = CARD.height - 2 * CARD_MARGIN;
  const fit = n.width > 0 && n.height > 0 ? Math.min(1, availW / n.width, availH / n.height) : 1;
  const overflow = fit < minScale;
  const s = overflow ? minScale : fit;
  const width = Math.max(CARD.width, n.width * s + 2 * CARD_MARGIN);
  const height = Math.max(CARD.height, n.height * s + 2 * CARD_MARGIN);
  const ox = (width - n.width * s) / 2, oy = (height - n.height * s) / 2;
  const tb = (b: Box): Box => ({ x: r(ox + b.x * s), y: r(oy + b.y * s), w: r(b.w * s), h: r(b.h * s) });
  const tp = ([x, y]: [number, number]): [number, number] => [r(ox + x * s), r(oy + y * s)];

  const groupOf = new Map<string, number>();
  d.groups.forEach((g, gi) => g.members.forEach((m) => groupOf.set(m, gi)));
  const nodes: LaidOutNode[] = d.nodes.map((nd) => {
    const gi = groupOf.get(nd.id);
    return {
      id: nd.id,
      label: nd.label,
      ...(nd.sub !== undefined ? { sub: nd.sub } : {}),
      ...(nd.step !== undefined ? { step: nd.step } : {}),
      ...(nd.at ? { at: nd.at } : {}),
      ...(nd.paths ? { paths: nd.paths } : {}),
      ...(gi !== undefined ? { group: gi } : {}),
      ...tb(n.boxes.get(nd.id)!),
    };
  });
  const groups: LaidOutGroup[] = d.groups.map((g, gi) => {
    const b = n.groups[gi]!;
    return { label: g.label, members: g.members, ...tb(b), label_box: tb({ x: b.x + GROUP_PAD, y: b.y + 6, w: g.label.length * SUB_CHAR, h: 12 }) };
  });
  const edges: LaidOutEdge[] = d.edges.map(([from, to, label], i) => {
    const rt = n.routes.get(i) ?? straight(n.boxes.get(from)!, n.boxes.get(to)!, label);
    return {
      from,
      to,
      ...(label ? { label } : {}),
      points: rt.points.map(tp),
      ...(label && rt.label_box ? { label_box: tb(rt.label_box) } : {}),
    };
  });
  return {
    ...(d.title !== undefined ? { title: d.title } : {}),
    mode,
    width: r(width),
    height: r(height),
    scale: Math.round(s * 1000) / 1000,
    minScale,
    overflow,
    natural: { width: r(n.width), height: r(n.height) },
    nodes,
    groups,
    edges,
    warnings: n.warnings,
  };
}
