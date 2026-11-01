// SessionManager against a fake `query()`: no model calls, no network.

import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import type { Options, Query, SDKMessage, SDKUserMessage } from "@anthropic-ai/claude-agent-sdk";
import { afterEach, describe, expect, it } from "vitest";
import { AppBridge } from "./bridge.js";
import { loadConfig } from "./config.js";
import type { SidecarMessage } from "./protocol.js";
import { SessionManager, formatChips, isReadOnlyCommand, readOnlyPolicy } from "./sessions.js";

interface FakeRun {
  options: Options;
  prompts: SDKUserMessage[];
  interrupted: number;
}

/** A fake query: answers each user message with two text deltas and a result. */
function fakeQuery(runs: FakeRun[], onPrompt?: (run: FakeRun, m: SDKUserMessage) => void) {
  return ((p: { prompt: AsyncIterable<SDKUserMessage>; options: Options }) => {
    const run: FakeRun = { options: p.options, prompts: [], interrupted: 0 };
    runs.push(run);
    const sid = p.options.sessionId ?? p.options.resume ?? "unknown";
    let total = 0;
    async function* gen(): AsyncGenerator<SDKMessage, void> {
      yield { type: "system", subtype: "init", model: "fake", apiKeySource: "oauth", claude_code_version: "x", tools: [], mcp_servers: [{ name: "viewer", status: "connected" }] } as unknown as SDKMessage;
      let n = 0;
      for await (const m of p.prompt) {
        run.prompts.push(m);
        onPrompt?.(run, m);
        n++;
        const mid = `msg_${n}`;
        yield { type: "stream_event", parent_tool_use_id: null, session_id: sid, event: { type: "message_start", message: { id: mid } } } as unknown as SDKMessage;
        yield { type: "stream_event", parent_tool_use_id: null, session_id: sid, event: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Task" } } } as unknown as SDKMessage;
        yield { type: "stream_event", parent_tool_use_id: "tool_1", session_id: sid, event: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "(subagent)" } } } as unknown as SDKMessage;
        yield { type: "stream_event", parent_tool_use_id: null, session_id: sid, event: { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Spec." } } } as unknown as SDKMessage;
        yield { type: "assistant", parent_tool_use_id: null, session_id: sid, message: { id: mid, content: [{ type: "text", text: "TaskSpec." }] } } as unknown as SDKMessage;
        total += 0.25;
        yield { type: "result", subtype: "success", is_error: false, result: "TaskSpec.", total_cost_usd: total, usage: { input_tokens: 10, output_tokens: 2 }, user_message_uuids: [m.uuid], session_id: sid } as unknown as SDKMessage;
      }
    }
    const it = gen() as unknown as Query;
    (it as unknown as { interrupt: () => Promise<undefined> }).interrupt = async () => {
      run.interrupted++;
      return undefined;
    };
    (it as unknown as { close: () => void }).close = () => undefined;
    return it;
  }) as unknown as typeof import("@anthropic-ai/claude-agent-sdk").query;
}

const dirs: string[] = [];
afterEach(() => {
  for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
});

function setup(onPrompt?: (run: FakeRun, m: SDKUserMessage) => void) {
  const root = mkdtempSync(path.join(tmpdir(), "sessions-test-"));
  dirs.push(root);
  const config = loadConfig({ MARIN_VIEWER_ROOT: root, MARIN_VIEWER_MARIN: root });
  const sent: SidecarMessage[] = [];
  const send = (m: SidecarMessage) => sent.push(m);
  const runs: FakeRun[] = [];
  const mgr = new SessionManager({ config, send, bridge: new AppBridge(send), queryFn: fakeQuery(runs, onPrompt) });
  return { root, config, sent, runs, mgr };
}

const until = async (cond: () => boolean) => {
  for (let i = 0; i < 200 && !cond(); i++) await new Promise((r) => setTimeout(r, 5));
  if (!cond()) throw new Error("condition not reached");
};

describe("SessionManager", () => {
  it("opens with a chosen id, streams deltas, reports per-turn cost, and persists the id", async () => {
    const prev = process.env.ANTHROPIC_API_KEY;
    process.env.ANTHROPIC_API_KEY = "sk-test-should-not-leak";
    try {
      const { sent, runs, mgr, config } = setup();
      const { session } = await mgr.open({ scope: { pr: 10640 } });
      expect(session).toMatch(/^[0-9a-f-]{36}$/);
      const o = runs[0]!.options;
      expect(o.sessionId).toBe(session);
      expect(o.resume).toBeUndefined();
      expect(o.env?.ANTHROPIC_API_KEY).toBeUndefined();
      expect(o.env?.PATH).toBe(process.env.PATH);
      expect(o.settingSources).toEqual(["project"]);
      expect(o.includePartialMessages).toBe(true);
      expect(o.systemPrompt).toMatchObject({ type: "preset", preset: "claude_code" });
      expect(Object.keys(o.mcpServers ?? {})).toEqual(["viewer"]);
      expect(o.strictMcpConfig).toBe(true);
      expect(o.env?.ENABLE_CLAUDEAI_MCP_SERVERS).toBe("false"); // no claude.ai connectors
      expect(o.env?.CLAUDE_API_KEY).toBeUndefined();
      expect(o.allowedTools).toBeUndefined();

      await mgr.send(session, "Which file defines TaskSpec?", []);
      await until(() => sent.some((m) => m.type === "turn.result"));
      await mgr.send(session, "And Runtime?", []);
      await until(() => sent.filter((m) => m.type === "turn.result").length === 2);

      expect(sent.filter((m) => m.type === "stream.delta").map((m) => (m as { text: string }).text)).toEqual(["Task", "Spec.", "Task", "Spec."]);
      const results = sent.filter((m) => m.type === "turn.result") as Extract<SidecarMessage, { type: "turn.result" }>[];
      expect(results.map((r) => [r.cost_usd, r.total_cost_usd])).toEqual([[0.25, 0.25], [0.25, 0.5]]);
      expect(results[0]!.usage).toEqual({ input_tokens: 10, output_tokens: 2 });

      await until(() => {
        try {
          return JSON.parse(readFileSync(path.join(config.state, "sessions.json"), "utf8")).sessions[session].total_cost_usd === 0.5;
        } catch {
          return false;
        }
      });
      const state = JSON.parse(readFileSync(path.join(config.state, "sessions.json"), "utf8"));
      expect(state.by_scope["pr:10640"]).toBe(session);
      expect(state.sessions[session]).toMatchObject({ scope: { pr: 10640 }, mode: "interactive" });

      await mgr.interrupt(session);
      expect(runs[0]!.interrupted).toBe(1);
      await mgr.shutdown();
    } finally {
      if (prev === undefined) delete process.env.ANTHROPIC_API_KEY;
      else process.env.ANTHROPIC_API_KEY = prev;
    }
  });

  it("resumes the scope's stored session and forks with a new id", async () => {
    const { runs, mgr } = setup();
    const first = await mgr.open({ scope: { system: "shellbox" } });
    await mgr.shutdown();
    const again = await mgr.open({ scope: { system: "shellbox" } });
    expect(again).toEqual({ session: first.session, resumed: first.session, forked: false });
    expect(runs[1]!.options.resume).toBe(first.session);
    expect(runs[1]!.options.sessionId).toBeUndefined();
    const fork = await mgr.open({ scope: { system: "shellbox" }, fork: true });
    expect(fork.forked).toBe(true);
    expect(fork.session).not.toBe(first.session);
    expect(runs[2]!.options).toMatchObject({ resume: first.session, forkSession: true, sessionId: fork.session });
    const fresh = await mgr.open({ scope: { system: "shellbox" }, fresh: true });
    expect(runs[3]!.options.resume).toBeUndefined();
    expect(fresh.session).not.toBe(first.session);
    await mgr.shutdown();
  });

  it("closes with the memories turn, emits notes.proposed, then keeps notes into the wordbase", async () => {
    const { sent, mgr, runs, config } = setup((_run, m) => {
      const text = typeof m.message.content === "string" ? m.message.content : "";
      if (text.includes("propose_notes")) {
        // What the propose_notes tool handler does when the model calls it.
        (mgr as unknown as { live: Map<string, { proposals: unknown[] }> }).live.get(sid)!.proposals.push({ target: "lib/shellbox/src/shellbox/task.py#TaskSpec", text: "TaskSpec is the declarative spec.", commit: "01a8bb8f0bea" });
      }
    });
    const { session: sid } = await mgr.open({ scope: { pr: 10640 } });
    const notes = await mgr.close(sid);
    expect(runs[0]!.prompts).toHaveLength(1);
    expect(notes).toHaveLength(1);
    expect(sent.find((m) => m.type === "notes.proposed")).toEqual({ type: "notes.proposed", session: sid, notes });
    expect(sent.some((m) => m.type === "stream.delta")).toBe(false); // the closing turn is not streamed
    expect(mgr.isLive(sid)).toBe(false);

    const kept = await mgr.keepNotes(sid, notes);
    expect(kept.files).toEqual(["lib/shellbox/src/shellbox/task.py.md"]);
    expect(kept.commit).toMatch(/^[0-9a-f]{40}$/);
    const entry = readFileSync(path.join(config.wordbase, "lib/shellbox/src/shellbox/task.py.md"), "utf8");
    expect(entry).toContain(`· 01a8bb8 · session ${sid.slice(0, 8)}… · \`TaskSpec\`: TaskSpec is the declarative spec.`);
  });

  it("refuses to send to a session that is not open", async () => {
    const { mgr } = setup();
    await expect(mgr.send("nope", "x", [])).rejects.toThrow(/no open session nope/);
  });
});

describe("chips and permissions", () => {
  it("formats chips without a checkout", async () => {
    const t = await formatChips([{ kind: "selection", path: "lib/a.py", lines: [3, 9], symbol: "f", commit: "01a8bb8f0bea2dde", label: "a.py:3-9" }], null);
    expect(t).toBe('<chips>\n[1] selection · lib/a.py:3-9 · symbol f · @ 01a8bb8f0bea · "a.py:3-9"\n</chips>\n');
  });

  it("allows read commands and refuses writes", async () => {
    for (const ok of ["git log --oneline -5", "git -C marin show HEAD:lib/a.py", "rg -n TaskSpec lib | head -20", "ls lib"]) expect(isReadOnlyCommand(ok), ok).toBe(true);
    for (const bad of ["rm -rf /", "git push", "git commit -m x", "echo x > f", "ls; rm f", "sed -i '' s/a/b/ f", "find . -delete", "cat $(which x)"]) expect(isReadOnlyCommand(bad), bad).toBe(false);
    const sig = { signal: new AbortController().signal, toolUseID: "t", requestId: "r" };
    expect((await readOnlyPolicy("Edit", {}, sig))?.behavior).toBe("deny");
    expect((await readOnlyPolicy("mcp__viewer__open_location", {}, sig))?.behavior).toBe("allow");
    expect((await readOnlyPolicy("Bash", { command: "git diff HEAD~1" }, sig))?.behavior).toBe("allow");
  });
});
