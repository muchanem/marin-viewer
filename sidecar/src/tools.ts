// The in-process MCP server each session gets (DESIGN.md section 7, "Tools").

import { readdir } from "node:fs/promises";
import path from "node:path";
import { createSdkMcpServer, tool, type McpSdkServerConfigWithInstance } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";
import type { AppBridge } from "./bridge.js";
import type { ProposedNote, SidecarMessage } from "./protocol.js";
import {
  fileEntryPath,
  getSymbol,
  readEntry,
  renderSymbol,
  systemEntryPath,
  writeEntry,
  type Entry,
} from "./wordbase.js";

export const SERVER_NAME = "viewer";
export const TOOL_NAMES = [
  "focus_code_path",
  "open_location",
  "draft_review_note",
  "wordbase_entry",
  "find_symbol",
  "propose_notes",
] as const;
export const qualifiedToolNames = TOOL_NAMES.map((n) => `mcp__${SERVER_NAME}__${n}`);

export interface ToolContext {
  session: string;
  wordbase: string;
  send: (m: SidecarMessage) => void;
  bridge: AppBridge;
  /** Called by propose_notes. */
  onProposeNotes: (notes: ProposedNote[]) => void;
}

type ToolResult = { content: { type: "text"; text: string }[]; isError?: boolean };
const text = (t: string, isError = false): ToolResult => ({ content: [{ type: "text", text: t }], ...(isError ? { isError } : {}) });

function uiCommand(ctx: ToolContext, name: "focus_code_path" | "open_location" | "draft_review_note", args: Record<string, unknown>): ToolResult {
  const clean = Object.fromEntries(Object.entries(args).filter(([, v]) => v !== undefined));
  ctx.send({ type: "ui.command", session: ctx.session, name, args: clean });
  return text(`Sent ${name} to the viewer.`);
}

// ---------------------------------------------------------------------------
// wordbase_entry

function rel(ctx: ToolContext, file: string): string {
  return `wordbase/${path.relative(ctx.wordbase, file)}`;
}

function summaryLine(label: string, e: Entry | null): string {
  if (!e) return `- ${label}: (no entry yet)`;
  return `- ${label}: ${e.front.l1 ?? "(no l1)"}`;
}

async function linkedFor(ctx: ToolContext, e: Entry): Promise<string[]> {
  const out: string[] = [];
  if (e.front.kind === "file" && typeof e.front.system === "string") {
    out.push(summaryLine(`system ${e.front.system}`, await readEntry(systemEntryPath(ctx.wordbase, e.front.system))));
  }
  if (e.front.kind === "system") {
    const names = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : []);
    for (const s of [...names(e.front.uses).map((n) => ["uses", n]), ...names(e.front.used_by).map((n) => ["used by", n])]) {
      out.push(summaryLine(`${s[0]} system ${s[1]}`, await readEntry(systemEntryPath(ctx.wordbase, s[1]!))));
    }
    for (const m of names(e.front.members).slice(0, 60)) {
      const isPath = /\.[A-Za-z0-9]+$/.test(m) || m.includes("/");
      const file = isPath ? fileEntryPath(ctx.wordbase, m) : systemEntryPath(ctx.wordbase, m);
      out.push(summaryLine(`member ${m}`, await readEntry(file).catch(() => null)));
    }
  }
  return out;
}

async function findSymbolAnywhere(ctx: ToolContext, symbol: string, limit = 5): Promise<string[]> {
  let files: string[];
  try {
    files = (await readdir(ctx.wordbase, { recursive: true })) as string[];
  } catch {
    return [];
  }
  const hits: string[] = [];
  for (const f of files) {
    if (!f.endsWith(".md") || f.startsWith("prs/") || f.startsWith(".git")) continue;
    const full = path.join(ctx.wordbase, f);
    const e = await readEntry(full).catch(() => null);
    const s = e && getSymbol(e, symbol);
    if (s) hits.push(renderSymbol(rel(ctx, full), s));
    if (hits.length >= limit) break;
  }
  return hits;
}

export async function wordbaseEntry(ctx: ToolContext, args: { path?: string | undefined; system?: string | undefined; symbol?: string | undefined }): Promise<ToolResult> {
  if (!args.path && !args.system && !args.symbol) return text("Give a path, a system or a symbol.", true);
  if (!args.path && !args.system && args.symbol) {
    const hits = await findSymbolAnywhere(ctx, args.symbol);
    return hits.length ? text(hits.join("\n")) : text(`No wordbase entry has a subsection for \`${args.symbol}\`.`);
  }
  let file: string;
  try {
    file = args.path ? fileEntryPath(ctx.wordbase, args.path) : systemEntryPath(ctx.wordbase, args.system!);
  } catch (e) {
    return text((e as Error).message, true);
  }
  const entry = await readEntry(file);
  if (!entry) return text(`No wordbase entry yet for ${args.path ?? `system ${args.system}`} (expected at ${rel(ctx, file)}).`);
  if (args.symbol) {
    const s = getSymbol(entry, args.symbol);
    if (!s) {
      const have = entry.symbols.map((x) => `\`${x.name}\``).join(", ") || "none";
      return text(`${rel(ctx, file)} has no subsection for \`${args.symbol}\`. Symbols described there: ${have}.`);
    }
    return text(renderSymbol(rel(ctx, file), s));
  }
  const linked = await linkedFor(ctx, entry);
  return text(`${rel(ctx, file)}\n\n${writeEntry(entry)}${linked.length ? `\nLinked entries:\n${linked.join("\n")}\n` : ""}`);
}

