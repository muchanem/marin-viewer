import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { AppBridge } from "./bridge.js";
import type { SidecarMessage } from "./protocol.js";
import { buildTools, type ToolContext } from "./tools.js";

describe("app.request", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it("times out after 5 s with a readable error", async () => {
    const sent: SidecarMessage[] = [];
    const bridge = new AppBridge((m) => sent.push(m));
    const p = bridge.request("find_symbol", { name: "TaskSpec", commit: "01a8bb8" });
    const settled = p.then(
      () => "resolved",
      (e: Error) => e.message,
    );
    expect(sent).toEqual([{ type: "app.request", id: expect.stringMatching(/^req-/), name: "find_symbol", args: { name: "TaskSpec", commit: "01a8bb8" } }]);
    await vi.advanceTimersByTimeAsync(4999);
    expect(bridge.size).toBe(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(await settled).toBe("the viewer did not answer find_symbol within 5 s");
    expect(bridge.size).toBe(0);
    // A late answer is ignored, not an error.
    expect(bridge.handleResponse({ id: (sent[0] as { id: string }).id, result: 1 })).toBe(false);
  });

  it("resolves on the matching app.response and rejects on an error answer", async () => {
    const sent: { id: string }[] = [];
    const bridge = new AppBridge((m) => sent.push(m as unknown as { id: string }));
    const a = bridge.request("find_symbol", { name: "A", commit: "c" });
    const b = bridge.request("selection_context", {});
    expect(bridge.handleResponse({ id: "req-unknown", result: 0 })).toBe(false);
    expect(bridge.handleResponse({ id: sent[1]!.id, error: "no index for c" })).toBe(true);
    expect(bridge.handleResponse({ id: sent[0]!.id, result: { definition: "a.py:3" } })).toBe(true);
    await expect(a).resolves.toEqual({ definition: "a.py:3" });
    await expect(b).rejects.toThrow("the viewer could not answer selection_context: no index for c");
  });
});

describe("tools", () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  function ctx(sent: SidecarMessage[], proposed: unknown[] = []): ToolContext {
    const send = (m: SidecarMessage) => sent.push(m);
    return { session: "s1", wordbase: "/nonexistent-wordbase", send, bridge: new AppBridge(send), onProposeNotes: (n) => proposed.push(...n) };
  }
  const get = (c: ToolContext, name: string) => buildTools(c).find((t) => t.name === name)!;

  it("find_symbol reports the timeout to the model as a tool error", async () => {
    const sent: SidecarMessage[] = [];
    const c = ctx(sent);
    const r = get(c, "find_symbol").handler({ name: "TaskSpec", commit: "01a8bb8" } as never, {});
    await vi.advanceTimersByTimeAsync(5000);
    const out = await r;
    expect(out.isError).toBe(true);
    expect((out.content[0] as { text: string }).text).toMatch(/did not answer find_symbol within 5 s/);
    expect(sent[0]).toMatchObject({ type: "app.request", name: "find_symbol", args: { session: "s1", name: "TaskSpec" } });
  });

  it("UI tools emit ui.command and return at once", async () => {
    const sent: SidecarMessage[] = [];
    const c = ctx(sent);
    await get(c, "focus_code_path").handler({ order: [6, 1, 2], reason: "Start at the relay." } as never, {});
    await get(c, "open_location").handler({ path: "lib/a.py", function: "f" } as never, {});
    await get(c, "draft_review_note").handler({ path: "lib/a.py", line: 3, side: "head", severity: "low", l1: "x" } as never, {});
    expect(sent).toEqual([
      { type: "ui.command", session: "s1", name: "focus_code_path", args: { order: [6, 1, 2], reason: "Start at the relay." } },
      { type: "ui.command", session: "s1", name: "open_location", args: { path: "lib/a.py", function: "f" } },
      { type: "ui.command", session: "s1", name: "draft_review_note", args: { path: "lib/a.py", line: 3, side: "head", severity: "low", l1: "x" } },
    ]);
  });

  it("propose_notes hands notes to the session", async () => {
    const proposed: unknown[] = [];
    const c = ctx([], proposed);
    await get(c, "propose_notes").handler({ notes: [{ target: "system:shellbox", text: "t", commit: "c" }] } as never, {});
    expect(proposed).toEqual([{ target: "system:shellbox", text: "t", commit: "c" }]);
  });
});
