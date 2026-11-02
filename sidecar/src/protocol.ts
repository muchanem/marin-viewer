// JSON-lines protocol between the Marin viewer app and the sidecar (DESIGN.md section 7).
//
// Every message has `type`; requests carry `id`. The app talks on our stdin, we answer on stdout,
// and everything diagnostic goes to stderr. A malformed line yields an `error` message and the
// reader carries on.
//
// Additions beyond the section 7 list, kept small and marked here:
// - `session.open` takes an optional `cwd` (the worktree the app created) and `fresh` (ignore the
//   scope's stored session), and returns `response {id, result: {session, resumed, forked}}`.
// - Any app message with an `id` gets a `response {id, result}` when it completes, or an
//   `error {id, message}` when it fails. `layout` and `review.post` return their results this way.
// - `app.response` may carry `error` instead of `result`.
// - `review.post` notes may carry `body`, the exact text the confirm box showed.

import { createInterface } from "node:readline";
import type { Readable, Writable } from "node:stream";
import { z } from "zod";

// ---------------------------------------------------------------------------
// Shared shapes (section 6)

export const RequestId = z.union([z.string().min(1), z.number().int()]);
export type RequestId = z.infer<typeof RequestId>;

export const Scope = z.union([
  z.object({ pr: z.number().int().positive() }).strict(),
  z.object({ system: z.string().min(1) }).strict(),
  z.object({ path: z.string().min(1) }).strict(),
]);
export type Scope = z.infer<typeof Scope>;

export function scopeKey(scope: Scope): string {
  if ("pr" in scope) return `pr:${scope.pr}`;
  if ("system" in scope) return `system:${scope.system}`;
  return `path:${scope.path}`;
}

export const LineRange = z.tuple([z.number().int().nonnegative(), z.number().int().nonnegative()]);

export const Chip = z
  .object({
    kind: z.string().min(1), // selection | symbol | line | file | step | box | note ...
    path: z.string().min(1).optional(),
    lines: LineRange.optional(),
    symbol: z.string().min(1).optional(),
    commit: z.string().min(1),
    label: z.string(),
  })
  .strict();
export type Chip = z.infer<typeof Chip>;

export const Severity = z.enum(["high", "medium", "low", "design"]);
export const NoteStatus = z.enum(["draft", "approved", "rejected", "posted", "resolved"]);

/** One line of `wordbase/prs/<n>/notes.jsonl`. */
export const ReviewNote = z
  .object({
    id: z.string().min(1),
    path: z.string().min(1),
    line: z.number().int().positive(),
    side: z.enum(["head", "base"]),
    commit: z.string().min(1),
    severity: Severity,
    status: NoteStatus,
    who: z.string().min(1),
    l1: z.string().min(1),
    l2: z.string().optional(),
    github_comment_id: z.number().int().optional(),
    created: z.string().min(1),
    updated: z.string().min(1),
  })
  .strict();
export type ReviewNote = z.infer<typeof ReviewNote>;

/** A note as handed to `review.post`: the stored note plus the exact confirmed text. */
export const PostNote = ReviewNote.extend({ body: z.string().min(1).optional() }).strict();
export type PostNote = z.infer<typeof PostNote>;

/** A memory proposed in the closing turn. `target` names the wordbase entry (see wordbase.ts). */
export const ProposedNote = z
  .object({
    target: z.string().min(1),
    text: z.string().min(1),
    commit: z.string().min(1),
  })
  .strict();
export type ProposedNote = z.infer<typeof ProposedNote>;

export const DiagramNode = z
  .object({
    id: z.string().min(1),
    label: z.string(),
    sub: z.string().optional(),
    step: z.number().int().optional(),
    at: z.object({ path: z.string().min(1), function: z.string().min(1).optional() }).strict().optional(),
    /** Files the box stands for; the app marks it touched or dimmed from the PR's changed files. */
    paths: z.array(z.string().min(1)).optional(),
    /** Subsystem maps only: the packages one box stands for, when it stands for several. */
    systems: z.array(z.string().min(1)).optional(),
    /** Grid cell, required in grid mode. */
    grid: z
      .object({ col: z.number().int().nonnegative(), row: z.number().int().nonnegative(), span: z.number().int().positive().optional() })
      .strict()
      .optional(),
  })
  .strict();
export const DiagramEdge = z.union([
  z.tuple([z.string().min(1), z.string().min(1)]),
  z.tuple([z.string().min(1), z.string().min(1), z.string()]),
]);
export const DiagramGroup = z
  .object({ label: z.string(), members: z.array(z.string().min(1)) })
  .strict();
export const LayoutDirection = z.enum(["RIGHT", "DOWN"]);
export const DiagramLayout = z
  .object({ mode: z.enum(["auto", "grid"]), direction: LayoutDirection.optional() })
  .strict();