// ---------------------------------------------------------------------------

// A step as focus_code_path proposes it: code-path.json's shape, with everything but the id
// optional so a proposal can retitle or re-excerpt one step.
const ProposedStep = z.object({
  id: z.number().int(),
  title: z.string().optional(),
  l1: z.string().optional(),
  l2: z.string().optional(),
  node: z.string().optional(),
  excerpts: z
    .array(
      z.object({
        path: z.string(),
        functions: z.array(z.string()).describe("Consecutive declarations the excerpt spans; [] for a whole-module excerpt, which needs lines."),
        lines: z.tuple([z.number().int(), z.number().int()]).optional(),
      }),
    )
    .optional(),
});

export function buildTools(ctx: ToolContext) {
  return [
    tool(
      "focus_code_path",
      "Propose a change to the PR's code path in the viewer: select a step, reorder steps, or replace steps. The viewer shows the proposal to Mark with Apply / Undo; it does not change anything until he applies it. Returns at once.",
      {
        step: z.number().int().optional().describe("Step id to select and show."),
        order: z.array(z.number().int()).optional().describe("New order of step ids, e.g. [6,1,2,3,4,5,7,8]."),
        steps: z.array(ProposedStep).optional().describe("Replacement or added steps, in code-path.json form."),
        reason: z.string().describe("One sentence the viewer shows beside Apply / Undo."),
      },
      async (args) => uiCommand(ctx, "focus_code_path", args),
    ),
    tool(
      "open_location",
      "Scroll the viewer's main view to a file location. Give `function` to resolve by declaration name; `line` is a fallback. Returns at once.",
      {
        path: z.string().describe("Repository-relative path."),
        line: z.number().int().positive().optional(),
        function: z.string().optional(),
        commit: z.string().optional().describe("Defaults to the session's head commit."),
      },
      async (args) => uiCommand(ctx, "open_location", args),
    ),
    tool(
      "draft_review_note",
      "Add a draft review note at a line. It appears amber in the gutter and in the Review notes tab, where Mark approves, rejects or edits it. Nothing is posted to GitHub from here. Returns at once.",
      {
        path: z.string(),
        line: z.number().int().positive(),
        side: z.enum(["head", "base"]).default("head"),
        severity: z.enum(["high", "medium", "low", "design"]),
        l1: z.string().describe("The note in one sentence."),
        l2: z.string().optional().describe("A paragraph with the evidence."),
        commit: z.string().optional(),
      },
      async (args) => uiCommand(ctx, "draft_review_note", args),
    ),
    tool(
      "wordbase_entry",
      "Read a wordbase entry: the layered description of a file (by repository path) or a subsystem (by name), with short lines for its linked entries. Given a symbol as well, returns only that symbol's subsection; given only a symbol, searches every file entry for it.",
      {
        path: z.string().optional().describe("Repository-relative file path."),
        system: z.string().optional().describe("Subsystem name, e.g. shellbox."),
        symbol: z.string().optional().describe("Function or class name."),
      },
      async (args) => wordbaseEntry(ctx, args),
      { annotations: { readOnlyHint: true } },
    ),
    tool(
      "find_symbol",
      "Look up a symbol's definition and references in the viewer's SCIP indexes at a commit. Fails after 5 s if the viewer does not answer.",
      { name: z.string().min(1), commit: z.string().min(1) },
      async (args) => {
        try {
          const result = await ctx.bridge.request("find_symbol", { session: ctx.session, ...args });
          return text(typeof result === "string" ? result : JSON.stringify(result, null, 2));
        } catch (e) {
          return text(`find_symbol failed: ${(e as Error).message}. Fall back to Grep over the checkout.`, true);
        }
      },
      { annotations: { readOnlyHint: true } },
    ),
    tool(
      "propose_notes",
      "Only in the closing turn: propose the memories this session should keep. Each note says what was learned about the code (never a bug; bugs go to review notes), names its wordbase target, and cites the commit it was true at. Targets: a repository path, `path#symbol`, `system:<name>`, `pr:<n>` or `reviewer`.",
      {
        notes: z
          .array(z.object({ target: z.string().min(1), text: z.string().min(1), commit: z.string().min(1) }))
          .describe("Empty when the session learned nothing worth keeping."),
      },
      async (args) => {
        ctx.onProposeNotes(args.notes);
        return text(`Recorded ${args.notes.length} proposed note${args.notes.length === 1 ? "" : "s"}; Mark will review them.`);
      },
    ),
  ];
}

export function createViewerServer(ctx: ToolContext): McpSdkServerConfigWithInstance {
  return createSdkMcpServer({
    name: SERVER_NAME,
    version: "0.1.0",
    instructions:
      "Tools that drive the Marin viewer the user is looking at, and read its wordbase of code descriptions. UI tools return at once; their effect is shown to the user.",
    tools: buildTools(ctx),
  });
}
