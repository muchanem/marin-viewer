// Agent SDK sessions (DESIGN.md section 7, "Sessions" and "Closing").
//
// One `query()` per live session, fed by an async queue of user messages (streaming input), so a
// session stays one process across turns. Session ids are chosen here (`sessionId`), which lets
// `session.open` answer at once and lets a fork name its child up front.

import { execFile } from "node:child_process";
import { randomUUID } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import {
  query as sdkQuery,
  type CanUseTool,
  type Options,
  type Query,
  type SDKMessage,
  type SDKUserMessage,
} from "@anthropic-ai/claude-agent-sdk";
import type { AppBridge } from "./bridge.js";
import { backgroundEnv, interactiveEnv, type Config } from "./config.js";
import { log, scopeKey, type Chip, type ProposedNote, type Scope, type SidecarMessage } from "./protocol.js";
import { SERVER_NAME, createViewerServer } from "./tools.js";
import { appendNote, commitWordbase } from "./wordbase.js";

// ---------------------------------------------------------------------------
// Async queue for streaming input

export class AsyncQueue<T> implements AsyncIterable<T> {
  private items: T[] = [];
  private waiters: ((r: IteratorResult<T>) => void)[] = [];
  private ended = false;

  push(item: T): void {
    if (this.ended) throw new Error("queue is closed");
    const w = this.waiters.shift();
    if (w) w({ value: item, done: false });
    else this.items.push(item);
  }

  end(): void {
    this.ended = true;
    for (const w of this.waiters.splice(0)) w({ value: undefined as never, done: true });
  }

  get closed(): boolean {
    return this.ended;
  }

  [Symbol.asyncIterator](): AsyncIterator<T> {
    return {
      next: () => {
        const item = this.items.shift();
        if (item !== undefined) return Promise.resolve({ value: item, done: false });
        if (this.ended) return Promise.resolve({ value: undefined as never, done: true });
        return new Promise((resolve) => this.waiters.push(resolve));
      },
      return: () => {
        this.end();
        return Promise.resolve({ value: undefined as never, done: true });
      },
    };
  }
}

// ---------------------------------------------------------------------------
// state/sessions.json

export interface SessionRecord {
  scope: Scope;
  cwd: string;
  mode: "interactive" | "background";
  created: string;
  updated: string;
  total_cost_usd: number;
  parent?: string;
}

export interface SessionsFile {
  version: 1;
  by_scope: Record<string, string>;
  sessions: Record<string, SessionRecord>;
}

export class SessionStore {
  private data: SessionsFile | null = null;
  private chain: Promise<void> = Promise.resolve();

  constructor(readonly file: string) {}

  async load(): Promise<SessionsFile> {
    if (this.data) return this.data;
    try {
      const parsed = JSON.parse(await readFile(this.file, "utf8")) as SessionsFile;
      this.data = { version: 1, by_scope: parsed.by_scope ?? {}, sessions: parsed.sessions ?? {} };
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "ENOENT") log(`could not read ${this.file}, starting empty:`, (e as Error).message);
      this.data = { version: 1, by_scope: {}, sessions: {} };
    }
    return this.data;
  }

  async update(fn: (d: SessionsFile) => void): Promise<void> {
    const d = await this.load();
    fn(d);
    const snapshot = JSON.stringify(d, null, 2) + "\n";
    this.chain = this.chain.then(async () => {
      await mkdir(path.dirname(this.file), { recursive: true });
      const tmp = `${this.file}.${process.pid}.tmp`;
      await writeFile(tmp, snapshot, "utf8");
      await rename(tmp, this.file);
    });
    await this.chain;
  }
}

// ---------------------------------------------------------------------------
// Prompts

const FALLBACK_SESSION_PROMPT = `You are the Claude Code session inside the Marin viewer, a Mac app Mark uses to read the Marin repository and review its pull requests.

- Messages may start with chips: the code, files, steps, diagram boxes or review notes Mark selected when he asked. Each chip names a path, lines, a symbol and the commit it was taken at; an excerpt follows when there is one.
- The wordbase holds layered descriptions of the code. A repository path p is described at wordbase/<p>.md, a subsystem at wordbase/systems/<name>.md, a PR under wordbase/prs/<n>/. Read entries with the wordbase_entry tool.
- focus_code_path, open_location and draft_review_note change what the viewer shows; they return at once. find_symbol asks the viewer's SCIP indexes. propose_notes is only for the closing turn.
- Bugs and review findings go into draft_review_note, never into memories.
- Keep answers short and concrete, and name files and functions so Mark can jump to them.`;

