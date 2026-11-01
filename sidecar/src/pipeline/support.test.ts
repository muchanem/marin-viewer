import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { Gh } from "./exec.js";
import { fillTemplate } from "./prompts.js";
import { searchPrs } from "./prepare.js";
import { Ledger, paceUsd } from "./state.js";
import { workspaceDeps } from "./systems.js";
import { excerpt, findTranscripts, jobNames } from "./transcripts.js";

const dirs: string[] = [];
const tmp = (p: string) => {
  const d = mkdtempSync(path.join(tmpdir(), p));
  dirs.push(d);
  return d;
};
afterEach(() => {
  for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
});

describe("gh", () => {
  it("counts calls and turns a failed or empty call into an error", async () => {
    const gh = new Gh(async (args) => (args[0] === "bad" ? { code: 1, stdout: "", stderr: "HTTP 502" } : args[0] === "empty" ? { code: 0, stdout: "", stderr: "" } : { code: 0, stdout: "[]", stderr: "" }));
    await expect(gh.json(["bad"])).rejects.toThrow(/HTTP 502/);
    await expect(gh.json(["empty"])).rejects.toThrow(/no output/);
    expect(await gh.json(["ok"])).toEqual([]);
    expect(gh.calls).toBe(3);
  });

  it("searchPrs merges review requests and own PRs, and never turns an error into an empty list", async () => {
    const ok = new Gh(async (args) => ({
      code: 0,
      stderr: "",
      stdout: JSON.stringify(args.some((a) => a.startsWith("--review-requested")) ? [{ number: 5, title: "A", author: { login: "x" } }] : [{ number: 5, title: "A", author: { login: "x" } }, { number: 7, title: "B", author: { login: "muchanem" } }]),
    }));
    expect(await searchPrs(ok)).toEqual([
      { number: 5, title: "A", author: "x", reasons: ["review requested", "own PR"] },
      { number: 7, title: "B", author: "muchanem", reasons: ["own PR"] },
    ]);
    const failing = new Gh(async () => ({ code: 1, stdout: "", stderr: "API rate limit exceeded" }));
    await expect(searchPrs(failing)).rejects.toThrow(/rate limit/);
  });
});

describe("spending", () => {
  it("paces the monthly budget by elapsed time", () => {
    expect(paceUsd(300, new Date("2026-11-01T00:00:00Z"))).toBe(0);
    expect(paceUsd(300, new Date("2026-11-16T00:00:00Z"))).toBeCloseTo(150);
  });

  it("sums the ledger for the current month", async () => {
    const l = new Ledger(path.join(tmp("ledger-"), "spend.jsonl"));
    await l.add({ at: "2026-10-31T23:00:00Z", kind: "describe", run: "a", model: "m", cost_usd: 5 });
    await l.add({ at: "2026-11-01T01:00:00Z", kind: "prepare", run: "b", model: "m", cost_usd: 1.25 });
    expect(await l.monthToDate(new Date("2026-11-02T00:00:00Z"))).toBe(1.25);
  });
});

describe("templates", () => {
  it("strips the comment and fails on a placeholder without a value", () => {
    expect(fillTemplate("<!-- note {{x}} -->\nHello {{name}}", { name: "Mark" })).toBe("Hello Mark");
    expect(() => fillTemplate("{{missing}}", {})).toThrow(/missing/);
  });
});

describe("Mark's PR context", () => {
  it("excerpts user and assistant text and keeps the end of a long session", () => {
    const lines = [
      { type: "user", message: { role: "user", content: "Run the federation test on cw-us-east-02a." } },
      { type: "assistant", message: { role: "assistant", content: [{ type: "text", text: "Submitted /muchanem/fed-probe-3." }, { type: "tool_use", name: "Bash" }] } },
      { type: "user", message: { role: "user", content: "<command-name>/clear</command-name>" } },
      { type: "summary", summary: "x" },
    ].map((l) => JSON.stringify(l));
    expect(excerpt(lines.join("\n"), 10_000)).toBe("[user] Run the federation test on cw-us-east-02a.\n[assistant] Submitted /muchanem/fed-probe-3.");
    expect(excerpt(lines.join("\n"), 30)).toMatch(/^\.\.\. \(earlier turns cut\)\n/);
  });

  it("finds Iris job names", () => {
    expect(jobNames("ran /muchanem/glm53-relay-7 and then `iris job run --job-name fed-probe --no-wait`.")).toEqual(["/muchanem/glm53-relay-7", "/muchanem/fed-probe"]);
  });

  it("matches transcripts on gitBranch or a worktree cwd named after the branch", async () => {
    const root = tmp("projects-");
    mkdirSync(path.join(root, "p1"));
    mkdirSync(path.join(root, "p2"));
    writeFileSync(path.join(root, "p1", "a.jsonl"), JSON.stringify({ gitBranch: "mark/fed-routing", cwd: "/x" }) + "\n");
    writeFileSync(path.join(root, "p2", "b.jsonl"), JSON.stringify({ gitBranch: "main", cwd: "/Users/m/wt/fed-routing" }) + "\n");
    writeFileSync(path.join(root, "p2", "c.jsonl"), JSON.stringify({ gitBranch: "main", cwd: "/Users/m/wt/other" }) + "\n");
    expect((await findTranscripts("mark/fed-routing", root)).map((f) => path.basename(f)).sort()).toEqual(["a.jsonl", "b.jsonl"]);
    expect(await findTranscripts("mark/nothing", root)).toEqual([]);
  });
});

describe("subsystem dependencies", () => {
  it("reads workspace packages from pyproject dependency strings", () => {
    const py = `[project]\nname = "marin-shellbox"\ndependencies = [\n  "marin-iris>=0.1",\n  "pydantic>=2",\n  "rigging",\n  "fray[gpu]",\n]\n`;
    expect(workspaceDeps(py, ["iris", "rigging", "fray", "shellbox", "zephyr"])).toEqual(["fray", "iris", "rigging", "shellbox"]);
  });
});
