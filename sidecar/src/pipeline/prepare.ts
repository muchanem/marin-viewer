// Preparation runs (DESIGN.md section 8, "Prepare PRs"). A run fetches the PR head with git, checks
// it out in its own worktree under `state/worktrees/`, opens the PR's background session on Opus 5.5
// and sends `prompts/prepare-pr.md`. The poller then validates the section 6 outputs and lints them,
// sends failures back once, runs a cold-reader pass over the PR description and code path, and
// sends any gaps back for a rewrite. A new head on a prepared PR resumes the session with an update
// turn.

import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { query as sdkQuery, type CanUseTool, type Options } from "@anthropic-ai/claude-agent-sdk";
import { AppBridge } from "../bridge.js";
import { backgroundEnv, type Config } from "../config.js";
import type { SidecarMessage } from "../protocol.js";
import { isReadOnlyCommand, readOnlyPolicy, SessionManager } from "../sessions.js";
import { SERVER_NAME } from "../tools.js";
import { commitWordbase, parseEntry, prDir, writeEntry } from "../wordbase.js";
import { Gh, gitIn, isCreditError } from "./exec.js";
import { inputBlock, renderPrompt } from "./prompts.js";
import type { MarinRepo } from "./repo.js";
import type { Ledger, PrRecord } from "./state.js";
import { markContext, type MarkContext } from "./transcripts.js";
import { checkerArgs, runChecker, validatePrOutputs, type Validation } from "./validate.js";

export const REPO = "marin-community/marin";
export const PREP_MODEL = "claude-opus-5-5";
export const COLD_READER_MODEL = "claude-sonnet-5-5";

// ---------------------------------------------------------------------------
// Permissions

/**
 * The preparation run reads anything, writes only inside `wordbase/prs/<n>/`, and runs read-only
 * Bash plus the check command. It makes no `gh` calls (the poller attaches the PR data) and starts no
 * subagents.
 */
