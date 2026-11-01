import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import {
  appendNote,
  commitWordbase,
  fileEntryPath,
  formatNote,
  getSymbol,
  parseEntry,
  prDir,
  readEntry,
  resolveTarget,
  reviewerEntryPath,
  systemEntryPath,
  writeEntry,
} from "./wordbase.js";

// The section 6 example, filled in.
const SAMPLE = `---
kind: file
path: lib/shellbox/src/shellbox/http_service.py
commit: 01a8bb8f0bea2dde1de90274ed695c25147b9f06
updated: 2026-11-01T16:40:00Z
by: claude-opus-5-5 prep 10640
l1: Runs a loopback HTTP listener inside a machine and relays each request over a process session to a handler on the host.
l2: Frames are newline-delimited JSON checked by strict Pydantic models on the host. \`_pump\` keeps up to 16 handler tasks in flight.
l3:
  - First paragraph, about the guest side.
  - Second paragraph, about the host side.
system: shellbox
---

## Symbols

### \`_pump\`
l1: Reads request frames and runs one handler task per frame, at most 16 at a time.
l2: It waits on FIRST_COMPLETED over the reader and the pending tasks, so a slow handler never blocks a fast one.

### \`_response\`
l1: Calls the handler under a 600 s wait_for and turns the outcome into a response frame.

## Notes

- 2026-11-01 · 01a8bb8 · session 3f2a… · The relay's failure behavior under a stuck model endpoint comes from three limits in http_service_guest.py.
- 2026-11-01 · 01a8bb8 · session 9c1d… · A second note
  that wraps onto a continuation line.
`;

const tmps: string[] = [];
function tmp(): string {
  const d = mkdtempSync(path.join(tmpdir(), "wordbase-test-"));
  tmps.push(d);
  return d;
}
afterEach(() => {
  for (const d of tmps.splice(0)) rmSync(d, { recursive: true, force: true });
});

describe("parseEntry", () => {
  const e = parseEntry(SAMPLE);

  it("reads the front matter", () => {
    expect(e.front.kind).toBe("file");
    expect(e.front.path).toBe("lib/shellbox/src/shellbox/http_service.py");
    expect(e.front.commit).toBe("01a8bb8f0bea2dde1de90274ed695c25147b9f06");
    expect(e.front.updated).toBe("2026-11-01T16:40:00Z");
    expect(e.front.l3).toEqual(["First paragraph, about the guest side.", "Second paragraph, about the host side."]);
    expect(e.front.system).toBe("shellbox");
  });

  it("reads symbols and notes", () => {
    expect(e.symbols.map((s) => s.name)).toEqual(["_pump", "_response"]);
    expect(getSymbol(e, "_pump")?.fields.l2).toMatch(/FIRST_COMPLETED/);
    expect(getSymbol(e, "`_response`")?.fields.l1).toMatch(/600 s/);
    expect(getSymbol(e, "missing")).toBeUndefined();
    expect(e.notes).toHaveLength(2);
    expect(e.notes[0]).toMatchObject({ date: "2026-11-01", commit: "01a8bb8", session: "3f2a…" });
    expect(e.notes[1]!.text).toBe("2026-11-01 · 01a8bb8 · session 9c1d… · A second note\nthat wraps onto a continuation line.");
  });

  it("round-trips", () => {
    const written = writeEntry(e);
    expect(parseEntry(written)).toEqual(e);
    expect(writeEntry(parseEntry(written))).toBe(written);
    // The sample is already in canonical form, so writing it reproduces it exactly.
    expect(written).toBe(SAMPLE);
  });

  it("keeps all-digit SHAs as strings and preserves unknown sections", () => {
    const x = parseEntry("---\nkind: file\ncommit: 1234567\n---\n\nIntro text.\n\n## Extra\n\nkept\n");
    expect(x.front.commit).toBe("1234567");
    expect(x.preamble).toBe("Intro text.");
    expect(x.other).toEqual([{ heading: "Extra", body: "kept" }]);
    expect(parseEntry(writeEntry(x))).toEqual(x);
    expect(writeEntry(x)).toContain("commit: \"1234567\"");
  });

  it("parses the workstream 0 fixture entries when present", () => {
    const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../wordbase/lib/shellbox/src/shellbox/http_service.py.md");
    let text: string;
    try {
      text = readFileSync(root, "utf8");
    } catch {
      return; // fixture not built on this machine
    }
    const f = parseEntry(text);
    expect(f.front.kind).toBe("file");
    expect(parseEntry(writeEntry(f))).toEqual(f);
  });
});

