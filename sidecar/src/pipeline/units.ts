// Description units (DESIGN.md section 8, "Context for descriptions"). A unit is one directory of
// Python source files at one commit, or a slice of one. Its prompt holds, in full and within a token
// budget for the whole prompt: the unit's own files, the package README, the unit's tests, the
// subsystem page, the existing entries and the diff, then as many neighbouring modules (imported by
// the unit or importing it, anywhere in the checkout) as fit, chosen across packages.
//
// Test files are not units. Each test under `lib/` belongs to the source unit it imports the most
// names from; that unit carries it in every prompt and writes its one-sentence `l1`. Tests that
// import none of the described code go into orphan batches with no neighbour context.

import path from "node:path";
import { readFile } from "node:fs/promises";
import { fileEntryPath, readEntry, systemEntryPath, type Entry } from "../wordbase.js";
import { inputBlock, renderPrompt } from "./prompts.js";
import { contextPackage, importGraph, isTestPath, packageName, type ImportGraph, type MarinRepo } from "./repo.js";
import { countTokens, type TokenCounter } from "./tokens.js";

/** o200k tokens for the whole first prompt: template, style guide and every input block. */
export const PROMPT_BUDGET = 256_000;
/** A split unit's slices fill at most this share of the room left after the fixed blocks with their own files and tests. */
export const SLICE_FILL = 0.8;
/** Tokens held back for the TARGETS, TEST TARGETS and LEFT OUT blocks and the joins between blocks while planning. */
const PLAN_MARGIN = 4_000;
/** The LEFT OUT block names at most this many paths and counts the rest, so it stays near 1K tokens. */
export const LEFT_OUT_LISTED = 40;
const LEFT_OUT_RESERVE = 1_500;

export interface Unit {
  /** The directory, such as `lib/shellbox/src/shellbox`; for an orphan batch, the first test's directory. */
  dir: string;
  package: string;
  commit: string;
  /** A source directory (the default) or a batch of orphan tests. */
  kind?: "source" | "orphans";
  /** The unit's own source files (a slice's share of them), each given in full. */
  files: string[];
  /** The files the run writes full entries for; the rest of `files` are context. */
  targets: string[];
  /** The unit's own tests: always in the prompt, in full. */
  tests?: string[];
  /** The tests the run writes an `l1` for. */
  testTargets?: string[];
  /** Set on one slice of a directory too large for one prompt. */
  slice?: { index: number; of: number };
}

export const unitLabel = (u: Unit) => (u.kind === "orphans" ? `orphan tests from ${u.dir}` : u.slice ? `${u.dir} [${u.slice.index}/${u.slice.of}]` : u.dir);

/** Group paths into directory units. Targets are the given paths; `files` is filled in by `loadUnit`. */
export function groupByDirectory(paths: string[], commit: string): Unit[] {
  const byDir = new Map<string, string[]>();
  for (const p of paths) {
    const dir = path.posix.dirname(p);
    if (!byDir.has(dir)) byDir.set(dir, []);
    byDir.get(dir)!.push(p);
  }
  return [...byDir.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([dir, targets]) => ({ dir, package: packageName(dir), commit, files: [], targets: targets.sort() }));
}

/** Fill in the unit's files: every non-empty `.py` directly in its directory at its commit, tests aside unless `includeTests`. */
export async function loadUnit(repo: MarinRepo, unit: Unit, opts: { includeTests?: boolean } = {}): Promise<Unit> {
  const sizes = await repo.sizes(unit.commit, `${unit.dir}/`);
  const files = [...sizes.entries()]
    .filter(([p, n]) => p.endsWith(".py") && path.posix.dirname(p) === unit.dir && n > 0 && (opts.includeTests || !isTestPath(p)))
    .map(([p]) => p)
    .sort();
  const targets = unit.targets.filter((t) => files.includes(t));
  return { ...unit, files, targets };
}

