// `review.post` (DESIGN.md section 7, "Posting"): one pending review with every approved note as
// an inline comment, then submit it, then record each note's `github_comment_id`. This is the only
// path in the viewer that writes to GitHub, and it runs only after the app's confirm box.

import { execFile } from "node:child_process";
import { readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { ReviewNote, type PostNote } from "./protocol.js";
import { prDir } from "./wordbase.js";

export const DEFAULT_REPO = "marin-community/marin";

export type GhRunner = (args: string[], input?: string) => Promise<{ code: number; stdout: string; stderr: string }>;

export const runGh: GhRunner = (args, input) =>
  new Promise((resolve) => {
    const child = execFile("gh", args, { maxBuffer: 16 * 1024 * 1024 }, (err, stdout, stderr) => {
      const code = err ? (typeof (err as { code?: unknown }).code === "number" ? (err as { code: number }).code : 1) : 0;
      resolve({ code, stdout: String(stdout), stderr: String(stderr) });
    });
    if (input !== undefined) child.stdin?.end(input);
  });

/** The text posted for a note when the confirm box did not supply one. */
export function noteBody(n: Pick<PostNote, "l1" | "l2">): string {
  return n.l2 ? `${n.l1}\n\n${n.l2}` : n.l1;
}

export interface ReviewComment {
  path: string;
  line: number;
  side: "RIGHT" | "LEFT";
  body: string;
}

export interface ReviewRequest {
  endpoint: string;
  payload: { commit_id: string; comments: ReviewComment[]; body?: string };
}

/** Build the create-review call. No `event`, so GitHub leaves the review PENDING. */
export function buildReviewRequest(pr: number, notes: PostNote[], repo = DEFAULT_REPO): ReviewRequest {
  if (!notes.length) throw new Error("review.post needs at least one note");
  const notApproved = notes.filter((n) => n.status !== "approved");
  if (notApproved.length) throw new Error(`only approved notes are posted; not approved: ${notApproved.map((n) => `${n.id} (${n.status})`).join(", ")}`);
  const commits = [...new Set(notes.map((n) => n.commit))];
  if (commits.length !== 1) throw new Error(`notes span several commits (${commits.map((c) => c.slice(0, 7)).join(", ")}); a review anchors to one`);
  return {
    endpoint: `repos/${repo}/pulls/${pr}/reviews`,
    payload: {
      commit_id: commits[0]!,
      comments: notes.map((n) => ({ path: n.path, line: n.line, side: n.side === "base" ? "LEFT" : "RIGHT", body: n.body ?? noteBody(n) })),
    },
  };
}

export interface PostResult {
  review_id: number;
  html_url?: string;
  comments: { note_id: string; github_comment_id: number }[];
}

async function ghJson(gh: GhRunner, args: string[], input?: unknown): Promise<unknown> {
  const r = await gh(args, input === undefined ? undefined : JSON.stringify(input));
  if (r.code !== 0) throw new Error(`gh ${args.slice(0, 4).join(" ")} failed: ${(r.stderr || r.stdout).trim().slice(0, 500)}`);
  try {
    return r.stdout.trim() ? JSON.parse(r.stdout) : null;
  } catch {
    throw new Error(`gh ${args.slice(0, 4).join(" ")} returned non-JSON output`);
  }
}

export async function postReview(p: { pr: number; notes: PostNote[]; repo?: string | undefined; body?: string | undefined; gh?: GhRunner }): Promise<PostResult> {
  const gh = p.gh ?? runGh;
  const repo = p.repo ?? DEFAULT_REPO;
  const req = buildReviewRequest(p.pr, p.notes, repo);

  const created = (await ghJson(gh, ["api", "--method", "POST", req.endpoint, "--input", "-"], req.payload)) as { id?: number; html_url?: string } | null;
  const reviewId = created?.id;
  if (typeof reviewId !== "number") throw new Error("GitHub did not return a review id");

  try {
    await ghJson(gh, ["api", "--method", "POST", `${req.endpoint}/${reviewId}/events`, "--input", "-"], { event: "COMMENT", ...(p.body ? { body: p.body } : {}) });
  } catch (e) {
    // Leave no stray pending review behind: GitHub allows one per user per PR.
    await gh(["api", "--method", "DELETE", `${req.endpoint}/${reviewId}`]).catch(() => undefined);
    throw new Error(`submitting review ${reviewId} failed, pending review deleted: ${(e as Error).message}`);
  }

  const listed = (await ghJson(gh, ["api", "--method", "GET", `${req.endpoint}/${reviewId}/comments?per_page=100`])) as
    | { id: number; path: string; line?: number | null; original_line?: number | null; side?: string; body: string }[]
    | null;
  const comments: PostResult["comments"] = [];
  const pool = [...(listed ?? [])];
  req.payload.comments.forEach((c, i) => {
    const k = pool.findIndex((g) => g.path === c.path && (g.line ?? g.original_line) === c.line && g.body === c.body);
    if (k >= 0) {
      comments.push({ note_id: p.notes[i]!.id, github_comment_id: pool[k]!.id });
      pool.splice(k, 1);
    }
  });
  return { review_id: reviewId, ...(created?.html_url ? { html_url: created.html_url } : {}), comments };
}

/** Mark posted notes in `wordbase/prs/<n>/notes.jsonl`. Returns how many lines changed. */
export async function recordPosted(wordbase: string, pr: number, posted: PostResult["comments"], now = new Date().toISOString()): Promise<number> {
  const file = path.join(prDir(wordbase, pr), "notes.jsonl");
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return 0;
    throw e;
  }
  const byId = new Map(posted.map((c) => [c.note_id, c.github_comment_id]));
  let changed = 0;
  const lines = text.split("\n").map((line) => {
    if (!line.trim()) return line;
    const parsed = ReviewNote.safeParse(JSON.parse(line));
    if (!parsed.success) return line;
    const cid = byId.get(parsed.data.id);
    if (cid === undefined) return line;
    changed++;
    return JSON.stringify({ ...parsed.data, status: "posted", github_comment_id: cid, updated: now });
  });
  if (changed) {
    const tmp = `${file}.tmp`;
    await writeFile(tmp, lines.join("\n"), "utf8");
    await rename(tmp, file);
  }
  return changed;
}
