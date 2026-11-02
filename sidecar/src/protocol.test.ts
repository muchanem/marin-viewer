import { PassThrough } from "node:stream";
import { describe, expect, it } from "vitest";
import { AppMessage, CodePath, Diagram, Excerpt, LineWriter, SidecarMessage, parseLine, readLines, type AppMessage as AppMessageT } from "./protocol.js";

const note = {
  id: "f1",
  path: "lib/shellbox/src/shellbox/http_service.py",
  line: 133,
  side: "head",
  commit: "01a8bb8f0bea2dde1de90274ed695c25147b9f06",
  severity: "medium",
  status: "approved",
  who: "review session",
  l1: "One sentence.",
  l2: "A paragraph.",
  created: "2026-10-30T00:00:00Z",
  updated: "2026-10-30T00:00:00Z",
} as const;

const appMessages: AppMessageT[] = [
  { type: "session.open", id: 1, scope: { pr: 10640 } },
  { type: "session.open", id: "o2", scope: { system: "shellbox" }, resume: "3f2a0000-0000-4000-8000-000000000000", fork: true },
  { type: "session.open", id: "o3", scope: { path: "lib/shellbox/src/shellbox/task.py" }, cwd: "/tmp/wt", fresh: true },
  {
    type: "session.send",
    session: "s1",
    text: "Why 16?",
    chips: [{ kind: "selection", path: "lib/shellbox/src/shellbox/http_service.py", lines: [120, 133], symbol: "_pump", commit: "01a8bb8", label: "http_service.py:120-133" }],
  },
  { type: "session.send", id: "x", session: "s1", text: "plain", chips: [] },
  { type: "session.interrupt", session: "s1" },
  { type: "session.close", session: "s1", propose_notes: true },
  { type: "notes.keep", session: "s1", notes: [{ target: "lib/a.py#f", text: "learned", commit: "01a8bb8" }] },
  { type: "layout", id: 7, diagram: { nodes: [{ id: "a", label: "A" }, { id: "b", label: "B", sub: "b", step: 2, at: { path: "x.py", function: "f" } }], edges: [["a", "b"], ["b", "a", "back"]], groups: [{ label: "G", members: ["a"] }] } },
  {
    type: "layout",
    id: 10,
    diagram: { nodes: [{ id: "a", label: "A" }, { id: "b", label: "B" }], edges: [["a", "b", "loopback"]], groups: [] },
    sizes: { a: { w: 60, h: 26 } },
    edge_labels: { loopback: { w: 46, h: 13 } },
  },
  { type: "review.post", id: 8, pr: 10640, notes: [{ ...note }] },
  {
    type: "layout",
    id: 9,
    options: { mode: "grid", direction: "DOWN" },
    diagram: { layout: { mode: "grid" }, nodes: [{ id: "a", label: "A", paths: ["lib/a.py"], grid: { col: 0, row: 0, span: 2 } }], edges: [], groups: [] },
  },
  { type: "app.response", id: "req-1", result: { definitions: [] } },
  { type: "app.response", id: "req-2", error: "no index" },
];

const sidecarMessages: SidecarMessage[] = [
  { type: "stream.delta", session: "s1", text: "Hel" },
  { type: "turn.result", session: "s1", cost_usd: 0.01, total_cost_usd: 0.03, usage: { input_tokens: 3 } },
  { type: "ui.command", session: "s1", name: "focus_code_path", args: { order: [6, 1, 2] } },
  { type: "ui.command", session: "s1", name: "open_location", args: { path: "a.py", line: 3 } },
  { type: "ui.command", session: "s1", name: "draft_review_note", args: { path: "a.py", line: 3, severity: "low", l1: "x" } },
  { type: "app.request", id: "req-1", name: "find_symbol", args: { name: "TaskSpec", commit: "01a8bb8" } },
  { type: "notes.proposed", session: "s1", notes: [{ target: "system:shellbox", text: "t", commit: "01a8bb8" }] },
  { type: "error", message: "bad" },
  { type: "error", session: "s1", id: 3, message: "bad" },
  { type: "response", id: 1, result: { session: "s1" } },
];

describe("protocol round-trips", () => {
  it.each(appMessages.map((m) => [m.type, m] as const))("app message %s", (_t, m) => {
    const r = parseLine(JSON.stringify(m));
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.message).toEqual(AppMessage.parse(m));
      expect(AppMessage.parse(JSON.parse(JSON.stringify(r.message)))).toEqual(r.message);
    }
  });

  it.each(sidecarMessages.map((m) => [m.type, m] as const))("sidecar message %s", (_t, m) => {
    expect(SidecarMessage.parse(JSON.parse(JSON.stringify(m)))).toEqual(m);
  });

  it("fills defaults", () => {
    const r = parseLine(JSON.stringify({ type: "session.send", session: "s", text: "t" }));
    expect(r.ok && r.message.type === "session.send" && r.message.chips).toEqual([]);
    const c = parseLine(JSON.stringify({ type: "session.close", session: "s" }));
    expect(c.ok && c.message.type === "session.close" && c.message.propose_notes).toBe(true);
  });
});