// ---------------------------------------------------------------------------
// Choosing and packing (pure, so the rules can be tested without a repository)

export interface Candidate {
  path: string;
  tokens: number;
  /** `contextPackage` of the path: a `lib/` package, or `experiments`, `scripts`, `tests`, ... */
  package: string;
  test: boolean;
  /** Imported names between the candidate and the unit, both directions. */
  score: number;
  /** How the candidate relates to the unit, for its block heading. */
  relation: string;
}

/**
 * The order neighbours are offered to the budget: non-test code before test code; within each,
 * round-robin over packages, the unit's own package first and then by each package's best score;
 * within a package by score, then smaller first, then path.
 */
export function diversityOrder<T extends Candidate>(cands: T[], home: string): T[] {
  const out: T[] = [];
  for (const test of [false, true]) {
    const groups = new Map<string, T[]>();
    for (const c of cands) {
      if (c.test !== test) continue;
      if (!groups.has(c.package)) groups.set(c.package, []);
      groups.get(c.package)!.push(c);
    }
    for (const g of groups.values()) g.sort((a, b) => b.score - a.score || a.tokens - b.tokens || a.path.localeCompare(b.path));
    const order = [...groups.keys()].sort((a, b) => Number(b === home) - Number(a === home) || groups.get(b)![0]!.score - groups.get(a)![0]!.score || a.localeCompare(b));
    for (let i = 0, more = true; more; i++) {
      more = false;
      for (const k of order) {
        const g = groups.get(k)!;
        if (i < g.length) {
          out.push(g[i]!);
          more = true;
        }
      }
    }
  }
  return out;
}

/** Take candidates in order while they fit `room`; one that does not fit is left out and the next is tried. */
export function fillBudget<T extends { tokens: number }>(room: number, ordered: T[]): { included: T[]; dropped: T[]; used: number } {
  const included: T[] = [];
  const dropped: T[] = [];
  let used = 0;
  for (const c of ordered) {
    if (used + c.tokens <= room) {
      included.push(c);
      used += c.tokens;
    } else dropped.push(c);
  }
  return { included, dropped, used };
}

/**
 * Cut a directory's files into slices of about equal size, each at most `capacity` tokens (a file's
 * cost includes the tests it carries). Files go, in path order, into the first slice with room, so
 * a large file between small ones does not strand them; each slice lists its files in path order.
 * A file over `capacity` gets a slice alone.
 */
export function planSlices(items: { path: string; tokens: number }[], capacity: number): string[][] {
  const sorted = [...items].sort((a, b) => a.path.localeCompare(b.path));
  const total = sorted.reduce((a, i) => a + i.tokens, 0);
  if (total <= capacity) return [sorted.map((i) => i.path)];
  const pack = (cap: number) => {
    const slices: { paths: string[]; used: number }[] = [];
    for (const i of sorted) {
      const s = slices.find((x) => x.used + i.tokens <= cap);
      if (s) {
        s.paths.push(i.path);
        s.used += i.tokens;
      } else slices.push({ paths: [i.path], used: i.tokens });
    }
    return slices.map((s) => s.paths);
  };
  const k = Math.ceil(total / capacity);
  for (const slack of [1.02, 1.05, 1.1, 1.2, 1.35]) {
    const cap = Math.min(capacity, (total / k) * slack);
    const s = pack(cap);
    if (s.length <= k) return s;
  }
  return pack(capacity);
}

/**
 * The owner of each test: the source directory it imports the most names from, ties going to the
 * test's own package and then to the first directory by path. `null` marks an orphan.
 */
