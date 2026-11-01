// Read-side helpers over the Marin clone. The poller only fetches and fast-forwards `main` here;
// PR heads live in separate worktrees (prepare.ts), so the clone never checks out another branch.

import { gitIn, type Git } from "./exec.js";

export interface Change {
  status: "added" | "modified" | "deleted" | "renamed";
  path: string;
  /** The old path of a rename. */
  from?: string;
}

export class MarinRepo {
  readonly git: Git;
  private shown = new Map<string, string | null>();

  constructor(
    readonly root: string,
    git?: Git,
  ) {
    this.git = git ?? gitIn(root);
  }

  async rev(ref: string): Promise<string> {
    return (await this.git(["rev-parse", "--verify", `${ref}^{commit}`])).trim();
  }

  async hasCommit(sha: string): Promise<boolean> {
    try {
      await this.git(["cat-file", "-e", `${sha}^{commit}`]);
      return true;
    } catch {
      return false;
    }
  }

  /**
   * `git fetch origin main`, then `git merge --ff-only origin/main` on `main`. Refuses to run when
   * the clone is on another branch, since the poller must never change what is checked out.
   */
  async updateMain(): Promise<{ before: string; after: string }> {
    const branch = (await this.git(["symbolic-ref", "--short", "HEAD"])).trim();
    if (branch !== "main") throw new Error(`the clone at ${this.root} is on ${branch}, not main; the poller only fast-forwards main`);
    const before = await this.rev("HEAD");
    await this.git(["fetch", "--quiet", "origin", "main"], { timeoutMs: 180_000 });
    await this.git(["merge", "--ff-only", "--quiet", "origin/main"], { timeoutMs: 120_000 });
    return { before, after: await this.rev("HEAD") };
  }

  async commitCount(from: string, to: string): Promise<number> {
    return Number((await this.git(["rev-list", "--count", `${from}..${to}`])).trim());
  }

  async subject(sha: string): Promise<string> {
    return (await this.git(["log", "-1", "--format=%s", sha])).trim();
  }

  /** Python files under `lib/` that `from..to` adds, modifies, renames or deletes. */
  async changedPython(from: string, to: string): Promise<Change[]> {
    const out = await this.git(["diff", "--name-status", "-M", "--no-color", from, to, "--", "lib/"]);
    return parseNameStatus(out).filter((c) => c.path.endsWith(".py") || (c.from?.endsWith(".py") ?? false));
  }

  async show(commit: string, path: string): Promise<string | null> {
    const key = `${commit}:${path}`;
    if (!this.shown.has(key)) {
      try {
        this.shown.set(key, await this.git(["show", key]));
      } catch {
        this.shown.set(key, null);
      }
    }
    return this.shown.get(key)!;
  }

  async lsTree(commit: string, prefix: string): Promise<string[]> {
    const out = await this.git(["ls-tree", "-r", "--name-only", commit, "--", prefix]);
    return out.split("\n").filter(Boolean);
  }

  /** Blob sizes for every file under `prefix`, from one `ls-tree -l`. */
  async sizes(commit: string, prefix: string): Promise<Map<string, number>> {
    const out = await this.git(["ls-tree", "-r", "-l", commit, "--", prefix]);
    const m = new Map<string, number>();
    for (const line of out.split("\n")) {
      const t = /^\S+ blob \S+\s+(\d+)\t(.+)$/.exec(line);
      if (t) m.set(t[2]!, Number(t[1]));
    }
    return m;
  }

  async diff(from: string, to: string, paths: string[]): Promise<string> {
    if (!paths.length) return "";
    return this.git(["diff", "--no-color", "-U3", from, to, "--", ...paths]);
  }

  /** `git grep` at a commit; exit 1 (no match) yields an empty list. */
  async grep(commit: string, pattern: string, pathspecs: string[]): Promise<{ path: string; line: number; text: string }[]> {
    let out: string;
    try {
      out = await this.git(["grep", "-n", "-I", "-E", pattern, commit, "--", ...pathspecs]);
    } catch (e) {
      const r = (e as { result?: { code: number; stderr: string } }).result;
      if (r && r.code === 1 && !r.stderr.trim()) return [];
      throw e;
    }
    const hits: { path: string; line: number; text: string }[] = [];
    const prefix = `${commit}:`;
    for (const raw of out.split("\n")) {
      if (!raw.startsWith(prefix)) continue;
      const rest = raw.slice(prefix.length);
      const m = /^(.+?):(\d+):(.*)$/.exec(rest);
      if (m) hits.push({ path: m[1]!, line: Number(m[2]), text: m[3]! });
    }
    return hits;
  }
}

export function parseNameStatus(out: string): Change[] {
  const changes: Change[] = [];
  for (const line of out.split("\n")) {
    if (!line.trim()) continue;
    const parts = line.split("\t");
    const code = parts[0]!;
    if (code.startsWith("R") && parts.length >= 3) changes.push({ status: "renamed", from: parts[1]!, path: parts[2]! });
    else if (code.startsWith("C") && parts.length >= 3) changes.push({ status: "added", path: parts[2]! });
    else if (code === "A") changes.push({ status: "added", path: parts[1]! });
    else if (code === "D") changes.push({ status: "deleted", path: parts[1]! });
    else if (parts[1]) changes.push({ status: "modified", path: parts[1] });
  }
  return changes;
}