describe("protocol rejections", () => {
  const bad: [string, string][] = [
    ["not JSON", "{type: session.open"],
    ["unknown type", JSON.stringify({ type: "session.explode", id: 1 })],
    ["missing type", JSON.stringify({ id: 1 })],
    ["missing id on session.open", JSON.stringify({ type: "session.open", scope: { pr: 1 } })],
    ["two scope keys", JSON.stringify({ type: "session.open", id: 1, scope: { pr: 1, system: "x" } })],
    ["negative PR", JSON.stringify({ type: "session.open", id: 1, scope: { pr: -4 } })],
    ["chip without commit", JSON.stringify({ type: "session.send", session: "s", text: "t", chips: [{ kind: "line", label: "x" }] })],
    ["extra field", JSON.stringify({ type: "session.interrupt", session: "s", bogus: true })],
    ["bad severity", JSON.stringify({ type: "review.post", id: 2, pr: 1, notes: [{ ...note, severity: "critical" }] })],
    ["empty notes", JSON.stringify({ type: "review.post", id: 2, pr: 1, notes: [] })],
    ["array", "[1,2,3]"],
    ["null", "null"],
  ];
  it.each(bad)("%s", (_name, line) => {
    const r = parseLine(line);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.error.type).toBe("error");
      expect(r.error.message.length).toBeGreaterThan(5);
      expect(SidecarMessage.safeParse(r.error).success).toBe(true);
    }
  });

  it("keeps the request id on a rejected request", () => {
    const r = parseLine(JSON.stringify({ type: "review.post", id: 42, pr: 1, notes: [] }));
    expect(!r.ok && r.error.id).toBe(42);
  });
});

describe("readLines", () => {
  it("routes valid lines, answers invalid ones with error, survives handler failures", async () => {
    const input = new PassThrough();
    const output = new PassThrough();
    const chunks: string[] = [];
    output.on("data", (c) => chunks.push(String(c)));
    const writer = new LineWriter(output);
    const seen: string[] = [];
    const done = readLines(input, writer, async (m) => {
      seen.push(m.type);
      if (m.type === "session.interrupt") throw new Error("no open session s9");
    });
    input.write(JSON.stringify({ type: "session.send", session: "s", text: "hi" }) + "\n");
    input.write("garbage\n\n");
    input.write(JSON.stringify({ type: "session.interrupt", id: "i1", session: "s9" }) + "\r\n");
    input.write(JSON.stringify({ type: "layout", id: 5, diagram: { nodes: [] } }));
    input.end();
    await done;
    await new Promise((r) => setImmediate(r));
    const out = chunks.join("").trim().split("\n").map((l) => JSON.parse(l));
    expect(seen).toEqual(["session.send", "session.interrupt", "layout"]);
    expect(out).toHaveLength(2);
    expect(out[0]).toMatchObject({ type: "error" });
    expect(out[0].message).toMatch(/invalid JSON/);
    expect(out[1]).toEqual({ type: "error", id: "i1", session: "s9", message: "no open session s9" });
  });

  it("refuses to emit a malformed outbound message", () => {
    const output = new PassThrough();
    let text = "";
    output.on("data", (c) => (text += String(c)));
    new LineWriter(output).send({ type: "stream.delta", session: "s", text: 5 } as unknown as SidecarMessage);
    expect(JSON.parse(text)).toEqual({ type: "error", session: "s", message: "sidecar produced a malformed stream.delta message" });
  });
});

describe("section 6 schema changes", () => {
  it("requires a grid cell on every node in grid mode", () => {
    const r = parseLine(JSON.stringify({ type: "layout", id: 1, diagram: { layout: { mode: "grid" }, nodes: [{ id: "a", label: "A", grid: { col: 0, row: 0 } }, { id: "b", label: "B" }] } }));
    expect(r.ok).toBe(false);
    expect(!r.ok && r.error.message).toMatch(/grid layout needs a grid cell on every node; missing on "b"/);
    expect(!r.ok && r.error.id).toBe(1);
    expect(Diagram.safeParse({ layout: { mode: "auto" }, nodes: [{ id: "b", label: "B" }] }).success).toBe(true);
    expect(Diagram.safeParse({ layout: { mode: "grid", direction: "LEFT" }, nodes: [] }).success).toBe(false);
    expect(Diagram.safeParse({ nodes: [{ id: "a", label: "A", grid: { col: -1, row: 0 } }] }).success).toBe(false);
  });

  it("takes excerpts with functions[], and whole-module excerpts with lines", () => {
    expect(Excerpt.parse({ path: "lib/a.py", functions: ["ServiceEndpoint", "TaskSpec"], lines: [45, 111] }).functions).toHaveLength(2);
    expect(Excerpt.safeParse({ path: "lib/a.py", functions: [], lines: [1, 40] }).success).toBe(true);
    expect(Excerpt.safeParse({ path: "lib/a.py", functions: [] }).success).toBe(false);
    expect(Excerpt.safeParse({ path: "lib/a.py", function: "TaskSpec", lines: [1, 2] }).success).toBe(false);
  });

  it("parses the fixture's code-path.json when present", async () => {
    const { readFileSync } = await import("node:fs");
    let text: string;
    try {
      text = readFileSync(new URL("../../wordbase/prs/10640/code-path.json", import.meta.url), "utf8");
    } catch {
      return;
    }
    const parsed = CodePath.safeParse(JSON.parse(text));
    expect(parsed.success ? "ok" : parsed.error.issues.slice(0, 3)).toBe("ok");
  });
});