export function assignOwners(tests: string[], names: Map<string, Map<string, number>>, dirOf: Map<string, string>): Map<string, string | null> {
  const owners = new Map<string, string | null>();
  for (const t of tests) {
    const w = new Map<string, number>();
    for (const [target, n] of names.get(t) ?? []) {
      const d = dirOf.get(target);
      if (d) w.set(d, (w.get(d) ?? 0) + n);
    }
    const home = contextPackage(t);
    const best = [...w].sort((a, b) => b[1] - a[1] || Number(contextPackage(b[0]) === home) - Number(contextPackage(a[0]) === home) || a[0].localeCompare(b[0]))[0];
    owners.set(t, best ? best[0] : null);
  }
  return owners;
}

/** Pack orphan tests into batches by directory, in path order, each within `room` tokens. */
export function packOrphans(tests: { path: string; tokens: number }[], room: number): string[][] {
  const sorted = [...tests].sort((a, b) => path.posix.dirname(a.path).localeCompare(path.posix.dirname(b.path)) || a.path.localeCompare(b.path));
  const batches: string[][] = [];
  let cur: string[] = [];
  let used = 0;
  for (const t of sorted) {
    if (cur.length && used + t.tokens > room) {
      batches.push(cur);
      cur = [];
      used = 0;
    }
    cur.push(t.path);
    used += t.tokens;
  }
  if (cur.length) batches.push(cur);
  return batches;
}

// ---------------------------------------------------------------------------
// Building prompts from a repository

export interface ContextStats {
  /** o200k tokens of the whole first prompt. */
  tokens: number;
  budget: number;
  chars: number;
  sourceTokens: number;
  /** Test files in the prompt, the unit's own first. */
  tests: string[];
  /** Tests that import the unit but did not fit. */
  testsDropped: string[];
  neighbours: string[];
  neighboursDropped: string[];
  /** Tests and neighbours in the prompt from outside `lib/`. */
  outsideLib: string[];
  /** The fixed part alone passes the budget (a single file too large for one prompt). */
  overBudget: boolean;
}

export interface UnitContext {
  unit: Unit;
  /** The rendered `prompts/describe-unit.md`, style guide included (rendered on use when absent). */
  header?: string;
  /** The rendered input blocks that follow it. */
  inputs: string;
  stats: ContextStats;
  existing: Map<string, Entry>;
}

export interface BuilderOptions {
  wordbase: string;
  prompts: string;
  budget?: number;
  tokens?: TokenCounter;
  /** Leave EXISTING empty, as on a first pass (the model comparison does this). */
  ignoreExisting?: boolean;
  /**
   * Which tests a source unit must carry: `owned` (the tests it owns; the rule since 2026-11-02) or
   * `all` (every test that imports it, as when test directories were units of their own).
   */
  mandatoryTests?: "owned" | "all";
}

export interface PlannedUnit {
  /** The unit, or its slices. */
  units: Unit[];
  /** Owned tests that do not fit even beside a single file; they go to an orphan batch. */
  overflow: string[];
}

const block = inputBlock;

async function readText(file: string): Promise<string | null> {
  try {
    return await readFile(file, "utf8");
  } catch {
    return null;
  }
}

export function unitKind(u: Unit): string {
  if (u.kind === "orphans") return "a batch of test files that import none of the described code, with no source files and no neighbours";
  if (u.slice) return `slice ${u.slice.index} of ${u.slice.of} of a directory too large for one prompt; the other slices' files appear as neighbours when they fit`;
  return "a single directory";
}

export class ContextBuilder {
  readonly budget: number;
  private readonly count: TokenCounter;
  private graphP: Promise<ImportGraph> | null = null;
  private tokenCache = new Map<string, number>();
  private ownersCache: Map<string, string | null> | null = null;
  private dirsCache: Map<string, string[]> | null = null;

  constructor(
    readonly repo: MarinRepo,
    readonly commit: string,
    readonly opts: BuilderOptions,
  ) {
    this.budget = opts.budget ?? PROMPT_BUDGET;
    this.count = opts.tokens ?? countTokens;
  }

  graph(): Promise<ImportGraph> {
    this.graphP ??= importGraph(this.repo, this.commit);
    return this.graphP;
  }

