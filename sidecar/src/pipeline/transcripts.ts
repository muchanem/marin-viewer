// Context for Mark's own PRs (DESIGN.md section 8): excerpts of the Claude Code transcripts whose
// sessions ran on the PR's branch or in a worktree named after it, and the Iris jobs they mention.
// Every read is bounded: at most `maxSessions` transcripts, `perSession` characters from each,
// `maxJobs` jobs and `jobLines` lines of each job record.

import { readFile, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { run } from "./exec.js";

export interface SessionExcerpt {
  file: string;
  modified: string;
  text: string;
}

export interface MarkContext {
  sessions: SessionExcerpt[];
  jobs: { name: string; record: string }[];
  notes: string[];
}

export interface TranscriptOptions {
  projectsDir?: string;
  maxSessions?: number;
  perSession?: number;
  maxJobs?: number;
  jobLines?: number;
  /** Runs `iris job describe`; injectable for tests. */
  describeJob?: (name: string) => Promise<string>;
}

/** Transcript files whose lines name the branch as `gitBranch` or a cwd ending in the branch's leaf. */
export async function findTranscripts(branch: string, projectsDir: string): Promise<string[]> {
  const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const leaf = branch.split("/").at(-1)!;
  // rg exits 1 on no match, which is a valid empty answer; 2 is an error.
  const pattern = `"gitBranch":"${esc(branch)}"|"cwd":"[^"]*/${esc(leaf)}"`;
  const r = await run("rg", ["-l", "--glob", "*.jsonl", "--max-filesize", "200M", "-e", pattern, projectsDir], { timeoutMs: 60_000 });
  if (r.code > 1) throw new Error(`rg over ${projectsDir} failed: ${r.stderr.trim().slice(0, 200)}`);
  return r.stdout.split("\n").filter(Boolean);
}

/** User and assistant text from one transcript, newest last, cut to `limit` characters. */
export function excerpt(jsonl: string, limit: number): string {
  const parts: string[] = [];
  for (const line of jsonl.split("\n")) {
    if (!line.trim()) continue;
    let m: { type?: string; message?: { role?: string; content?: unknown } };
    try {
      m = JSON.parse(line);
    } catch {
      continue;
    }
    if (m.type !== "user" && m.type !== "assistant") continue;
    const c = m.message?.content;
    const text =
      typeof c === "string"
        ? c
        : Array.isArray(c)
          ? c.flatMap((b: { type?: string; text?: string }) => (b?.type === "text" && typeof b.text === "string" ? [b.text] : [])).join("\n")
          : "";
    if (!text.trim() || text.startsWith("<command-") || text.startsWith("<local-command")) continue;
    parts.push(`[${m.type}] ${text.trim().slice(0, 2_000)}`);
  }
  // Keep the end of the session, where the outcome is.
  let out = parts.join("\n");
  if (out.length > limit) out = `... (earlier turns cut)\n${out.slice(out.length - limit)}`;
  return out;
}

/** Iris job names in text: `/muchanem/<job>` paths and `--job-name <job>` flags. */
export function jobNames(text: string): string[] {
  const names = new Set<string>();
  for (const m of text.matchAll(/\/muchanem\/[A-Za-z0-9][A-Za-z0-9._-]{2,80}/g)) names.add(m[0].replace(/[._-]+$/, ""));
  for (const m of text.matchAll(/--job-name[= ]+([A-Za-z0-9][A-Za-z0-9._-]{2,80})/g)) names.add(`/muchanem/${m[1]}`);
  return [...names];
}

export async function markContext(branch: string, marin: string, opts: TranscriptOptions = {}): Promise<MarkContext> {
  const projectsDir = opts.projectsDir ?? path.join(os.homedir(), ".claude", "projects");
  const maxSessions = opts.maxSessions ?? 4;
  const perSession = opts.perSession ?? 12_000;
  const maxJobs = opts.maxJobs ?? 4;
  const jobLines = opts.jobLines ?? 40;
  const notes: string[] = [];
  const files = await findTranscripts(branch, projectsDir);
  const dated = await Promise.all(files.map(async (f) => ({ f, t: (await stat(f)).mtime })));
  dated.sort((a, b) => b.t.getTime() - a.t.getTime());
  if (dated.length > maxSessions) notes.push(`${dated.length} transcripts match; the ${maxSessions} most recent are attached`);
  const sessions: SessionExcerpt[] = [];
  const allText: string[] = [];
  for (const { f, t } of dated.slice(0, maxSessions)) {
    const text = excerpt(await readFile(f, "utf8"), perSession);
    if (!text) continue;
    sessions.push({ file: f, modified: t.toISOString(), text });
    allText.push(text);
  }
  const names = jobNames(allText.join("\n"));
  if (names.length > maxJobs) notes.push(`${names.length} Iris jobs are mentioned; the first ${maxJobs} are described`);
  const describe =
    opts.describeJob ??
    (async (name: string) => {
      const r = await run("uv", ["run", "--frozen", "iris", "--cluster=marin", "job", "describe", name], { cwd: marin, timeoutMs: 90_000 });
      if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim().split("\n").slice(-2).join(" ").slice(0, 300));
      return r.stdout;
    });
  const jobs: MarkContext["jobs"] = [];
  for (const name of names.slice(0, maxJobs)) {
    try {
      jobs.push({ name, record: (await describe(name)).split("\n").slice(0, jobLines).join("\n") });
    } catch (e) {
      jobs.push({ name, record: `(job describe failed: ${(e as Error).message})` });
    }
  }
  return { sessions, jobs, notes };
}