export function prepPolicy(p: { outDir: string; checkCommand: string; log?: (line: string) => void }): CanUseTool {
  const out = path.resolve(p.outDir) + path.sep;
  const deny = (message: string) => {
    p.log?.(`  deny: ${message.slice(0, 160)}`);
    return { behavior: "deny" as const, message };
  };
  return async (toolName, input, opts) => {
    if (toolName === "Write" || toolName === "Edit" || toolName === "MultiEdit") {
      const file = typeof input.file_path === "string" ? path.resolve(input.file_path) : "";
      if (file.startsWith(out)) {
        p.log?.(`  ${toolName} ${file}`);
        return { behavior: "allow", updatedInput: input };
      }
      return deny(`This run writes only inside ${out}; ${file || "that path"} is outside it.`);
    }
    if (toolName === "Bash") {
      const command = typeof input.command === "string" ? input.command.trim() : "";
      if (command === p.checkCommand || (command.startsWith(p.checkCommand) && !/[;&|`$<>]/.test(command.slice(p.checkCommand.length)))) {
        p.log?.(`  bash (check) ${command.slice(0, 120)}`);
        return { behavior: "allow", updatedInput: input };
      }
      if (/^\s*gh\b/.test(command) || /\|\s*gh\b/.test(command)) return deny("This run makes no gh calls; the PR metadata and review comments are attached to the prompt.");
      if (isReadOnlyCommand(command)) {
        p.log?.(`  bash ${command.slice(0, 120)}`);
        return { behavior: "allow", updatedInput: input };
      }
      return deny("Bash runs read-only commands only (git log/show/diff/grep, rg, ls, cat, sed -n), one plain command without cd, &&, ;, $(...) or redirection, plus the check command.");
    }
    if (["Agent", "Task", "WebFetch", "WebSearch", "NotebookEdit"].includes(toolName)) return deny(`${toolName} is not available in preparation runs.`);
    if (toolName.startsWith(`mcp__${SERVER_NAME}__`) && !toolName.endsWith("__wordbase_entry")) return deny(`${toolName} needs the viewer, which is not attached to background runs.`);
    return readOnlyPolicy(toolName, input, opts);
  };
}

// ---------------------------------------------------------------------------
// Background sessions: SessionManager with a sink that resolves one promise per turn.

interface TurnOutcome {
  cost_usd: number;
  total_cost_usd: number;
  is_error: boolean;
  subtype: string;
  text: string;
}

export class BackgroundSessions {
  readonly manager: SessionManager;
  private readonly waiting = new Map<string, { resolve: (t: TurnOutcome) => void; reject: (e: Error) => void }>();
  private readonly bridge: AppBridge;

  constructor(config: Config, queryFn?: typeof sdkQuery) {
    this.bridge = new AppBridge((m) => this.onMessage(m), 1000);
    this.manager = new SessionManager({ config, send: (m) => this.onMessage(m), bridge: this.bridge, ...(queryFn ? { queryFn } : {}) });
  }

  private onMessage(m: SidecarMessage): void {
    if (m.type === "app.request") {
      // No viewer is attached to background runs.
      queueMicrotask(() => this.bridge.handleResponse({ id: m.id, error: "no viewer is attached to background runs" }));
    } else if (m.type === "turn.result") {
      const w = this.waiting.get(m.session);
      this.waiting.delete(m.session);
      w?.resolve({ cost_usd: m.cost_usd, total_cost_usd: m.total_cost_usd ?? m.cost_usd, is_error: Boolean(m.is_error), subtype: m.subtype ?? "", text: m.text ?? "" });
    } else if (m.type === "error" && m.session) {
      const w = this.waiting.get(m.session);
      this.waiting.delete(m.session);
      w?.reject(new Error(m.message));
    }
  }

  async turn(session: string, text: string): Promise<TurnOutcome> {
    const done = new Promise<TurnOutcome>((resolve, reject) => this.waiting.set(session, { resolve, reject }));
    await this.manager.send(session, text, []);
    return done;
  }
}

// ---------------------------------------------------------------------------
// PR data

export interface SearchedPr {
  number: number;
  title: string;
  author: string;
  reasons: string[];
}

/** Open PRs requesting Mark's review, and his own open PRs. A gh failure throws. */
export async function searchPrs(gh: Gh, user = "muchanem"): Promise<SearchedPr[]> {
  type Hit = { number: number; title: string; author: { login: string } };
  const fields = "number,title,author";
  const requested = await gh.json<Hit[]>(["search", "prs", "--repo", REPO, `--review-requested=${user}`, "--state=open", "--limit", "50", "--json", fields]);
  const own = await gh.json<Hit[]>(["search", "prs", "--repo", REPO, `--author=${user}`, "--state=open", "--limit", "50", "--json", fields]);
  if (!Array.isArray(requested) || !Array.isArray(own)) throw new Error("gh search prs returned something other than a list");
  const byNumber = new Map<number, SearchedPr>();
  for (const [list, reason] of [[requested, "review requested"], [own, "own PR"]] as const) {
    for (const h of list) {
      const e = byNumber.get(h.number) ?? { number: h.number, title: h.title, author: h.author?.login ?? "unknown", reasons: [] };
      e.reasons.push(reason);
      byNumber.set(h.number, e);
    }
  }
  return [...byNumber.values()].sort((a, b) => a.number - b.number);
}

/** Fetch every PR head into `refs/viewer/pr/<n>` with one `git fetch`; return the head SHAs. */
export async function fetchHeads(repo: MarinRepo, numbers: number[]): Promise<Map<number, string>> {
  const heads = new Map<number, string>();
  if (!numbers.length) return heads;
  await repo.git(["fetch", "--quiet", "--no-tags", "origin", ...numbers.map((n) => `+refs/pull/${n}/head:refs/viewer/pr/${n}`)], { timeoutMs: 300_000 });
  for (const n of numbers) heads.set(n, await repo.rev(`refs/viewer/pr/${n}`));
  return heads;
}

export interface PrMeta {
  number: number;
  title: string;
  body: string;
  author: { login: string };
  state: string;
  isDraft: boolean;
  baseRefName: string;
  headRefName: string;
  headRefOid: string;
  url: string;
  reviews: { author?: { login?: string }; state?: string; body?: string; submittedAt?: string }[];
  comments: { author?: { login?: string }; body?: string; createdAt?: string }[];
}

interface ReviewComment {
  id: number;
  user?: { login?: string };
  path: string;
  line?: number | null;
  original_line?: number | null;
  side?: string;
  commit_id?: string;
  original_commit_id?: string;
  body: string;
  created_at: string;
  in_reply_to_id?: number;
}

async function fetchPrData(gh: Gh, n: number): Promise<{ meta: PrMeta; comments: ReviewComment[] }> {
  const meta = await gh.json<PrMeta>([
    "pr",
    "view",
    String(n),
    "--repo",
    REPO,
    "--json",
    "number,title,body,author,state,isDraft,baseRefName,headRefName,headRefOid,url,reviews,comments",
  ]);
  const pages = await gh.json<ReviewComment[][]>(["api", "--paginate", "--slurp", `repos/${REPO}/pulls/${n}/comments?per_page=100`]);
  return { meta, comments: pages.flat() };
}

function attachments(meta: PrMeta, comments: ReviewComment[], mark: MarkContext | null): string {
  const cut = (s: string | undefined, n: number) => (s && s.length > n ? `${s.slice(0, n)} ...(cut)` : (s ?? ""));
  const slimMeta = {
    ...meta,
    body: cut(meta.body, 20_000),
    reviews: meta.reviews.map((r) => ({ ...r, body: cut(r.body, 3_000) })),
    comments: meta.comments.map((c) => ({ ...c, body: cut(c.body, 3_000) })),
  };
  const slimComments = comments.map((c) => ({
    id: c.id,
    user: c.user?.login,
    path: c.path,
    line: c.line ?? null,
    original_line: c.original_line ?? null,
    side: c.side,
    commit_id: c.commit_id,
    original_commit_id: c.original_commit_id,
    in_reply_to_id: c.in_reply_to_id,
    created_at: c.created_at,
    body: cut(c.body, 3_000),
  }));
  const parts = [inputBlock("PR METADATA", JSON.stringify(slimMeta, null, 1)), inputBlock("REVIEW COMMENTS", JSON.stringify(slimComments, null, 1))];
  if (mark) {
    parts.push(
      inputBlock(
        "SESSIONS",
        mark.sessions.length
          ? [...mark.notes, ...mark.sessions.map((s) => `### ${s.file} (modified ${s.modified})\n${s.text}`)].join("\n\n")
          : "No Claude Code transcripts match this branch.",
      ),
      inputBlock("IRIS JOBS", mark.jobs.length ? mark.jobs.map((j) => `### ${j.name}\n${j.record}`).join("\n\n") : "No Iris jobs are mentioned."),
    );
  }
  return parts.join("\n");
}

// ---------------------------------------------------------------------------
// Worktrees

export async function ensureWorktree(repo: MarinRepo, dir: string, head: string): Promise<void> {
  if (existsSync(dir)) {
    if (!existsSync(path.join(dir, ".git"))) throw new Error(`${dir} exists and is not a worktree`);
    await gitIn(dir)(["checkout", "--quiet", "--detach", head]);
    return;
  }
  await mkdir(path.dirname(dir), { recursive: true });
  await repo.git(["worktree", "add", "--quiet", "--detach", dir, head], { timeoutMs: 300_000 });
}

// ---------------------------------------------------------------------------
// Cold reader

export interface Gap {
  where: string;
  claim: string;
  problem: string;
}

export function parseGaps(text: string): Gap[] {
  const a = text.indexOf("{");
  const b = text.lastIndexOf("}");
  if (a < 0 || b <= a) throw new Error("the cold reader's reply holds no JSON object");
  const doc = JSON.parse(text.slice(a, b + 1)) as { gaps?: unknown };
  if (!Array.isArray(doc.gaps)) throw new Error("the cold reader's reply has no gaps list");
  return doc.gaps.filter((g): g is Gap => !!g && typeof g === "object" && typeof (g as Gap).claim === "string");
}

/** The PR description and the code-path steps, as the cold reader receives them. */
export async function describedText(dir: string): Promise<string> {
  const front = parseEntry(await readFile(path.join(dir, "pr.md"), "utf8")).front;
  const lines = [`l1: ${front.l1 ?? ""}`, ...(front.l2 ? [`l2: ${front.l2}`] : []), ...(front.l3 ?? []).map((p, i) => `l3[${i}]: ${p}`), ""];
  try {
    const steps = JSON.parse(await readFile(path.join(dir, "code-path.json"), "utf8")) as { id: number; title: string; l1: string; l2?: string; excerpts: { path: string; functions: string[] }[] }[];
    lines.push("Code path:");
    for (const s of steps) {
      lines.push(`step ${s.id} "${s.title}" (${s.excerpts.map((e) => `${e.path}${e.functions.length ? `: ${e.functions.join(", ")}` : ""}`).join("; ")})`);
      lines.push(`step ${s.id} l1: ${s.l1}`);
      if (s.l2) lines.push(`step ${s.id} l2: ${s.l2}`);
    }
  } catch {
    // validation reports a broken code path; the reader checks the description alone
  }
  return lines.join("\n");
}

export async function coldRead(p: { config: Config; cwd: string; prompt: string; budgetUsd: number; queryFn?: typeof sdkQuery }): Promise<{ gaps: Gap[]; cost_usd: number; error?: string }> {
  const options: Options = {
    cwd: p.cwd,
    model: COLD_READER_MODEL,
    env: backgroundEnv(p.config),
    settingSources: [],
    systemPrompt: { type: "preset", preset: "claude_code" },
    strictMcpConfig: true,
    canUseTool: readOnlyPolicy,
    permissionMode: "default",
    disallowedTools: ["Agent", "Task", "WebFetch", "WebSearch", "Write", "Edit", "NotebookEdit"],
    maxBudgetUsd: p.budgetUsd,
    maxTurns: 40,
  };
  let cost = 0;
  let text = "";
  for await (const m of (p.queryFn ?? sdkQuery)({ prompt: p.prompt, options })) {
    if (m.type === "result") {
      cost = m.total_cost_usd ?? 0;
      if (m.subtype === "success") text = m.result;
      else return { gaps: [], cost_usd: cost, error: `cold reader ended with ${m.subtype}` };
    }
  }
  try {
    return { gaps: parseGaps(text), cost_usd: cost };
  } catch (e) {
    return { gaps: [], cost_usd: cost, error: (e as Error).message };
  }
}

// ---------------------------------------------------------------------------
// The run

export interface PrepDeps {
  config: Config;
  repo: MarinRepo;
  gh: Gh;
  ledger: Ledger;
  sessions: BackgroundSessions;
  log: (line: string) => void;
  /** Per-run cost cap passed to the SDK as `maxBudgetUsd`. */
  budgetUsd: number;
  coldReaderBudgetUsd: number;
  effort: "low" | "medium" | "high" | "xhigh";
  user?: string;
  queryFn?: typeof sdkQuery;
}

export interface PrepOutcome {
  record: PrRecord;
  validation: Validation | null;
  checker: string[];
  gaps: Gap[];
  turns: { name: string; cost_usd: number }[];
  commit: string | null;
}

function problemsText(v: Validation, checker: string[]): string[] {
  return [...v.problems, ...checker.map((f) => f.replace(/^FAIL\s+/, "check_fixture: "))];
}

export async function preparePr(d: PrepDeps, listed: SearchedPr, head: string, prior: PrRecord | undefined): Promise<PrepOutcome> {
  const { config, repo, gh } = d;
  let pr = listed;
  const n = pr.number;
  const outDir = prDir(config.wordbase, n);
  const wt = path.join(config.state, "worktrees", `pr-${n}`);
  const runLog = path.join(config.state, "runs", `pr-${n}-${head.slice(0, 7)}.log`);
  await mkdir(path.dirname(runLog), { recursive: true });
  const lines: string[] = [];
  const log = (l: string) => {
    lines.push(`${new Date().toISOString()} ${l}`);
  };
  const flush = () => writeFile(runLog, lines.join("\n") + "\n", "utf8");
  const turns: PrepOutcome["turns"] = [];
  const isUpdate = Boolean(prior?.head && prior.session_id && prior.head !== head && prior.status === "prepared");

  try {
    const { meta, comments } = await fetchPrData(gh, n);
    pr = { ...pr, title: meta.title || pr.title, author: meta.author?.login || pr.author };
    if (meta.headRefOid !== head) log(`gh reports head ${meta.headRefOid.slice(0, 10)}; git fetched ${head.slice(0, 10)}; using the git head`);
    if (meta.baseRefName !== "main") await repo.git(["fetch", "--quiet", "--no-tags", "origin", meta.baseRefName], { timeoutMs: 180_000 });
    const base = await repo.rev(`origin/${meta.baseRefName}`);
    const mergeBase = (await repo.git(["merge-base", base, head])).trim();
    await ensureWorktree(repo, wt, head);
    await mkdir(outDir, { recursive: true });

    const mark = pr.reasons.includes("own PR") || meta.author.login === (d.user ?? "muchanem") ? await markContext(meta.headRefName, config.marin).catch((e: Error) => ({ sessions: [], jobs: [], notes: [`transcript search failed: ${e.message}`] })) : null;
    const checkCommand = ["uv", ...checkerArgs({ prompts: config.prompts, wordbase: config.wordbase, marin: config.marin, pr: n })].join(" ");
    const values = { number: String(n), head, base, merge_base: mergeBase, wordbase: config.wordbase, check: checkCommand };
    const data = attachments(meta, comments, mark);

    const options: Partial<Options> = {
      model: PREP_MODEL,
      effort: d.effort,
      canUseTool: prepPolicy({ outDir, checkCommand, log }),
      permissionMode: "default",
      disallowedTools: ["Agent", "Task", "WebFetch", "WebSearch", "NotebookEdit"],
      maxBudgetUsd: d.budgetUsd,
      systemPrompt: {
        type: "preset",
        preset: "claude_code",
        append: `This is a background preparation run of the Marin viewer for PR #${n}. No viewer is attached. The working directory ${wt} is a worktree at the PR head. The wordbase is at ${config.wordbase}; write only under ${outDir}.`,
      },
    };

    let session: string;
    let first: string;
    if (isUpdate) {
      const opened = await d.sessions.manager.open({ scope: { pr: n }, resume: prior!.session_id!, cwd: wt, mode: "background", options });
      session = opened.session;
      first = [
        `PR #${n} has a new head ${head} (it was ${prior!.head}). The base is ${base} and the merge base is ${mergeBase}. The worktree ${wt} is now at the new head.`,
        `Follow the "Update turns" section of the preparation prompt, then run \`${checkCommand}\` and fix what it reports. Set \`head\`, \`commit\`, \`base\`, \`merge_base\`, \`updated\` and \`session_id\` (${session}) in pr.md.`,
        "",
        data,
      ].join("\n");
    } else {
      const opened = await d.sessions.manager.open({ scope: { pr: n }, fresh: true, cwd: wt, mode: "background", options });
      session = opened.session;
      first = `${await renderPrompt(config.prompts, "prepare-pr.md", values)}\n\nUse \`${session}\` as \`session_id\` and \`${PREP_MODEL} prep ${n}\` as \`by\` in pr.md.\n\n${data}`;
    }
    log(`session ${session} (${isUpdate ? "update" : "prepare"}) in ${wt}`);

    const runTurn = async (name: string, text: string) => {
      const t = await d.sessions.turn(session, text);
      turns.push({ name, cost_usd: t.cost_usd });
      await d.ledger.add({ at: new Date().toISOString(), kind: "prepare", run: `pr ${n} ${name}`, model: PREP_MODEL, cost_usd: t.cost_usd });
      log(`turn ${name}: ${t.subtype}${t.is_error ? " (error)" : ""}, $${t.cost_usd.toFixed(3)}`);
      d.log(`  pr #${n} turn ${name}: ${t.subtype}, $${t.cost_usd.toFixed(2)}`);
      // A failed API call ends the turn with subtype success, is_error set and the API's message as the text.
      if (t.is_error) throw new Error(`turn ${name} failed: ${t.text.trim().slice(0, 300) || t.subtype}`);
      return t;
    };

    await runTurn(isUpdate ? "update" : "prepare", first);

    const check = async () => {
      const v = await validatePrOutputs(outDir, { number: n, head });
      const c = await runChecker({ prompts: config.prompts, wordbase: config.wordbase, marin: config.marin, pr: n, cwd: config.root });
      return { v, failures: c.failures };
    };
    let { v, failures } = await check();
    let fixUsed = false;
    const issues = problemsText(v, failures);
    log(`validation: ${issues.length} problems, ${v.lint.length} lint hits`);
    if (issues.length || v.lint.length) {
      fixUsed = issues.length > 0;
      await runTurn(
        "fix",
        [
          "The poller checked the outputs. Fix every item below, rerun the check command, and stop.",
          ...(issues.length ? ["", "Validation failures:", ...issues.map((i) => `- ${i}`)] : []),
          ...(v.lint.length ? ["", "Style lint hits (rewrite each sentence from scratch under prompts/style.md; do not swap in a synonym):", ...v.lint.map((i) => `- ${i}`)] : []),
        ].join("\n"),
      );
      ({ v, failures } = await check());
      log(`after fix: ${problemsText(v, failures).length} problems, ${v.lint.length} lint hits`);
    }

    // Cold reader over the PR description and the code path.
    let gaps: Gap[] = [];
    if (existsSync(path.join(outDir, "pr.md"))) {
      const prompt = await renderPrompt(config.prompts, "cold-reader.md", {
        subject: `PR #${n} of marin-community/marin and its code path`,
        where: `in your working directory, a checkout of the PR head ${head}; the PR's changes are \`git diff ${mergeBase} ${head}\``,
        text: await describedText(outDir),
        code: `Read it in your working directory with Read, Grep and read-only git commands, starting from \`git diff ${mergeBase} ${head} --stat\`.`,
      });
      const cr = await coldRead({ config, cwd: wt, prompt, budgetUsd: d.coldReaderBudgetUsd, ...(d.queryFn ? { queryFn: d.queryFn } : {}) });
      turns.push({ name: "cold-reader", cost_usd: cr.cost_usd });
      await d.ledger.add({ at: new Date().toISOString(), kind: "cold-reader", run: `pr ${n}`, model: COLD_READER_MODEL, cost_usd: cr.cost_usd });
      gaps = cr.gaps;
      log(`cold reader: ${gaps.length} gaps, $${cr.cost_usd.toFixed(3)}${cr.error ? `, error: ${cr.error}` : ""}`);
      d.log(`  pr #${n} cold reader: ${gaps.length} gaps, $${cr.cost_usd.toFixed(2)}${cr.error ? ` (${cr.error})` : ""}`);
      if (gaps.length) {
        await runTurn(
          "cold-reader rewrite",
          [
            "A cold reader with only the description and the code could not check the claims below. Fix each gap with the smallest local edit to pr.md or code-path.json: name the referent, correct the claim, or narrow it when the full explanation would interrupt the text. Keep the style rules, rerun the check command, and stop.",
            "",
            ...gaps.map((g) => `- ${g.where}: "${g.claim}": ${g.problem}`),
          ].join("\n"),
        );
        ({ v, failures } = await check());
        const left = problemsText(v, failures);
        if (left.length && !fixUsed) {
          fixUsed = true;
          await runTurn("fix after rewrite", ["The rewrite broke the outputs. Fix every item below, rerun the check command, and stop.", "", ...left.map((i) => `- ${i}`)].join("\n"));
          ({ v, failures } = await check());
        }
      }
    }

    const left = problemsText(v, failures);
    // Text that still fails lint after one rewrite is kept with a `lint:` field listing the hits.
    if (existsSync(path.join(outDir, "pr.md"))) {
      const entry = parseEntry(await readFile(path.join(outDir, "pr.md"), "utf8"));
      if (v.lint.length) entry.front.lint = v.lint;
      else delete entry.front.lint;
      // The model does not know the time; it has written local times marked Z. The poller's clock is the record.
      const now = new Date().toISOString().replace(/\.\d+Z$/, "Z");
      entry.front.updated = now;
      if (!isUpdate || !entry.front.prepared_at) entry.front.prepared_at = now;
      await writeFile(path.join(outDir, "pr.md"), writeEntry(entry), "utf8");
    }
    const cost = turns.reduce((s, t) => s + t.cost_usd, 0);
    const files = ["pr.md", "code-path.json", "diagrams.json", "notes.jsonl", "files.json"].map((f) => path.join(outDir, f)).filter((f) => existsSync(f));
    const status = left.length ? "invalid" : "prepared";
    const title = isUpdate ? `Update the preparation of PR #${n} for ${head.slice(0, 7)}` : `Prepare PR #${n} at ${head.slice(0, 7)} for review`;
    const body = [
      `${isUpdate ? "Revises" : "Writes"} the description, code path, diagrams, review notes and file descriptions for marin-community/marin#${n} (${pr.title}) at head ${head.slice(0, 12)}, from a background ${PREP_MODEL} session ${session}.`,
      `The outputs have ${v.counts.steps} steps, ${v.counts.diagrams} diagrams, ${v.counts.notes} review notes and ${v.counts.files} file descriptions. ${left.length ? `Validation still fails on ${left.length} checks, so the poller marks the run invalid.` : "They pass the schema checks and check_fixture.py."} ${v.lint.length ? `Lint still reports ${v.lint.length} hits, which pr.md lists under lint.` : "Lint reports no hits."} The cold reader raised ${gaps.length} gaps. The run cost $${cost.toFixed(2)}.`,
    ].join("\n\n");
    const commit = await commitWordbase(config.wordbase, `${title}\n\n${body}`, files);
    log(`wordbase commit ${commit ?? "(nothing changed)"}`);
    await flush();
    return {
      record: {
        number: n,
        title: pr.title,
        author: pr.author,
        reasons: pr.reasons,
        head,
        session_id: session,
        status,
        prepared_at: new Date().toISOString(),
        cost_usd: cost,
        ...(left.length ? { failed_head: head, error: left.slice(0, 5).join("; ") } : {}),
      },
      validation: v,
      checker: failures,
      gaps,
      turns,
      commit,
    };
  } catch (e) {
    log(`failed: ${(e as Error).message}`);
    await flush();
    return {
      record: { ...(prior ?? {}), number: n, title: pr.title, author: pr.author, reasons: pr.reasons, status: "failed", ...(isCreditError((e as Error).message) ? {} : { failed_head: head }), error: (e as Error).message.slice(0, 500), cost_usd: turns.reduce((s, t) => s + t.cost_usd, 0) },
      validation: null,
      checker: [],
      gaps: [],
      turns,
      commit: null,
    };
  }
}