  async text(p: string): Promise<string> {
    return (await this.repo.show(this.commit, p)) ?? "";
  }

  /** o200k tokens of a file's SOURCE/TEST/NEIGHBOUR block body. */
  async fileTokens(p: string): Promise<number> {
    if (!this.tokenCache.has(p)) this.tokenCache.set(p, this.count(await this.text(p)));
    return this.tokenCache.get(p)!;
  }

  /** Every directory under `lib/` with non-empty source files, and the files. */
  async sourceDirs(): Promise<Map<string, string[]>> {
    if (this.dirsCache) return this.dirsCache;
    const g = await this.graph();
    const sizes = await this.repo.sizes(this.commit, "lib/");
    const dirs = new Map<string, string[]>();
    for (const p of g.files) {
      if (!p.startsWith("lib/") || isTestPath(p) || !(sizes.get(p) ?? 0)) continue;
      const d = path.posix.dirname(p);
      if (!dirs.has(d)) dirs.set(d, []);
      dirs.get(d)!.push(p);
    }
    for (const l of dirs.values()) l.sort();
    this.dirsCache = dirs;
    return dirs;
  }

  /** Non-empty test files under `lib/`: the ones the wordbase describes. */
  async libTests(): Promise<string[]> {
    const g = await this.graph();
    const sizes = await this.repo.sizes(this.commit, "lib/");
    return g.files.filter((p) => p.startsWith("lib/") && isTestPath(p) && (sizes.get(p) ?? 0) > 0).sort();
  }

  async owners(): Promise<Map<string, string | null>> {
    if (this.ownersCache) return this.ownersCache;
    const dirs = await this.sourceDirs();
    const dirOf = new Map<string, string>();
    for (const [d, files] of dirs) for (const f of files) dirOf.set(f, d);
    this.ownersCache = assignOwners(await this.libTests(), (await this.graph()).names, dirOf);
    return this.ownersCache;
  }

  /** The file of `files` a test imports the most names from (the first by path on a tie). */
  private async primaryFile(test: string, files: string[]): Promise<string | null> {
    const n = (await this.graph()).names.get(test);
    let best: string | null = null;
    let most = 0;
    for (const f of files) {
      const c = n?.get(f) ?? 0;
      if (c > most) {
        best = f;
        most = c;
      }
    }
    return best;
  }

  /** Tests anywhere in the checkout that import one of `files`, outside `files`. */
  private async importingTests(files: string[]): Promise<Set<string>> {
    const g = await this.graph();
    const inUnit = new Set(files);
    const out = new Set<string>();
    for (const f of files) for (const s of g.importers.get(f) ?? []) if (isTestPath(s) && !inUnit.has(s)) out.add(s);
    return out;
  }

  private async header(u: Unit): Promise<string> {
    return renderPrompt(this.opts.prompts, "describe-unit.md", { unit: u.dir, commit: u.commit, package: u.package, unit_kind: unitKind(u) });
  }

  private async readme(u: Unit): Promise<string> {
    if (u.kind === "orphans") return "none";
    return (await this.repo.show(this.commit, `lib/${u.package}/README.md`)) ?? "none";
  }

