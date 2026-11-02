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

  async isAncestor(a: string, b: string): Promise<boolean> {
    try {
      await this.git(["merge-base", "--is-ancestor", a, b]);
      return true;
    } catch {
      return false;
    }
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

  /** The paths the clone's ignore rules match, tracked or not (`git check-ignore --no-index`). */
  async ignored(paths: string[]): Promise<string[]> {
    if (!paths.length) return [];
    try {
      const out = await this.git(["check-ignore", "--no-index", "--stdin"], { input: paths.join("\n") + "\n" });
      return out.split("\n").filter(Boolean);
    } catch (e) {
      const r = (e as { result?: { code: number; stderr: string } }).result;
      if (r && r.code === 1 && !r.stderr.trim()) return [];
      throw e;
    }
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

/**
 * Trees left out of the import graph: `vendor/` holds upstream projects (evalchemy, harbor, skyrl)
 * that Marin's own linters and type checker exclude too.
 */
export const EXCLUDED_TREES = ["vendor/"];

/**
 * The module name a file is imported by. Under `lib/` the src layout applies:
 * `lib/shellbox/src/shellbox/task.py` -> `shellbox.task`, and a package without `src/` drops its
 * first two parts (`lib/levanter/tests/x.py` -> `tests.x`). Elsewhere the repository root is on the
 * path: `experiments/grug/base.py` -> `experiments.grug.base`. `.../pkg/__init__.py` -> `pkg`.
 */
export function moduleOf(path: string): string | null {
  if (!path.endsWith(".py")) return null;
  const parts = path.split("/");
  let rest: string[];
  if (parts[0] === "lib") {
    const src = parts.indexOf("src");
    rest = src >= 0 ? parts.slice(src + 1) : parts.slice(2);
  } else rest = parts;
  rest = [...rest];
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

/**
 * The package a file counts toward when neighbours are chosen for diversity: the package name under
 * `lib/`, else the top-level tree (`experiments`, `scripts`, `tests`, `infra`, ...).
 */
export function contextPackage(path: string): string {
  const parts = path.split("/");
  return parts[0] === "lib" ? (parts[1] ?? "lib") : parts.length > 1 ? parts[0]! : "(root)";
}

/** A test file: under a `tests` or `test` directory, or named `test_*.py`, `*_test.py` or `conftest.py`. */
export function isTestPath(path: string): boolean {
  const parts = path.split("/");
  const base = parts.at(-1) ?? "";
  return parts.slice(0, -1).some((p) => p === "tests" || p === "test") || /^test_.*\.py$/.test(base) || /_test\.py$/.test(base) || base === "conftest.py";
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

/**
 * Maps module names to repository paths. Two files can claim one name (`tests.conftest` in several
 * packages without a src layout); an import then resolves to the one in the importer's own package.
 */
export class ModuleIndex {
  private byModule = new Map<string, string[]>();

  constructor(paths: string[]) {
    for (const p of paths) {
      const mod = moduleOf(p);
      if (!mod) continue;
      const list = this.byModule.get(mod);
      if (list) list.push(p);
      else this.byModule.set(mod, [p]);
    }
  }

  private pick(module: string, from?: string): string | undefined {
    const list = this.byModule.get(module);
    if (!list) return undefined;
    if (list.length === 1 || !from) return list[0];
    const home = contextPackage(from);
    return list.find((p) => contextPackage(p) === home) ?? list[0];
  }

  path(module: string, from?: string): string | undefined {
    return this.pick(module, from);
  }

  /** The files an import refers to: submodules named in `from X import a`, else X or its longest known prefix. */
  resolve(imp: ImportLine, from?: string): string[] {
    return [...this.resolveNames(imp, from).keys()];
  }

  /**
   * The same files, each with the number of imported names it supplies: a named submodule counts
   * one, each other name counts one toward the module itself, and a bare `import X` counts one.
   */
  resolveNames(imp: ImportLine, from?: string): Map<string, number> {
    const out = new Map<string, number>();
    let rest = 0;
    for (const n of imp.names) {
      const sub = this.pick(`${imp.module}.${n}`, from);
      if (sub) out.set(sub, (out.get(sub) ?? 0) + 1);
      else rest++;
    }
    if (rest || !imp.names.length) {
      const parts = imp.module.split(".");
      for (let i = parts.length; i > 0; i--) {
        const p = this.pick(parts.slice(0, i).join("."), from);
        if (p) {
          out.set(p, (out.get(p) ?? 0) + Math.max(1, rest));
          break;
        }
      }
    }
    return out;
  }
}

/** Whether a path is in a tree the import graph leaves out. */
export function excludedPath(path: string): boolean {
  return EXCLUDED_TREES.some((t) => path.startsWith(t));
}

/**
 * Every tracked `.py` file in the checkout at `commit` that the graph covers: `lib/`, `experiments/`,
 * `scripts/`, `tests/`, `infra/` and the rest, less `EXCLUDED_TREES` and anything the clone's ignore
 * rules match (a force-added file).
 */
export async function graphFiles(repo: MarinRepo, commit: string): Promise<string[]> {
  const files = (await repo.lsTree(commit, ".")).filter((p) => p.endsWith(".py") && !excludedPath(p));
  const ignored = new Set(await repo.ignored(files));
  return files.filter((p) => !ignored.has(p));
}

export interface ImportGraph {
  index: ModuleIndex;
  /** Every file the graph covers. */
  files: string[];
  imports: Map<string, Set<string>>;
  importers: Map<string, Set<string>>;
  /** Imported names per edge: importer -> imported file -> count. */
  names: Map<string, Map<string, number>>;
}

/** Every import edge among the files `graphFiles` lists, from one `git grep`. */
export async function importGraph(repo: MarinRepo, commit: string): Promise<ImportGraph> {
  const files = await graphFiles(repo, commit);
  const covered = new Set(files);
  const index = new ModuleIndex(files);
  const hits = await repo.grep(commit, "^[[:space:]]*(from|import)[[:space:]]", ["*.py", ...EXCLUDED_TREES.map((t) => `:(exclude)${t}`)]);
  const imports = new Map<string, Set<string>>();
  const importers = new Map<string, Set<string>>();
  const names = new Map<string, Map<string, number>>();
  for (const h of hits) {
    if (!covered.has(h.path)) continue;
    const imp = parseImport(h.path, h.text);
    if (!imp) continue;
    for (const [target, n] of index.resolveNames(imp, h.path)) {
      if (target === h.path) continue;
      if (!imports.has(h.path)) imports.set(h.path, new Set());
      imports.get(h.path)!.add(target);
      if (!importers.has(target)) importers.set(target, new Set());
      importers.get(target)!.add(h.path);
      if (!names.has(h.path)) names.set(h.path, new Map());
      const m = names.get(h.path)!;
      m.set(target, (m.get(target) ?? 0) + n);
    }
  }
  return { index, files, imports, importers, names };
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