const FALLBACK_MEMORIES_PROMPT = `The session is closing. Propose memories: what this session learned about the code that a later reader would want, each one or two sentences, each attached to the wordbase entry it is about and citing the commit it was true at. Never record bugs or review findings as memories; those belong in review notes. Propose nothing when nothing was learned.`;

function readPrompt(config: Config, name: string, fallback: string): string {
  const file = path.join(config.prompts, name);
  try {
    if (existsSync(file)) return readFileSync(file, "utf8");
  } catch (e) {
    log(`could not read ${file}:`, (e as Error).message);
  }
  return fallback;
}

function describeScope(scope: Scope): string {
  if ("pr" in scope) return `PR #${scope.pr} of marin-community/marin`;
  if ("system" in scope) return `the ${scope.system} subsystem`;
  return `the file ${scope.path}`;
}

// ---------------------------------------------------------------------------
// Chips

function git(cwd: string, args: string[]): Promise<string | null> {
  return new Promise((resolve) => {
    execFile("git", ["-C", cwd, ...args], { maxBuffer: 8 * 1024 * 1024 }, (err, stdout) => resolve(err ? null : String(stdout)));
  });
}

const MAX_CHIP_LINES = 120;

export async function formatChips(chips: Chip[], cwd: string | null): Promise<string> {
  if (!chips.length) return "";
  const out: string[] = ["<chips>"];
  for (const [i, c] of chips.entries()) {
    const loc = c.path ? `${c.path}${c.lines ? `:${c.lines[0]}-${c.lines[1]}` : ""}` : "";
    const parts = [c.kind, loc, c.symbol ? `symbol ${c.symbol}` : "", `@ ${c.commit.slice(0, 12)}`].filter(Boolean);
    out.push(`[${i + 1}] ${parts.join(" · ")}${c.label ? ` · ${JSON.stringify(c.label)}` : ""}`);
    if (cwd && c.path && c.lines) {
      const [a, b] = c.lines[0] <= c.lines[1] ? c.lines : [c.lines[1], c.lines[0]];
      const file = await git(cwd, ["show", `${c.commit}:${c.path}`]);
      if (file !== null) {
        const lines = file.split("\n").slice(Math.max(0, a - 1), Math.min(b, a - 1 + MAX_CHIP_LINES));
        const width = String(a + lines.length).length;
        out.push("```", ...lines.map((l, j) => `${String(a + j).padStart(width)}  ${l}`), "```");
        if (b - a + 1 > MAX_CHIP_LINES) out.push(`(excerpt cut at ${MAX_CHIP_LINES} lines)`);
      }
    }
  }
  out.push("</chips>", "");
  return out.join("\n");
}

// ---------------------------------------------------------------------------
// Permissions: interactive sessions read; they do not write.

const READ_TOOLS = ["Read", "Grep", "Glob", "LSP", "ToolSearch", "TodoWrite", "WebFetch", "WebSearch", "Agent", "Task"];
const READ_COMMANDS = new Set(["rg", "grep", "ls", "cat", "head", "tail", "wc", "find", "sed", "awk", "sort", "uniq", "cut", "tr", "file", "stat", "tree", "pwd", "echo", "jq", "git"]);
const READ_GIT = new Set(["log", "show", "diff", "blame", "grep", "ls-files", "ls-tree", "rev-parse", "status", "cat-file", "merge-base", "branch", "tag", "describe", "shortlog", "name-rev", "rev-list", "whatchanged"]);

