// Child-process helpers for the poller. Every helper here either returns the output or throws with
// the command and its stderr, so a failed `git` or `gh` call can never read as an empty result.

import { execFile } from "node:child_process";

export interface RunResult {
  code: number;
  stdout: string;
  stderr: string;
}

export interface RunOptions {
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  timeoutMs?: number;
  input?: string;
  maxBuffer?: number;
}

/** Run a command and resolve with its exit code and output. Never rejects. */
export function run(cmd: string, args: string[], opts: RunOptions = {}): Promise<RunResult> {
  return new Promise((resolve) => {
    const child = execFile(
      cmd,
      args,
      {
        cwd: opts.cwd,
        env: opts.env,
        timeout: opts.timeoutMs ?? 120_000,
        maxBuffer: opts.maxBuffer ?? 64 * 1024 * 1024,
      },
      (err, stdout, stderr) => {
        const e = err as (NodeJS.ErrnoException & { code?: unknown; killed?: boolean; signal?: string }) | null;
        let code = 0;
        if (e) code = typeof e.code === "number" ? e.code : e.killed ? 124 : 1;
        const extra = e && typeof e.code === "string" ? `${e.code}: ${e.message}` : e?.killed ? `timed out after ${opts.timeoutMs ?? 120_000} ms` : "";
        resolve({ code, stdout: String(stdout ?? ""), stderr: `${String(stderr ?? "")}${extra ? `\n${extra}` : ""}` });
      },
    );
    if (opts.input !== undefined) child.stdin?.end(opts.input);
  });
}

/** The Anthropic account is out of API credit. Every later call fails the same way until Mark tops it up. */
export function isCreditError(message: string): boolean {
  return /credit balance is too low/i.test(message);
}

export class CommandError extends Error {
  constructor(
    readonly cmd: string,
    readonly result: RunResult,
  ) {
    super(`${cmd} failed (exit ${result.code}): ${(result.stderr || result.stdout).trim().slice(0, 600)}`);
  }
}

/** Run a command and return stdout; throw a CommandError on a non-zero exit. */
export async function check(cmd: string, args: string[], opts: RunOptions = {}): Promise<string> {
  const r = await run(cmd, args, opts);
  if (r.code !== 0) throw new CommandError(`${cmd} ${args.slice(0, 6).join(" ")}`, r);
  return r.stdout;
}

export type Git = (args: string[], opts?: RunOptions) => Promise<string>;

/** A git runner bound to one repository. */
export function gitIn(repo: string): Git {
  return (args, opts) => check("git", ["-C", repo, ...args], opts);
}

/**
 * The `gh` runner for the poller. It counts every call, because the GitHub API quota is shared by
 * every job on the account, and turns a non-zero exit or unparseable output into an error.
 */
export class Gh {
  calls = 0;
  constructor(private readonly runner: (args: string[]) => Promise<RunResult> = (args) => run("gh", args, { timeoutMs: 60_000 })) {}

  async json<T = unknown>(args: string[]): Promise<T> {
    this.calls++;
    const r = await this.runner(args);
    if (r.code !== 0) throw new CommandError(`gh ${args.slice(0, 4).join(" ")}`, r);
    const text = r.stdout.trim();
    if (!text) throw new Error(`gh ${args.slice(0, 4).join(" ")} returned no output`);
    try {
      return JSON.parse(text) as T;
    } catch {
      throw new Error(`gh ${args.slice(0, 4).join(" ")} returned non-JSON output: ${text.slice(0, 200)}`);
    }
  }
}