describe("paths", () => {
  const wb = "/w";
  it("maps repo paths, systems, PRs and the reviewer entry", () => {
    expect(fileEntryPath(wb, "lib/shellbox/src/shellbox/task.py")).toBe("/w/lib/shellbox/src/shellbox/task.py.md");
    expect(fileEntryPath(wb, "./lib/x.py")).toBe("/w/lib/x.py.md");
    expect(systemEntryPath(wb, "shellbox")).toBe("/w/systems/shellbox.md");
    expect(systemEntryPath(wb, "iris/controller")).toBe("/w/systems/iris/controller.md");
    expect(prDir(wb, 10640)).toBe("/w/prs/10640");
    expect(reviewerEntryPath(wb)).toBe("/w/reviewer.md");
  });
  it("refuses paths that escape the wordbase", () => {
    expect(() => fileEntryPath(wb, "../etc/passwd")).toThrow(/invalid repo path/);
    expect(() => fileEntryPath(wb, "/etc/passwd")).toThrow(/invalid repo path/);
    expect(() => systemEntryPath(wb, "a/../../b")).toThrow(/invalid system name/);
  });
  it("resolves note targets", () => {
    expect(resolveTarget(wb, "system:shellbox")).toMatchObject({ file: "/w/systems/shellbox.md", kind: "system" });
    expect(resolveTarget(wb, "systems/shellbox.md")).toMatchObject({ file: "/w/systems/shellbox.md", kind: "system" });
    expect(resolveTarget(wb, "pr:10640")).toMatchObject({ file: "/w/prs/10640/pr.md", kind: "pr" });
    expect(resolveTarget(wb, "reviewer")).toMatchObject({ file: "/w/reviewer.md" });
    expect(resolveTarget(wb, "lib/a.py#_pump")).toEqual({ file: "/w/lib/a.py.md", kind: "file", key: "lib/a.py", symbol: "_pump" });
  });
});

describe("notes and commits", () => {
  it("formats a note line", () => {
    const n = formatNote({ date: "2026-11-01", commit: "01a8bb8f0bea2dde", session: "3f2a9b7c-1111-2222-3333-444455556666", text: "Learned\nsomething." });
    expect(n.text).toBe("2026-11-01 · 01a8bb8 · session 3f2a9b7c… · Learned something.");
    expect(n.session).toBe("3f2a9b7c…");
  });

  it("appends to an existing entry, creates missing ones, and commits with git -C", async () => {
    const wb = tmp();
    execFileSync("git", ["-C", wb, "init", "-q"]);
    execFileSync("git", ["-C", wb, "config", "user.email", "test@example.com"]);
    execFileSync("git", ["-C", wb, "config", "user.name", "test"]);
    const file = fileEntryPath(wb, "lib/shellbox/src/shellbox/http_service.py");
    mkdirSync(path.dirname(file), { recursive: true });
    writeFileSync(file, SAMPLE);

    const note = { date: "2026-11-02", commit: "abcdef0123", session: "sess-1234567890", text: "Third note." };
    expect(await appendNote(wb, "lib/shellbox/src/shellbox/http_service.py#_pump", note)).toBe(file);
    const created = await appendNote(wb, "system:newsys", note);
    expect(created).toBe(path.join(wb, "systems/newsys.md"));

    const e = (await readEntry(file))!;
    expect(e.notes).toHaveLength(3);
    expect(e.notes[2]!.text).toBe("2026-11-02 · abcdef0 · session sess-123… · `_pump`: Third note.");
    expect(e.symbols).toHaveLength(2);
    const s = (await readEntry(created))!;
    expect(s.front).toEqual({ kind: "system", system: "newsys" });

    const sha = await commitWordbase(wb, "notes: session sess-1 (pr:10640)", [file, created]);
    expect(sha).toMatch(/^[0-9a-f]{40}$/);
    expect(execFileSync("git", ["-C", wb, "log", "-1", "--format=%s"]).toString().trim()).toBe("notes: session sess-1 (pr:10640)");
    expect(execFileSync("git", ["-C", wb, "show", "--name-only", "--format=", "HEAD"]).toString().trim().split("\n").sort()).toEqual([
      "lib/shellbox/src/shellbox/http_service.py.md",
      "systems/newsys.md",
    ]);
    // Nothing new: no empty commit.
    expect(await commitWordbase(wb, "again", [file])).toBeNull();
  });
});
