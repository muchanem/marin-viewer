import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { parseGaps, prepPolicy } from "./prepare.js";
import { checkerArgs, validatePrOutputs } from "./validate.js";

const dirs: string[] = [];
afterEach(() => {
  for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
});

describe("preparation permissions", () => {
  const out = "/wb/prs/10330";
  const check = "uv run --with pyyaml /v/prompts/check_fixture.py --wordbase /wb --marin /m --strict-boxes --pr 10330";
  const policy = prepPolicy({ outDir: out, checkCommand: check });
  const ask = async (tool: string, input: Record<string, unknown>) => (await policy(tool, input, { signal: new AbortController().signal, suggestions: [] } as never))!;

  it("writes only inside the PR's output directory", async () => {
    expect((await ask("Write", { file_path: "/wb/prs/10330/pr.md" })).behavior).toBe("allow");
    expect((await ask("Edit", { file_path: "/wb/prs/10330/code-path.json" })).behavior).toBe("allow");
    expect((await ask("Write", { file_path: "/wb/prs/10330/../10640/pr.md" })).behavior).toBe("deny");
    expect((await ask("Write", { file_path: "/wb/prs/103300/pr.md" })).behavior).toBe("deny");
    expect((await ask("Write", { file_path: "/m/lib/x.py" })).behavior).toBe("deny");
  });

  it("runs read-only Bash and the check command, and never gh", async () => {
    expect((await ask("Bash", { command: "git diff abc def --stat" })).behavior).toBe("allow");
    expect((await ask("Bash", { command: "rg -n TaskSpec lib/" })).behavior).toBe("allow");
    expect((await ask("Bash", { command: check })).behavior).toBe("allow");
    expect((await ask("Bash", { command: `${check} --strict` })).behavior).toBe("allow");
    expect((await ask("Bash", { command: `${check}; rm -rf /` })).behavior).toBe("deny");
    expect((await ask("Bash", { command: "gh pr view 10330" })).behavior).toBe("deny");
    expect((await ask("Bash", { command: "gh api -X POST repos/x/pulls/1/reviews" })).behavior).toBe("deny");
    expect((await ask("Bash", { command: "cd /m && git log" })).behavior).toBe("deny");
    expect((await ask("Bash", { command: "git push origin HEAD" })).behavior).toBe("deny");
  });

  it("reads, but starts no subagents and uses no viewer-only tools", async () => {
    expect((await ask("Read", { file_path: "/m/lib/x.py" })).behavior).toBe("allow");
    expect((await ask("Agent", {})).behavior).toBe("deny");
    expect((await ask("WebFetch", {})).behavior).toBe("deny");
    expect((await ask("mcp__viewer__wordbase_entry", {})).behavior).toBe("allow");
    expect((await ask("mcp__viewer__draft_review_note", {})).behavior).toBe("deny");
  });
});

describe("cold reader replies", () => {
  it("parses the gaps list", () => {
    expect(parseGaps('Checked.\n{"gaps": [{"where": "l2", "claim": "16 pending", "problem": "the limit is 32"}]}')).toEqual([{ where: "l2", claim: "16 pending", problem: "the limit is 32" }]);
    expect(parseGaps('{"gaps": []}')).toEqual([]);
    expect(() => parseGaps("nothing")).toThrow();
  });
});

const HEAD = "a".repeat(40);
const BASE = "b".repeat(40);