export const Diagram = z
  .object({
    title: z.string().optional(),
    layout: DiagramLayout.optional(),
    nodes: z.array(DiagramNode),
    edges: z.array(DiagramEdge).default([]),
    groups: z.array(DiagramGroup).default([]),
  })
  .strict()
  .superRefine((d, ctx) => {
    if (d.layout?.mode !== "grid") return;
    const missing = d.nodes.filter((n) => !n.grid).map((n) => JSON.stringify(n.id));
    if (missing.length) {
      ctx.addIssue({
        code: "custom",
        path: ["nodes"],
        message: `grid layout needs a grid cell on every node; missing on ${missing.join(", ")}`,
      });
    }
  });
export type Diagram = z.infer<typeof Diagram>;
export type DiagramInput = z.input<typeof Diagram>;

/** Request-level overrides of the diagram's own `layout`. */
export const LayoutOptions = z
  .object({
    mode: z.enum(["auto", "grid"]).optional(),
    direction: LayoutDirection.optional(),
    minScale: z.number().gt(0).lte(1).optional(),
  })
  .strict();
/** Box sizes the app measured with its own font, by node id, at scale 1. */
export const NodeSizes = z.record(z.string().min(1), z.object({ w: z.number().positive(), h: z.number().positive() }).strict());
/** Edge label sizes the app measured with its own font, by label text, at scale 1. */
export const EdgeLabelSizes = z.record(z.string().min(1), z.object({ w: z.number().positive(), h: z.number().positive() }).strict());

// code-path.json (section 6)
export const Excerpt = z
  .object({
    path: z.string().min(1),
    /** Consecutive declarations; empty for a whole-module excerpt, which keeps `lines`. */
    functions: z.array(z.string().min(1)),
    lines: LineRange.optional(),
  })
  .strict()
  .refine((e) => e.functions.length > 0 || e.lines !== undefined, { message: "a whole-module excerpt (functions: []) needs lines" });
export type Excerpt = z.infer<typeof Excerpt>;

export const CodePathStep = z
  .object({
    id: z.number().int(),
    title: z.string(),
    l1: z.string(),
    l2: z.string().optional(),
    node: z.string().optional(),
    excerpts: z.array(Excerpt),
  })
  .strict();
export type CodePathStep = z.infer<typeof CodePathStep>;
export const CodePath = z.array(CodePathStep);

// ---------------------------------------------------------------------------
// From the app

const optId = { id: RequestId.optional() };

export const SessionOpen = z
  .object({
    type: z.literal("session.open"),
    id: RequestId,
    scope: Scope,
    resume: z.string().min(1).optional(),
    fork: z.boolean().optional(),
    /** Start a new session even when the scope has a stored one. */
    fresh: z.boolean().optional(),
    cwd: z.string().min(1).optional(),
  })
  .strict();

export const SessionSend = z
  .object({
    type: z.literal("session.send"),
    ...optId,
    session: z.string().min(1),
    text: z.string(),
    chips: z.array(Chip).default([]),
  })
  .strict();

export const SessionInterrupt = z
  .object({ type: z.literal("session.interrupt"), ...optId, session: z.string().min(1) })
  .strict();

export const SessionClose = z
  .object({
    type: z.literal("session.close"),
    ...optId,
    session: z.string().min(1),
    propose_notes: z.boolean().default(true),
  })
  .strict();

export const NotesKeep = z
  .object({
    type: z.literal("notes.keep"),
    ...optId,
    session: z.string().min(1),
    notes: z.array(ProposedNote),
  })
  .strict();

export const LayoutRequest = z
  .object({
    type: z.literal("layout"),
    id: RequestId,
    diagram: Diagram,
    sizes: NodeSizes.optional(),
    edge_labels: EdgeLabelSizes.optional(),
    options: LayoutOptions.optional(),
  })
  .strict();

export const ReviewPost = z
  .object({
    type: z.literal("review.post"),
    id: RequestId,
    pr: z.number().int().positive(),
    notes: z.array(PostNote).min(1),
    repo: z.string().regex(/^[\w.-]+\/[\w.-]+$/).optional(),
    body: z.string().optional(),
  })
  .strict();

export const AppResponse = z
  .object({
    type: z.literal("app.response"),
    id: RequestId,
    result: z.unknown().optional(),
    error: z.string().optional(),
  })
  .strict();

export const AppMessage = z.discriminatedUnion("type", [
  SessionOpen,
  SessionSend,
  SessionInterrupt,
  SessionClose,
  NotesKeep,
  LayoutRequest,
  ReviewPost,
  AppResponse,
]);
export type AppMessage = z.infer<typeof AppMessage>;
export type AppMessageOf<T extends AppMessage["type"]> = Extract<AppMessage, { type: T }>;

// ---------------------------------------------------------------------------
// From the sidecar

export const StreamDelta = z
  .object({ type: z.literal("stream.delta"), session: z.string(), text: z.string() })
  .strict();

export const TurnResult = z
  .object({
    type: z.literal("turn.result"),
    session: z.string(),
    /** Cost of this turn alone (the SDK reports a running total; we difference it). */
    cost_usd: z.number(),
    /** The SDK's running total for the session. */
    total_cost_usd: z.number().optional(),
    usage: z.record(z.string(), z.unknown()),
    is_error: z.boolean().optional(),
    subtype: z.string().optional(),
    text: z.string().optional(),
  })
  .strict();