export function isReadOnlyCommand(command: string): boolean {
  if (/[;`]|&&|\|\||\$\(|>|<\(|\bsed\s+-i|\bfind\b.*\s-(exec|delete|ok)/.test(command)) return false;
  return command.split("|").every((seg) => {
    const words = seg.trim().split(/\s+/);
    const cmd = words[0] ?? "";
    if (!READ_COMMANDS.has(cmd)) return false;
    if (cmd !== "git") return true;
    let i = 1;
    while (i < words.length && words[i]!.startsWith("-")) i += words[i] === "-C" || words[i] === "-c" ? 2 : 1;
    return READ_GIT.has(words[i] ?? "");
  });
}

export const readOnlyPolicy: CanUseTool = async (toolName, input) => {
  if (toolName === "Bash") {
    const command = typeof input.command === "string" ? input.command : "";
    if (isReadOnlyCommand(command)) return { behavior: "allow", updatedInput: input };
    return { behavior: "deny", message: "Viewer sessions are read-only: only read commands (git log/show/diff/blame, rg, ls, cat, ...) without redirection or chaining may run." };
  }
  if (READ_TOOLS.includes(toolName) || toolName.startsWith(`mcp__${SERVER_NAME}__`)) return { behavior: "allow", updatedInput: input };
  return { behavior: "deny", message: `Viewer sessions are read-only; ${toolName} is not available. Put findings in draft_review_note.` };
};

// ---------------------------------------------------------------------------
// Sessions

export interface OpenRequest {
  scope: Scope;
  resume?: string | undefined;
  fork?: boolean | undefined;
  fresh?: boolean | undefined;
  cwd?: string | undefined;
  mode?: "interactive" | "background";
  /** Merged over the defaults; background runs (the poller) set model, permissions, etc. */
  options?: Partial<Options>;
}

interface Live {
  id: string;
  scope: Scope;
  cwd: string;
  mode: "interactive" | "background";
  input: AsyncQueue<SDKUserMessage>;
  q: Query;
  busy: boolean;
  baselineCost: number;
  streamedMessages: Set<string>;
  currentMessage: string | null;
  proposals: ProposedNote[];
  closing: { uuid: string; resolve: () => void } | null;
  done: Promise<void>;
}

export interface SessionManagerDeps {
  config: Config;
  send: (m: SidecarMessage) => void;
  bridge: AppBridge;
  store?: SessionStore;
  queryFn?: typeof sdkQuery;
}

export class SessionManager {
  private readonly live = new Map<string, Live>();
  readonly store: SessionStore;
  private readonly queryFn: typeof sdkQuery;

  constructor(private readonly deps: SessionManagerDeps) {
    this.store = deps.store ?? new SessionStore(path.join(deps.config.state, "sessions.json"));
    this.queryFn = deps.queryFn ?? sdkQuery;
  }

  isLive(id: string): boolean {
    return this.live.has(id);
  }

  async open(req: OpenRequest): Promise<{ session: string; resumed: string | null; forked: boolean }> {
    const data = await this.store.load();
    const key = scopeKey(req.scope);
    const resumeId = req.resume ?? (req.fresh ? undefined : data.by_scope[key]);
    if (resumeId && this.live.has(resumeId) && !req.fork) return { session: resumeId, resumed: resumeId, forked: false };
    const fork = Boolean(req.fork && resumeId);
    const id = resumeId && !fork ? resumeId : randomUUID();
    const prior = resumeId ? data.sessions[resumeId] : undefined;
    const cwd = path.resolve(req.cwd ?? prior?.cwd ?? this.deps.config.marin);
    if (!existsSync(cwd)) throw new Error(`session cwd does not exist: ${cwd}`);
    const mode = req.mode ?? "interactive";

    const live = this.start({ id, scope: req.scope, cwd, mode, resumeId, fork, baselineCost: prior?.total_cost_usd ?? 0, ...(req.options ? { options: req.options } : {}) });
    const now = new Date().toISOString();
    await this.store.update((d) => {
      d.by_scope[key] = id;
      d.sessions[id] = {
        scope: req.scope,
        cwd,
        mode,
        created: d.sessions[id]?.created ?? now,
        updated: now,
        total_cost_usd: live.baselineCost,
        ...(fork && resumeId ? { parent: resumeId } : {}),
      };
    });
    return { session: id, resumed: resumeId ?? null, forked: fork };
  }

  private start(p: { id: string; scope: Scope; cwd: string; mode: "interactive" | "background"; resumeId: string | undefined; fork: boolean; baselineCost: number; options?: Partial<Options> }): Live {
    const { config } = this.deps;
    const input = new AsyncQueue<SDKUserMessage>();
    const live = { id: p.id, scope: p.scope, cwd: p.cwd, mode: p.mode, input, busy: false, baselineCost: p.baselineCost, streamedMessages: new Set<string>(), currentMessage: null, proposals: [], closing: null } as unknown as Live;

    const server = createViewerServer({
      session: p.id,
      wordbase: config.wordbase,
      send: this.deps.send,
      bridge: this.deps.bridge,
      onProposeNotes: (notes) => live.proposals.push(...notes),
    });

    const sessionPrompt = readPrompt(config, "session.md", FALLBACK_SESSION_PROMPT);
    const append = `${sessionPrompt.trim()}\n\nThis session is about ${describeScope(p.scope)}. Its working directory is ${p.cwd}. The wordbase is at ${config.wordbase}.`;
    const options: Options = {
      cwd: p.cwd,
      additionalDirectories: existsSync(config.wordbase) ? [config.wordbase] : [],
      settingSources: ["project"],
      systemPrompt: { type: "preset", preset: "claude_code", append },
      mcpServers: { [SERVER_NAME]: server },
      // Only the viewer server: no project .mcp.json, user or plugin servers in viewer sessions.
      strictMcpConfig: true,
      canUseTool: readOnlyPolicy,
      permissionMode: "default",
      includePartialMessages: true,
      env: p.mode === "background" ? backgroundEnv(config) : interactiveEnv(),
      stderr: (data) => log(`[claude ${p.id.slice(0, 8)}]`, data.trimEnd()),
      ...(process.env.MARIN_VIEWER_MODEL ? { model: process.env.MARIN_VIEWER_MODEL } : {}),
      ...(p.resumeId ? { resume: p.resumeId } : { sessionId: p.id }),
      ...(p.fork ? { forkSession: true, sessionId: p.id } : {}),
      ...p.options,
    };

    live.q = this.queryFn({ prompt: input, options });
    live.done = this.consume(live).finally(() => {
      this.live.delete(p.id);
      live.closing?.resolve();
    });
    this.live.set(p.id, live);
    log(`session ${p.id} started (${p.mode}, ${scopeKey(p.scope)}, cwd ${p.cwd}${p.resumeId ? `, ${p.fork ? "fork of" : "resume"} ${p.resumeId}` : ""})`);
    return live;
  }

  private async consume(live: Live): Promise<void> {
    const send = this.deps.send;
    try {
      for await (const m of live.q) this.handle(live, m);
    } catch (e) {
      log(`session ${live.id} ended with an error:`, e);
      send({ type: "error", session: live.id, message: `session ended: ${(e as Error).message}` });
    }
  }

  private handle(live: Live, m: SDKMessage): void {
    const send = this.deps.send;
    switch (m.type) {
      case "system":
        if (m.subtype === "init") {
          log(`session ${live.id} init: model ${m.model}, auth ${m.apiKeySource}, claude ${m.claude_code_version}, tools ${m.tools.length}, mcp ${m.mcp_servers.map((s) => `${s.name}=${s.status}`).join(",")}`);
          if (live.mode === "interactive" && m.apiKeySource === "ANTHROPIC_API_KEY") {
            send({ type: "error", session: live.id, message: "interactive session is using an API key instead of the claude login" });
          }
        }
        return;
      case "stream_event": {
        if (m.parent_tool_use_id !== null) return;
        const ev = m.event;
        if (ev.type === "message_start") live.currentMessage = ev.message.id;
        else if (ev.type === "content_block_delta" && ev.delta.type === "text_delta" && ev.delta.text) {
          if (live.currentMessage) live.streamedMessages.add(live.currentMessage);
          if (!live.closing) send({ type: "stream.delta", session: live.id, text: ev.delta.text });
        }
        return;
      }
      case "assistant": {
        // Fallback when partial messages did not arrive for this message.
        if (m.parent_tool_use_id !== null || live.closing) return;
        if (live.streamedMessages.has(m.message.id)) return;
        const t = m.message.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
        if (t) send({ type: "stream.delta", session: live.id, text: t });
        return;
      }
      case "result": {
        live.busy = false;
        live.streamedMessages.clear();
        const total = m.total_cost_usd ?? 0;
        const cost = Math.max(0, total - live.baselineCost);
        live.baselineCost = total;
        send({
          type: "turn.result",
          session: live.id,
          cost_usd: cost,
          total_cost_usd: total,
          usage: { ...(m.usage as unknown as Record<string, unknown>) },
          is_error: m.is_error,
          subtype: m.subtype,
          ...(m.subtype === "success" ? { text: m.result } : {}),
        });
        void this.store.update((d) => {
          const r = d.sessions[live.id];
          if (r) {
            r.total_cost_usd = total;
            r.updated = new Date().toISOString();
          }
        }).catch((e) => log("could not save sessions.json:", e));
        const c = live.closing;
        const uuids = new Set([...(m.user_message_uuids ?? []), ...(m.user_message_uuid ? [m.user_message_uuid] : [])]);
        if (c && (uuids.size === 0 || uuids.has(c.uuid))) c.resolve();
        return;
      }
      default:
        return;
    }
  }

  private getLive(id: string): Live {
    const l = this.live.get(id);
    if (!l) throw new Error(`no open session ${id}; send session.open first`);
    return l;
  }

  private push(live: Live, text: string): string {
    const uuid = randomUUID();
    live.busy = true;
    live.input.push({
      type: "user",
      message: { role: "user", content: text },
      parent_tool_use_id: null,
      uuid: uuid as `${string}-${string}-${string}-${string}-${string}`,
    });
    return uuid;
  }

  async send(id: string, text: string, chips: Chip[]): Promise<void> {
    const live = this.getLive(id);
    if (live.closing) throw new Error(`session ${id} is closing`);
    const prefix = await formatChips(chips, live.cwd);
    this.push(live, `${prefix}${text}`);
  }

  async interrupt(id: string): Promise<void> {
    const live = this.getLive(id);
    await live.q.interrupt();
  }

  /** Run the memories turn (unless `proposeNotes` is false), then end the session. */
  async close(id: string, proposeNotes = true): Promise<ProposedNote[]> {
    const live = this.getLive(id);
    if (live.closing) throw new Error(`session ${id} is already closing`);
    let notes: ProposedNote[] = [];
    if (proposeNotes) {
      if (live.busy) await live.q.interrupt().catch((e) => log(`interrupt before close failed:`, e));
      const prompt = readPrompt(this.deps.config, "memories.md", FALLBACK_MEMORIES_PROMPT);
      live.proposals = [];
      const finished = new Promise<void>((resolve) => {
        live.closing = { uuid: "", resolve };
      });
      live.closing!.uuid = this.push(live, `${prompt.trim()}\n\nCall the propose_notes tool once with your notes (an empty list if there are none), then stop.`);
      await finished;
      notes = live.proposals;
      this.deps.send({ type: "notes.proposed", session: id, notes });
    }
    live.input.end();
    await Promise.race([live.done, new Promise((r) => setTimeout(r, 10_000))]);
    if (this.live.has(id)) {
      live.q.close();
      this.live.delete(id);
    }
    return notes;
  }

  /** Append kept notes to their entries and commit the wordbase. */
  async keepNotes(id: string, notes: ProposedNote[]): Promise<{ files: string[]; commit: string | null }> {
    if (!notes.length) return { files: [], commit: null };
    const { wordbase } = this.deps.config;
    const record = (await this.store.load()).sessions[id];
    const date = new Date().toISOString().slice(0, 10);
    const files = new Set<string>();
    for (const n of notes) files.add(await appendNote(wordbase, n.target, { date, commit: n.commit, session: id, text: n.text }));
    const scope = record ? scopeKey(record.scope) : "unknown scope";
    const commit = await commitWordbase(wordbase, `notes: session ${id} (${scope})`, [...files]);
    return { files: [...files].map((f) => path.relative(wordbase, f)), commit };
  }

  async shutdown(): Promise<void> {
    for (const l of this.live.values()) {
      l.input.end();
      l.q.close();
    }
    this.live.clear();
  }
}