  /**
   * Attach the unit's own tests and split it when its files and those tests pass the budget. A
   * source unit's `targets` and `testTargets` are spread over the slices that hold them.
   */
  async plan(unit: Unit): Promise<PlannedUnit> {
    const isTestDir = unit.files.length > 0 && unit.files.every(isTestPath);
    let tests: string[] = [];
    if (!isTestDir) {
      if ((this.opts.mandatoryTests ?? "owned") === "all") tests = [...(await this.importingTests(unit.files))].sort();
      else {
        const owners = await this.owners();
        tests = [...owners].filter(([, d]) => d === unit.dir).map(([t]) => t).sort();
      }
    }
    const testTargets = (unit.testTargets ?? []).filter((t) => tests.includes(t));
    const fixed =
      this.count(await this.header({ ...unit, slice: { index: 1, of: 2 } })) +
      this.count(block("README", await this.readme(unit))) +
      this.count(block("SUBSYSTEM", (await readText(systemEntryPath(this.opts.wordbase, unit.package))) ?? "none")) +
      PLAN_MARGIN;
    const room = this.budget - fixed;
    // Each test rides with the file it imports the most names from.
    const carried = new Map<string, string[]>();
    for (const t of tests) {
      const f = (await this.primaryFile(t, unit.files)) ?? unit.files[0]!;
      if (!carried.has(f)) carried.set(f, []);
      carried.get(f)!.push(t);
    }
    const items: { path: string; tokens: number }[] = [];
    for (const f of unit.files) {
      let n = (await this.fileTokens(f)) + 64;
      for (const t of carried.get(f) ?? []) n += (await this.fileTokens(t)) + 64;
      items.push({ path: f, tokens: n });
    }
    const total = items.reduce((a, i) => a + i.tokens, 0);
    const groups = total <= room ? [unit.files] : planSlices(items, room * SLICE_FILL);
    const overflow: string[] = [];
    const units: Unit[] = [];
    for (const [i, files] of groups.entries()) {
      let sliceTests = files.flatMap((f) => carried.get(f) ?? []);
      let own = 0;
      for (const f of files) own += (await this.fileTokens(f)) + 64;
      let testTok = 0;
      for (const t of sliceTests) testTok += (await this.fileTokens(t)) + 64;
      if (own + testTok > room) {
        // Keep the tests that lean on the slice most, as many as fit; the rest are not this slice's to carry.
        const g = await this.graph();
        const scored = [];
        for (const t of sliceTests) scored.push({ path: t, tokens: (await this.fileTokens(t)) + 64, score: files.reduce((a, f) => a + (g.names.get(t)?.get(f) ?? 0), 0) });
        scored.sort((a, b) => b.score - a.score || a.tokens - b.tokens || a.path.localeCompare(b.path));
        const fit = fillBudget(Math.max(0, room - own), scored);
        sliceTests = fit.included.map((c) => c.path);
        overflow.push(...fit.dropped.map((c) => c.path));
      }
      sliceTests.sort();
      units.push({
        ...unit,
        files,
        targets: unit.targets.filter((t) => files.includes(t)),
        tests: sliceTests,
        testTargets: testTargets.filter((t) => sliceTests.includes(t)),
        ...(groups.length > 1 ? { slice: { index: i + 1, of: groups.length } } : {}),
      });
    }
    return { units, overflow };
  }

  /** Orphan batches for `tests`, by directory, as many per batch as fit; each test is a target. */
  async orphanBatches(tests: string[]): Promise<Unit[]> {
    if (!tests.length) return [];
    const probe: Unit = { dir: path.posix.dirname(tests[0]!), package: packageName(tests[0]!), commit: this.commit, kind: "orphans", files: [], targets: [] };
    const room = this.budget - this.count(await this.header(probe)) - PLAN_MARGIN;
    const sized = [];
    for (const t of tests) sized.push({ path: t, tokens: (await this.fileTokens(t)) + 64 + 40 });
    return packOrphans(sized, room).map((batch) => ({
      dir: path.posix.dirname(batch[0]!),
      package: packageName(batch[0]!),
      commit: this.commit,
      kind: "orphans" as const,
      files: [],
      targets: [],
      tests: batch,
      testTargets: batch,
    }));
  }

