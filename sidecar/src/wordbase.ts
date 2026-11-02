// Wordbase entries (DESIGN.md section 6): YAML front matter, then `## Symbols` with one
// `### \`name\`` subsection per symbol, then `## Notes` as a bullet list. Other `##` sections are
// kept verbatim after Notes.

import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { parse as parseYaml, stringify as stringifyYaml } from "yaml";

export type EntryKind = "file" | "system" | "pr" | "reviewer";

export interface FrontMatter {
  kind?: EntryKind | string;
  path?: string;
  commit?: string;
  updated?: string;
  by?: string;
  l1?: string;
  l2?: string;
  l3?: string[];
  system?: string;
  members?: unknown[];
  uses?: string[];
  used_by?: string[];
  diagram?: unknown;
  [key: string]: unknown;
}

export interface SymbolSection {
  name: string;
  /** Parsed `l1:` / `l2:` / `l3:` and any other keys. */
  fields: Record<string, unknown>;
  /** Set when the subsection body is not valid YAML; written back verbatim. */
  raw?: string;
}

export interface Note {
  /** Everything after the leading `- `, continuation lines joined with `\n`. */
  text: string;
  date?: string;
  commit?: string;
  session?: string;
  body?: string;
}

export interface Entry {
  front: FrontMatter;
  /** Body text before the first `##` heading. */
  preamble: string;
  symbols: SymbolSection[];
  notes: Note[];
  /** Other `##` sections, verbatim. */
  other: { heading: string; body: string }[];
}

const STRING_FIELDS = ["kind", "path", "commit", "updated", "by", "l1", "l2", "system", "deleted"] as const;
const SEP = " · ";

// ---------------------------------------------------------------------------
// Parse / write