export const UiCommandName = z.enum(["focus_code_path", "open_location", "draft_review_note"]);
export const UiCommand = z
  .object({
    type: z.literal("ui.command"),
    session: z.string(),
    name: UiCommandName,
    args: z.record(z.string(), z.unknown()),
  })
  .strict();

export const AppRequestName = z.enum(["find_symbol", "selection_context"]);
export const AppRequest = z
  .object({
    type: z.literal("app.request"),
    id: RequestId,
    name: AppRequestName,
    args: z.record(z.string(), z.unknown()),
  })
  .strict();

export const NotesProposed = z
  .object({ type: z.literal("notes.proposed"), session: z.string(), notes: z.array(ProposedNote) })
  .strict();

export const ErrorMessage = z
  .object({
    type: z.literal("error"),
    session: z.string().optional(),
    id: RequestId.optional(),
    message: z.string(),
  })
  .strict();

export const Response = z
  .object({ type: z.literal("response"), id: RequestId, result: z.unknown() })
  .strict();

export const SidecarMessage = z.discriminatedUnion("type", [
  StreamDelta,
  TurnResult,
  UiCommand,
  AppRequest,
  NotesProposed,
  ErrorMessage,
  Response,
]);
export type SidecarMessage = z.infer<typeof SidecarMessage>;

// ---------------------------------------------------------------------------
// JSON-lines I/O

export function log(...parts: unknown[]): void {
  const text = parts.map((p) => (typeof p === "string" ? p : safeStringify(p))).join(" ");
  process.stderr.write(`[sidecar ${new Date().toISOString()}] ${text}\n`);
}

function safeStringify(v: unknown): string {
  if (v instanceof Error) return v.stack ?? v.message;
  try {
    return JSON.stringify(v);
  } catch {
    return String(v);
  }
}

export type ParseResult =
  | { ok: true; message: AppMessage }
  | { ok: false; error: { type: "error"; id?: RequestId; message: string } };

/** Parse one inbound line. Never throws. */
export function parseLine(line: string): ParseResult {
  let raw: unknown;
  try {
    raw = JSON.parse(line);
  } catch (e) {
    return { ok: false, error: { type: "error", message: `invalid JSON: ${(e as Error).message}` } };
  }
  const parsed = AppMessage.safeParse(raw);
  if (parsed.success) return { ok: true, message: parsed.data };
  const id = raw && typeof raw === "object" ? RequestId.safeParse((raw as { id?: unknown }).id) : undefined;
  const t = raw && typeof raw === "object" ? (raw as { type?: unknown }).type : undefined;
  const issues = parsed.error.issues
    .slice(0, 5)
    .map((i) => `${i.path.join(".") || "(root)"}: ${i.message}`)
    .join("; ");
  return {
    ok: false,
    error: {
      type: "error",
      ...(id?.success ? { id: id.data } : {}),
      message: `invalid message${typeof t === "string" ? ` of type ${JSON.stringify(t)}` : ""}: ${issues}`,
    },
  };
}

/** Serialise and write one outbound message. Validates in development so drift fails loudly. */
export class LineWriter {
  constructor(private readonly out: Writable = process.stdout) {}

  send(message: SidecarMessage): void {
    const checked = SidecarMessage.safeParse(message);
    if (!checked.success) {
      log("refusing to send a malformed message:", checked.error.issues, message.type);
      const fallback: SidecarMessage = {
        type: "error",
        message: `sidecar produced a malformed ${message.type} message`,
        ...("session" in message && typeof message.session === "string" ? { session: message.session } : {}),
      };
      this.out.write(JSON.stringify(fallback) + "\n");
      return;
    }
    this.out.write(JSON.stringify(checked.data) + "\n");
  }
}

/**
 * Read JSON lines from `input`, calling `onMessage` for each valid message and writing an `error`
 * for each invalid one. Handler exceptions and rejections become `error` messages too.
 * Resolves when the input ends.
 */
export function readLines(
  input: Readable,
  writer: LineWriter,
  onMessage: (message: AppMessage) => void | Promise<void>,
): Promise<void> {
  const rl = createInterface({ input, crlfDelay: Infinity });
  rl.on("line", (line) => {
    if (line.trim() === "") return;
    const r = parseLine(line);
    if (!r.ok) {
      log("rejected line:", r.error.message);
      writer.send(r.error);
      return;
    }
    const message = r.message;
    const fail = (e: unknown) => {
      log(`handler for ${message.type} failed:`, e);
      writer.send({
        type: "error",
        message: e instanceof Error ? e.message : String(e),
        ...("id" in message && message.id !== undefined ? { id: message.id } : {}),
        ...("session" in message ? { session: message.session } : {}),
      });
    };
    try {
      const p = onMessage(message);
      if (p && typeof (p as Promise<void>).catch === "function") (p as Promise<void>).catch(fail);
    } catch (e) {
      fail(e);
    }
  });
  return new Promise((resolve) => rl.on("close", () => resolve()));
}