  /** The prompt for one planned unit or slice. `diffFrom` is set on a regeneration. */
  async build(unit: Unit, opts: { diffFrom?: string | null; siblings?: string[] } = {}): Promise<UnitContext> {
    const g = await this.graph();
    const header = await this.header(unit);
    const fixed: string[] = [];
    let sourceTokens = 0;
    for (const f of unit.files) {
      fixed.push(block(`SOURCE ${f}`, await this.text(f)));
      sourceTokens += await this.fileTokens(f);
    }
    fixed.push(block("README", await this.readme(unit)));
    const ownTests = unit.tests ?? [];
    const testBlocks: string[] = [];
    for (const t of ownTests) testBlocks.push(block(`TEST ${t}${unit.kind === "orphans" ? "" : " (one of the unit's own tests)"}`, await this.text(t)));

    const tail: string[] = [];
    tail.push(block("SUBSYSTEM", unit.kind === "orphans" ? "none" : ((await readText(systemEntryPath(this.opts.wordbase, unit.package))) ?? "none")));
    const existing = new Map<string, Entry>();
    const existingText: string[] = [];
    const testTargets = unit.testTargets ?? [];
    for (const f of [...unit.files, ...testTargets]) {
      const e = this.opts.ignoreExisting ? null : await readEntry(fileEntryPath(this.opts.wordbase, f)).catch(() => null);
      if (!e || e.front.deleted) continue;
      existing.set(f, e);
      const lines = [`### ${f}`, `commit: ${e.front.commit ?? "unknown"}`, `l1: ${e.front.l1 ?? ""}`];
      if (!isTestPath(f)) {
        if (e.front.l2) lines.push(`l2: ${e.front.l2}`);
        for (const p of e.front.l3 ?? []) lines.push(`l3: ${p}`);
        for (const s of e.symbols) lines.push(`symbol ${s.name}: ${String(s.fields.l1 ?? s.raw ?? "")}`);
      }
      existingText.push(lines.join("\n"));
    }
    tail.push(block("EXISTING", existingText.length ? existingText.join("\n\n") : "none"));
    let diff = "none";
    const changed = [...unit.targets, ...testTargets];
    if (opts.diffFrom !== undefined && opts.diffFrom !== null && changed.length) {
      const d = await this.repo.diff(opts.diffFrom, unit.commit, changed).catch(() => "");
      if (d.trim()) diff = d;
    }
    tail.push(block("DIFF", diff));
    const targetBlocks = [block("TARGETS", unit.targets.join("\n") || "none"), block("TEST TARGETS", testTargets.join("\n") || "none")];

    const fixedTokens = this.count(header) + [...fixed, ...testBlocks, ...tail, ...targetBlocks].reduce((a, b) => a + this.count(b), 0);
    let room = this.budget - fixedTokens - LEFT_OUT_RESERVE; // the exact count below settles the rest

    // Optional tests: the other tests that import the unit, ahead of every neighbour.
    const inPrompt = new Set([...unit.files, ...ownTests]);
    const score = (p: string) => unit.files.reduce((a, f) => a + (g.names.get(p)?.get(f) ?? 0) + (g.names.get(f)?.get(p) ?? 0), 0);
    const testCands: Candidate[] = [];
    const neighbourCands: Candidate[] = [];
    if (unit.kind !== "orphans") {
      const isTestDir = unit.files.length > 0 && unit.files.every(isTestPath);
      const imported = new Set<string>();
      const importing = new Set<string>();
      for (const f of unit.files) {
        for (const t of g.imports.get(f) ?? []) if (!inPrompt.has(t)) imported.add(t);
        for (const s of g.importers.get(f) ?? []) if (!inPrompt.has(s)) importing.add(s);
      }
      const siblings = new Set((opts.siblings ?? []).filter((s) => !inPrompt.has(s)));
      const all = new Set([...imported, ...importing, ...siblings]);
      for (const p of all) {
        const test = isTestPath(p);
        const rel = siblings.has(p) ? "a file of this directory in another slice" : imported.has(p) && importing.has(p) ? "imported by the unit and imports it" : imported.has(p) ? "imported by the unit" : "imports the unit";
        const c: Candidate = { path: p, tokens: (await this.fileTokens(p)) + 40, package: contextPackage(p), test, score: score(p) + (siblings.has(p) ? 1000 : 0), relation: rel };
        if (test && importing.has(p) && !isTestDir) testCands.push(c);
        else neighbourCands.push(c);
      }
    }
    const home = contextPackage(unit.dir);
    const testFill = fillBudget(room, diversityOrder(testCands, home));
    room -= testFill.used;
    const nFill = fillBudget(room, diversityOrder(neighbourCands, home));
    const tests = [...testFill.included];
    const neighbours = [...nFill.included];
    const droppedTests = [...testFill.dropped];
    const droppedNeighbours = [...nFill.dropped];

    const assemble = async () => {
      const parts = [...fixed, ...testBlocks];
      for (const c of tests) parts.push(block(`TEST ${c.path} (imports the unit)`, await this.text(c.path)));
      for (const c of neighbours) parts.push(block(`NEIGHBOUR ${c.path} (${c.relation})`, await this.text(c.path)));
      parts.push(...tail);
      const left = [...droppedTests, ...droppedNeighbours].map((c) => `${c.path} (${c.test && testCands.includes(c) ? "a test that imports the unit" : c.relation})`);
      const listed = left.slice(0, LEFT_OUT_LISTED);
      const more = left.length - listed.length;
      parts.push(block("LEFT OUT", left.length ? `${left.length} related modules did not fit the prompt and are not shown:\n${listed.join("\n")}${more ? `\n... and ${more} more` : ""}` : "none"));
      parts.push(...targetBlocks);
      return parts.join("\n");
    };
    let inputs = await assemble();
    let tokens = this.count(`${header}\n\n${inputs}`);
    // The exact count decides: drop the last neighbour, then the last optional test, until it fits.
    while (tokens > this.budget && (neighbours.length || tests.length)) {
      if (neighbours.length) droppedNeighbours.unshift(neighbours.pop()!);
      else droppedTests.unshift(tests.pop()!);
      inputs = await assemble();
      tokens = this.count(`${header}\n\n${inputs}`);
    }
    const shown = [...ownTests, ...tests.map((c) => c.path), ...neighbours.map((c) => c.path)];
    return {
      unit,
      header,
      inputs,
      existing,
      stats: {
        tokens,
        budget: this.budget,
        chars: header.length + 2 + inputs.length,
        sourceTokens,
        tests: [...ownTests, ...tests.map((c) => c.path)],
        testsDropped: droppedTests.map((c) => c.path),
        neighbours: neighbours.map((c) => c.path),
        neighboursDropped: droppedNeighbours.map((c) => c.path),
        outsideLib: shown.filter((p) => !p.startsWith("lib/")),
        overBudget: tokens > this.budget,
      },
    };
  }

  /** Plan and build every slice of `unit` that has something to write. */
  async contexts(unit: Unit, opts: { diffFrom?: string | null } = {}): Promise<{ contexts: UnitContext[]; overflow: string[] }> {
    const planned = await this.plan(unit);
    const out: UnitContext[] = [];
    for (const u of planned.units) {
      if (!u.targets.length && !(u.testTargets ?? []).length) continue;
      const siblings = planned.units.length > 1 ? unit.files.filter((f) => !u.files.includes(f)) : [];
      out.push(await this.build(u, { ...opts, siblings }));
    }
    return { contexts: out, overflow: planned.overflow };
  }
}

/** One line on what a context holds and what it left out, for logs. */
export function describeStats(s: ContextStats): string {
  const left = [...s.testsDropped, ...s.neighboursDropped];
  return `${s.tokens} tokens of ${s.budget}${s.overBudget ? " (OVER BUDGET)" : ""}, ${s.tests.length} tests, ${s.neighbours.length} neighbours, ${s.outsideLib.length} from outside lib/, left out ${left.length}${left.length ? `: ${left.slice(0, 8).join(", ")}${left.length > 8 ? `, +${left.length - 8}` : ""}` : ""}`;
}