function writePr(dir: string, over: { pr?: string; steps?: unknown; diagrams?: unknown; notes?: string; files?: unknown } = {}) {
  mkdirSync(dir, { recursive: true });
  writeFileSync(
    path.join(dir, "pr.md"),
    over.pr ??
      `---\nkind: pr\nnumber: 7\ntitle: T\nauthor: x\nstate: OPEN\nhead: ${HEAD}\nbase: ${BASE}\nmerge_base: ${BASE}\nprepared_at: '2026-11-01T00:00:00Z'\nsession_id: s\ncommit: ${HEAD}\nupdated: '2026-11-01T00:00:00Z'\nby: claude-opus-5-5 prep 7\nl1: Callers can start a task.\nl2: The factory builds it.\n---\n`,
  );
  writeFileSync(path.join(dir, "code-path.json"), JSON.stringify(over.steps ?? [{ id: 1, title: "Start", l1: "Starts it.", node: "a", excerpts: [{ path: "lib/x.py", functions: ["f"], lines: [1, 3] }] }]));
  writeFileSync(path.join(dir, "diagrams.json"), JSON.stringify(over.diagrams ?? { pr: { layout: { mode: "auto" }, nodes: [{ id: "a", label: "f", sub: "starts", step: 1, at: { path: "lib/x.py", function: "f" }, paths: ["lib/x.py"] }], edges: [], groups: [] }, steps: {} }));
  writeFileSync(
    path.join(dir, "notes.jsonl"),
    over.notes ?? JSON.stringify({ id: "f1", path: "lib/x.py", line: 2, side: "head", commit: HEAD, severity: "low", status: "draft", who: "review session", l1: "The error is vague.", l2: "It says failed.", created: "t", updated: "t" }) + "\n",
  );
  writeFileSync(path.join(dir, "files.json"), JSON.stringify(over.files ?? { "lib/x.py": { l1: "Starts tasks." } }));
}

describe("PR output validation", () => {
  const tmp = () => {
    const d = mkdtempSync(path.join(tmpdir(), "pr-"));
    dirs.push(d);
    return path.join(d, "prs", "7");
  };

  it("accepts outputs in the section 6 shape", async () => {
    const dir = tmp();
    writePr(dir);
    const v = await validatePrOutputs(dir, { number: 7, head: HEAD });
    expect(v.problems).toEqual([]);
    expect(v.lint).toEqual([]);
    expect(v.counts).toEqual({ steps: 1, diagrams: 1, notes: 1, files: 1, boxes: 1 });
  });

  it("rejects the wrong head, missing files, too many boxes, grid overflow and boxes without paths", async () => {
    const dir = tmp();
    const nodes = Array.from({ length: 11 }, (_, i) => ({ id: `n${i}`, label: "x", sub: "y", grid: { col: i % 5, row: Math.floor(i / 5) }, ...(i === 0 ? { at: { path: "lib/x.py", function: "f" } } : {}) }));
    writePr(dir, { diagrams: { pr: { layout: { mode: "grid" }, nodes }, steps: { "9": { nodes: [{ id: "z", label: "z", sub: "z" }] } } } });
    rmSync(path.join(dir, "files.json"));
    const v = await validatePrOutputs(dir, { number: 7, head: "c".repeat(40) });
    const all = v.problems.join("\n");
    expect(all).toMatch(/head is aaaaaaaaaa, expected cccccccccc/);
    expect(all).toMatch(/files.json is missing/);
    expect(all).toMatch(/11 boxes; the limit is 10/);
    expect(all).toMatch(/runs past 4 columns by 3 rows/);
    expect(all).toMatch(/code anchors but no paths: n0/);
    expect(all).toMatch(/step diagram 9 has no step/);
  });

  it("rejects bad notes and lints every text field except Mark's own notes", async () => {
    const dir = tmp();
    const note = (who: string, l1: string) => JSON.stringify({ id: who, path: "lib/x.py", line: 2, side: "head", commit: HEAD, severity: "low", status: "draft", who, l1, created: "t", updated: "t" });
    writePr(dir, { notes: [note("review session", "It reaches the queue."), note("you", "This sees the queue — why?"), '{"id": "x", "severity": "huge"}'].join("\n") });
    const v = await validatePrOutputs(dir, { number: 7, head: HEAD });
    expect(v.problems.join("\n")).toMatch(/notes.jsonl line 3/);
    expect(v.lint).toEqual(['notes.jsonl review session l1: banned-word "reaches"']);
  });

  it("passes --pr and --strict-boxes to the checker", () => {
    expect(checkerArgs({ prompts: "/p", wordbase: "/w", marin: "/m", pr: 7 }).join(" ")).toBe("run --with pyyaml /p/check_fixture.py --wordbase /w --marin /m --strict-boxes --pr 7");
  });
});
