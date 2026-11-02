// Poller state under `state/` (DESIGN.md section 8): `main.json` for the described commit range,
// `prs.json` for prepared heads, `queue.json` for deferred regenerations and `spend.jsonl`, an
// append-only ledger of every background run's cost.

import { appendFile, mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";

export async function readJson<T>(file: string, fallback: T): Promise<T> {
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return fallback;
    throw e;
  }
  // A corrupt state file is an error, not an empty state: an empty state would redo or skip work.
  return JSON.parse(text) as T;
}

export async function writeJson(file: string, value: unknown): Promise<void> {
  await mkdir(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  await writeFile(tmp, JSON.stringify(value, null, 2) + "\n", "utf8");
  await rename(tmp, file);
}

// ---------------------------------------------------------------------------
// state/main.json

export interface MainState {
  /** Every commit up to and including this one has been described. */
  described: string | null;
  /** The range the last completed run covered, and when its read of `main` started. */
  last_run?: { from: string | null; to: string; read_started: string; finished: string; files: number };
  /** Set while a run is under way; a crash leaves it behind and the next tick redoes the range. */
  in_progress?: { from: string | null; to: string; read_started: string };
  /** When the last tick started, for the GAP line. */
  last_tick?: string;
}

// ---------------------------------------------------------------------------
// state/prs.json

export interface PrRecord {
  number: number;
  title: string;
  author: string;
  /** Why the PR is on the list: a review request, Mark's own PR, or both. */
  reasons: string[];
  /** The head the outputs describe; absent until a preparation run succeeds. */
  head?: string;
  session_id?: string;
  status: "prepared" | "invalid" | "failed" | "running";
  prepared_at?: string;
  cost_usd?: number;
  /** A head that failed, so the same head is not retried every tick. */
  failed_head?: string;
  error?: string;
}

export interface PrsState {
  prs: Record<string, PrRecord>;
}

// ---------------------------------------------------------------------------
// state/queue.json: regenerations deferred because spending ran ahead of pace.

export interface QueuedFile {
  path: string;
  commit: string;
  change: "modified" | "added";
  queued: string;
}

export interface QueueState {
  files: QueuedFile[];
}

// ---------------------------------------------------------------------------
// state/spend.jsonl

export interface SpendRecord {
  at: string;
  kind: "describe" | "system" | "prepare" | "cold-reader" | "compare" | "first-pass" | "probe";
  run: string;
  model: string;
  cost_usd: number;
  input_tokens?: number;
  output_tokens?: number;
  latency_ms?: number;
}

export class Ledger {
  constructor(readonly file: string) {}

  async add(r: SpendRecord): Promise<void> {
    await mkdir(path.dirname(this.file), { recursive: true });
    await appendFile(this.file, JSON.stringify(r) + "\n", "utf8");
  }

  async all(): Promise<SpendRecord[]> {
    let text: string;
    try {
      text = await readFile(this.file, "utf8");
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "ENOENT") return [];
      throw e;
    }
    return text
      .split("\n")
      .filter((l) => l.trim())
      .map((l) => JSON.parse(l) as SpendRecord);
  }

  async monthToDate(now = new Date()): Promise<number> {
    const month = now.toISOString().slice(0, 7);
    return (await this.all()).filter((r) => r.at.startsWith(month)).reduce((s, r) => s + r.cost_usd, 0);
  }
}

/**
 * The spending pace: the share of the monthly budget that should be spent by `now`. Spending above
 * it defers file regenerations; PR preparation always runs.
 */
export function paceUsd(monthlyBudget: number, now = new Date()): number {
  const start = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1);
  const end = Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + 1, 1);
  return (monthlyBudget * (now.getTime() - start)) / (end - start);
}

export function stateFiles(stateDir: string) {
  return {
    main: path.join(stateDir, "main.json"),
    prs: path.join(stateDir, "prs.json"),
    queue: path.join(stateDir, "queue.json"),
    spend: path.join(stateDir, "spend.jsonl"),
    log: path.join(stateDir, "poller.log"),
    worktrees: path.join(stateDir, "worktrees"),
    reports: path.join(stateDir, "reports"),
    runs: path.join(stateDir, "runs"),
  };
}