// ---------------------------------------------------------------------------
// Modules and imports

/** `lib/shellbox/src/shellbox/task.py` -> `shellbox.task`; `.../pkg/__init__.py` -> `pkg`. */
export function moduleOf(path: string): string | null {
  if (!path.startsWith("lib/") || !path.endsWith(".py")) return null;
  const parts = path.split("/");
  const src = parts.indexOf("src");
  const rest = src >= 0 ? parts.slice(src + 1) : parts.slice(2);
  if (!rest.length) return null;
  rest[rest.length - 1] = rest[rest.length - 1]!.replace(/\.py$/, "");
  if (rest[rest.length - 1] === "__init__") rest.pop();
  return rest.length ? rest.join(".") : null;
}

/** The package a module's relative imports start from. */
function packageOf(path: string): string[] {
  const mod = moduleOf(path);
  if (!mod) return [];
  const parts = mod.split(".");
  return path.endsWith("/__init__.py") ? parts : parts.slice(0, -1);
}

/** `lib/shellbox/...` -> `shellbox`. */
export function packageName(path: string): string {
  return path.split("/")[1] ?? "";
}

export interface ImportLine {
  /** `from X import a, b` gives module X and names [a, b]; `import X.Y` gives module X.Y. */
  module: string;
  names: string[];
}

/** Parse the first line of an import statement, resolving relative imports against `path`. */
export function parseImport(path: string, text: string): ImportLine | null {
  const line = text.replace(/#.*$/, "").trim();
  let m = /^from\s+(\.*)([\w.]*)\s+import\s+(.*)$/.exec(line);
  if (m) {
    const dots = m[1]!.length;
    let base = m[2]!;
    if (dots) {
      const pkg = packageOf(path);
      const up = pkg.slice(0, Math.max(0, pkg.length - (dots - 1)));
      base = [...up, ...(base ? base.split(".") : [])].join(".");
    }
    if (!base) return null;
    const names = m[3]!
      .replace(/[()\\]/g, " ")
      .split(",")
      .map((s) => s.trim().split(/\s+/)[0] ?? "")
      .filter((s) => /^\w+$/.test(s));
    return { module: base, names };
  }
  m = /^import\s+(.*)$/.exec(line);
  if (m) {
    const first = m[1]!.split(",")[0]!.trim().split(/\s+/)[0] ?? "";
    return /^[\w.]+$/.test(first) ? { module: first, names: [] } : null;
  }
  return null;
}

/** Maps module names to repository paths for every Python file under `lib/` at one commit. */
export class ModuleIndex {
  private byModule = new Map<string, string>();

  constructor(paths: string[]) {
    for (const p of paths) {
      const mod = moduleOf(p);
      if (mod && !this.byModule.has(mod)) this.byModule.set(mod, p);
    }
  }

  path(module: string): string | undefined {
    return this.byModule.get(module);
  }

  /** The files an import refers to: submodules named in `from X import a`, else X or its longest known prefix. */
  resolve(imp: ImportLine): string[] {
    const out = new Set<string>();
    for (const n of imp.names) {
      const sub = this.byModule.get(`${imp.module}.${n}`);
      if (sub) out.add(sub);
    }
    if (out.size < Math.max(1, imp.names.length)) {
      const parts = imp.module.split(".");
      for (let i = parts.length; i > 0; i--) {
        const p = this.byModule.get(parts.slice(0, i).join("."));
        if (p) {
          out.add(p);
          break;
        }
      }
    }
    return [...out];
  }
}

/** Every import edge among Python files under `lib/` at `commit`, from one `git grep`. */
export async function importGraph(repo: MarinRepo, commit: string): Promise<{ index: ModuleIndex; imports: Map<string, Set<string>>; importers: Map<string, Set<string>> }> {
  const files = (await repo.lsTree(commit, "lib/")).filter((p) => p.endsWith(".py"));
  const index = new ModuleIndex(files);
  const hits = await repo.grep(commit, "^[[:space:]]*(from|import)[[:space:]]", ["lib/*.py"]);
  const imports = new Map<string, Set<string>>();
  const importers = new Map<string, Set<string>>();
  for (const h of hits) {
    const imp = parseImport(h.path, h.text);
    if (!imp) continue;
    for (const target of index.resolve(imp)) {
      if (target === h.path) continue;
      if (!imports.has(h.path)) imports.set(h.path, new Set());
      imports.get(h.path)!.add(target);
      if (!importers.has(target)) importers.set(target, new Set());
      importers.get(target)!.add(h.path);
    }
  }
  return { index, imports, importers };
}

/** First lines of class and function definitions, at module level and one level in. */
export function signatures(source: string, maxLines = 40): string[] {
  const out: string[] = [];
  for (const line of source.split("\n")) {
    const m = /^( {0,4})(async\s+def|def|class)\s+\w+/.exec(line);
    if (!m) continue;
    const name = /(?:def|class)\s+(\w+)/.exec(line)![1]!;
    if (m[1] && name.startsWith("__") && name !== "__init__" && name !== "__call__") continue;
    out.push(line.trimEnd());
    if (out.length >= maxLines) {
      out.push("    ... (more definitions)");
      break;
    }
  }
  return out;
}