export function parseEntry(text: string): Entry {
  const src = text.replace(/\r\n/g, "\n");
  let front: FrontMatter = {};
  let body = src;
  const m = /^---\n([\s\S]*?)\n---[ \t]*(?:\n|$)/.exec(src);
  if (m) {
    const parsed = parseYaml(m[1]!) as unknown;
    if (parsed !== null && parsed !== undefined) {
      if (typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("front matter is not a mapping");
      front = parsed as FrontMatter;
    }
    body = src.slice(m[0].length);
    for (const k of STRING_FIELDS) {
      const v = front[k];
      if (v !== undefined && v !== null && typeof v !== "string") front[k] = String(v);
    }
  }

  const entry: Entry = { front, preamble: "", symbols: [], notes: [], other: [] };
  const parts = splitSections(body, /^## (.+?)\s*$/);
  entry.preamble = parts.preamble.trim();
  for (const { heading, body: sectionBody } of parts.sections) {
    if (heading === "Symbols") entry.symbols.push(...parseSymbols(sectionBody));
    else if (heading === "Notes") entry.notes.push(...parseNotes(sectionBody));
    else entry.other.push({ heading, body: sectionBody.trim() });
  }
  return entry;
}

function splitSections(body: string, re: RegExp): { preamble: string; sections: { heading: string; body: string }[] } {
  const lines = body.split("\n");
  const sections: { heading: string; body: string[] }[] = [];
  const preamble: string[] = [];
  let inFence = false;
  for (const line of lines) {
    if (/^\s*(```|~~~)/.test(line)) inFence = !inFence;
    const h = inFence ? null : re.exec(line);
    if (h) sections.push({ heading: h[1]!, body: [] });
    else (sections.at(-1)?.body ?? preamble).push(line);
  }
  return {
    preamble: preamble.join("\n"),
    sections: sections.map((s) => ({ heading: s.heading, body: s.body.join("\n") })),
  };
}

function parseSymbols(body: string): SymbolSection[] {
  const { sections } = splitSections(body, /^### (.+?)\s*$/);
  return sections.map(({ heading, body: b }) => {
    const name = heading.replace(/^`(.*)`$/, "$1");
    const trimmed = b.trim();
    if (!trimmed) return { name, fields: {} };
    try {
      const parsed = parseYaml(trimmed) as unknown;
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        const fields = parsed as Record<string, unknown>;
        for (const k of ["l1", "l2"]) if (fields[k] !== undefined && typeof fields[k] !== "string") fields[k] = String(fields[k]);
        return { name, fields };
      }
    } catch {
      // fall through to raw
    }
    return { name, fields: {}, raw: trimmed };
  });
}

function parseNotes(body: string): Note[] {
  const notes: string[][] = [];
  for (const line of body.split("\n")) {
    if (/^[-*] /.test(line)) notes.push([line.slice(2)]);
    else if (notes.length && /^\s+\S/.test(line)) notes.at(-1)!.push(line.trim());
  }
  return notes.map((n) => parseNoteText(n.join("\n")));
}

export function parseNoteText(text: string): Note {
  const parts = text.split(SEP);
  const note: Note = { text };
  if (parts.length >= 4 && /^\d{4}-\d{2}-\d{2}$/.test(parts[0]!) && /^session /.test(parts[2]!)) {
    note.date = parts[0]!;
    note.commit = parts[1]!;
    note.session = parts[2]!.slice("session ".length);
    note.body = parts.slice(3).join(SEP);
  }
  return note;
}

export function formatNote(n: { date: string; commit: string; session: string; text: string }): Note {
  const session = n.session.length > 8 ? `${n.session.slice(0, 8)}…` : n.session;
  const text = [n.date, n.commit.slice(0, 7), `session ${session}`, n.text.replace(/\s*\n\s*/g, " ").trim()].join(SEP);
  return parseNoteText(text);
}

export function writeEntry(entry: Entry): string {
  const out: string[] = [];
  const front = stringifyYaml(entry.front, { lineWidth: 0 }).trimEnd();
  out.push("---", front === "{}" ? "" : front, "---", "");
  if (entry.preamble) out.push(entry.preamble, "");
  if (entry.symbols.length) {
    out.push("## Symbols", "");
    for (const s of entry.symbols) {
      out.push(`### \`${s.name}\``);
      if (s.raw !== undefined) out.push(s.raw);
      else if (Object.keys(s.fields).length) out.push(stringifyYaml(s.fields, { lineWidth: 0 }).trimEnd());
      out.push("");
    }
  }
  if (entry.notes.length) {
    out.push("## Notes", "");
    for (const n of entry.notes) {
      const [first, ...rest] = n.text.split("\n");
      out.push(`- ${first}`, ...rest.map((l) => `  ${l}`));
    }
    out.push("");
  }
  for (const o of entry.other) {
    out.push(`## ${o.heading}`, "");
    if (o.body) out.push(o.body, "");
  }
  return out.join("\n").replace(/\n+$/, "\n");
}

export function getSymbol(entry: Entry, name: string): SymbolSection | undefined {
  const want = name.replace(/^`(.*)`$/, "$1");
  return entry.symbols.find((s) => s.name === want) ?? entry.symbols.find((s) => s.name.split(".").at(-1) === want);
}

/** Render one symbol subsection on its own, the way it appears in the entry. */
export function renderSymbol(entryPath: string, s: SymbolSection): string {
  const body = s.raw ?? stringifyYaml(s.fields, { lineWidth: 0 }).trimEnd();
  return `${entryPath} · ### \`${s.name}\`\n${body}\n`;
}

// ---------------------------------------------------------------------------
// Paths

function cleanRelative(p: string, what: string): string {
  const norm = path.posix.normalize(p.replace(/\\/g, "/")).replace(/^\.\//, "");
  if (!norm || norm === "." || path.posix.isAbsolute(norm) || norm === ".." || norm.startsWith("../")) {
    throw new Error(`invalid ${what}: ${JSON.stringify(p)}`);
  }
  return norm.replace(/\/$/, "");
}

/** `lib/x/y.py` -> `<wordbase>/lib/x/y.py.md` */
export function fileEntryPath(wordbase: string, repoPath: string): string {
  return path.join(wordbase, `${cleanRelative(repoPath, "repo path")}.md`);
}

/** `shellbox` -> `<wordbase>/systems/shellbox.md`; nesting allowed (`iris/controller`). */
export function systemEntryPath(wordbase: string, system: string): string {
  return path.join(wordbase, "systems", `${cleanRelative(system, "system name")}.md`);
}

export function prDir(wordbase: string, pr: number): string {
  if (!Number.isInteger(pr) || pr <= 0) throw new Error(`invalid PR number: ${pr}`);
  return path.join(wordbase, "prs", String(pr));
}

export function reviewerEntryPath(wordbase: string): string {
  return path.join(wordbase, "reviewer.md");
}

export interface ResolvedTarget {
  file: string;
  kind: EntryKind;
  /** Repo path or system name, used to seed a new entry. */
  key: string;
  symbol?: string;
}

/**
 * Resolve a note target. Accepted forms: `system:<name>` or `systems/<name>`, `pr:<n>`,
 * `reviewer`, `<repo path>#<symbol>`, and a bare `<repo path>`.
 */
export function resolveTarget(wordbase: string, target: string): ResolvedTarget {
  const t = target.trim();
  if (t === "reviewer") return { file: reviewerEntryPath(wordbase), kind: "reviewer", key: "reviewer" };
  let m = /^(?:system:|systems\/)(.+?)(?:\.md)?$/.exec(t);
  if (m) return { file: systemEntryPath(wordbase, m[1]!), kind: "system", key: m[1]! };
  m = /^pr:(\d+)$/.exec(t);
  if (m) return { file: path.join(prDir(wordbase, Number(m[1])), "pr.md"), kind: "pr", key: m[1]! };
  const hash = t.lastIndexOf("#");
  const repoPath = hash > 0 ? t.slice(0, hash) : t;
  const symbol = hash > 0 ? t.slice(hash + 1).replace(/^`(.*)`$/, "$1") : undefined;
  return { file: fileEntryPath(wordbase, repoPath), kind: "file", key: cleanRelative(repoPath, "repo path"), ...(symbol ? { symbol } : {}) };
}

// ---------------------------------------------------------------------------
// File I/O

export async function readEntry(file: string): Promise<Entry | null> {
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw e;
  }
  return parseEntry(text);
}

export async function saveEntry(file: string, entry: Entry): Promise<void> {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, writeEntry(entry), "utf8");
}

/** Append a note to the target's entry, creating a stub entry when there is none. Returns the file. */
export async function appendNote(
  wordbase: string,
  target: string,
  note: { date: string; commit: string; session: string; text: string },
): Promise<string> {
  const r = resolveTarget(wordbase, target);
  const entry =
    (await readEntry(r.file)) ??
    ({
      front: r.kind === "file" ? { kind: "file", path: r.key } : r.kind === "system" ? { kind: "system", system: r.key } : { kind: r.kind },
      preamble: "",
      symbols: [],
      notes: [],
      other: [],
    } satisfies Entry);
  const text = r.symbol ? `\`${r.symbol}\`: ${note.text}` : note.text;
  entry.notes.push(formatNote({ ...note, text }));
  await saveEntry(r.file, entry);
  return r.file;
}

// ---------------------------------------------------------------------------
// Git

export type GitRunner = (args: string[]) => Promise<{ code: number; stdout: string; stderr: string }>;

export const runGit: GitRunner = (args) =>
  new Promise((resolve) => {
    execFile("git", args, { maxBuffer: 16 * 1024 * 1024 }, (err, stdout, stderr) => {
      const code = err ? (typeof (err as { code?: unknown }).code === "number" ? ((err as { code: number }).code) : 1) : 0;
      resolve({ code, stdout: String(stdout), stderr: String(stderr) });
    });
  });

/**
 * Stage `files` (absolute or wordbase-relative) and commit them in the wordbase repo with
 * `git -C <wordbase>`. Returns the new commit SHA, or null when nothing changed.
 */
export async function commitWordbase(wordbase: string, message: string, files: string[], git: GitRunner = runGit): Promise<string | null> {
  if (!existsSync(path.join(wordbase, ".git"))) {
    const init = await git(["-C", wordbase, "init", "-q"]);
    if (init.code !== 0) throw new Error(`git init in ${wordbase} failed: ${init.stderr.trim()}`);
  }
  const rel = files.map((f) => (path.isAbsolute(f) ? path.relative(wordbase, f) : f));
  for (const r of rel) if (r.startsWith("..")) throw new Error(`${r} is outside the wordbase`);
  if (!rel.length) return null;
  const add = await git(["-C", wordbase, "add", "--", ...rel]);
  if (add.code !== 0) throw new Error(`git add failed: ${add.stderr.trim()}`);
  const diff = await git(["-C", wordbase, "diff", "--cached", "--quiet", "--", ...rel]);
  if (diff.code === 0) return null;
  const commit = await git(["-C", wordbase, "commit", "-q", "-m", message, "--", ...rel]);
  if (commit.code !== 0) throw new Error(`git commit failed: ${commit.stderr.trim() || commit.stdout.trim()}`);
  const head = await git(["-C", wordbase, "rev-parse", "HEAD"]);
  return head.stdout.trim() || null;
}
