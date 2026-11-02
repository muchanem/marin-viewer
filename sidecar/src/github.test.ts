import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { buildReviewRequest, noteBody, postReview, recordPosted, type GhRunner } from "./github.js";
import type { PostNote } from "./protocol.js";

const SHA = "01a8bb8f0bea2dde1de90274ed695c25147b9f06";
const base = { commit: SHA, severity: "medium", status: "approved", who: "review session", created: "2026-10-30T00:00:00Z", updated: "2026-10-30T00:00:00Z" } as const;
const notes: PostNote[] = [
  { ...base, id: "f1", path: "lib/shellbox/src/shellbox/http_service.py", line: 133, side: "head", l1: "Retry after a 504 can exceed the 16-slot limit.", l2: "The guest frees its slot first." },
  { ...base, id: "f2", path: "lib/shellbox/src/shellbox/task.py", line: 120, side: "base", l1: "Bare StopIteration.", body: "Exact text from the confirm box." },
];

interface Call {
  args: string[];
  input: unknown;
}

function fakeGh(responses: ((c: Call) => { code?: number; stdout?: unknown; stderr?: string })[]): { gh: GhRunner; calls: Call[] } {
  const calls: Call[] = [];
  const gh: GhRunner = async (args, input) => {
    const call = { args, input: input === undefined ? undefined : JSON.parse(input) };
    calls.push(call);
    const next = responses.shift();
    if (!next) throw new Error(`unexpected gh call ${args.join(" ")}`);
    const r = next(call);
    return { code: r.code ?? 0, stdout: r.stdout === undefined ? "" : typeof r.stdout === "string" ? r.stdout : JSON.stringify(r.stdout), stderr: r.stderr ?? "" };
  };
  return { gh, calls };
}

describe("buildReviewRequest", () => {
  it("creates a pending review with one inline comment per note", () => {
    const r = buildReviewRequest(10640, notes);
    expect(r).toEqual({
      endpoint: "repos/marin-community/marin/pulls/10640/reviews",
      payload: {
        commit_id: SHA,
        comments: [
          { path: "lib/shellbox/src/shellbox/http_service.py", line: 133, side: "RIGHT", body: "Retry after a 504 can exceed the 16-slot limit.\n\nThe guest frees its slot first." },
          { path: "lib/shellbox/src/shellbox/task.py", line: 120, side: "LEFT", body: "Exact text from the confirm box." },
        ],
      },
    });
    expect("event" in r.payload).toBe(false); // no event: GitHub keeps it PENDING
  });

  it("refuses unapproved notes and mixed commits", () => {
    expect(() => buildReviewRequest(1, [{ ...notes[0]!, status: "draft" }])).toThrow(/only approved notes.*f1 \(draft\)/);
    expect(() => buildReviewRequest(1, [notes[0]!, { ...notes[1]!, commit: "ffffffff" }])).toThrow(/several commits/);
    expect(() => buildReviewRequest(1, [])).toThrow(/at least one/);
  });

  it("uses the layered text when there is no confirmed body", () => {
    expect(noteBody({ l1: "One." })).toBe("One.");
  });
});

describe("postReview", () => {
  it("creates, submits, then lists comments to map ids", async () => {
    const { gh, calls } = fakeGh([
      () => ({ stdout: { id: 991, state: "PENDING", html_url: "https://github.com/marin-community/marin/pull/10640#pullrequestreview-991" } }),
      () => ({ stdout: { id: 991, state: "COMMENTED" } }),
      () => ({
        stdout: [
          { id: 5002, path: "lib/shellbox/src/shellbox/task.py", line: null, original_line: 120, side: "LEFT", body: "Exact text from the confirm box." },
          { id: 5001, path: "lib/shellbox/src/shellbox/http_service.py", line: 133, side: "RIGHT", body: "Retry after a 504 can exceed the 16-slot limit.\n\nThe guest frees its slot first." },
        ],
      }),
    ]);
    const r = await postReview({ pr: 10640, notes, gh, body: "Two notes." });
    expect(calls.map((c) => c.args)).toEqual([
      ["api", "--method", "POST", "repos/marin-community/marin/pulls/10640/reviews", "--input", "-"],
      ["api", "--method", "POST", "repos/marin-community/marin/pulls/10640/reviews/991/events", "--input", "-"],
      ["api", "--method", "GET", "repos/marin-community/marin/pulls/10640/reviews/991/comments?per_page=100"],
    ]);
    expect(calls[0]!.input).toEqual(buildReviewRequest(10640, notes).payload);
    expect(calls[1]!.input).toEqual({ event: "COMMENT", body: "Two notes." });
    expect(calls[2]!.input).toBeUndefined();
    expect(r).toEqual({
      review_id: 991,
      html_url: "https://github.com/marin-community/marin/pull/10640#pullrequestreview-991",
      comments: [
        { note_id: "f1", github_comment_id: 5001 },
        { note_id: "f2", github_comment_id: 5002 },
      ],
    });
  });

  it("targets another repo when asked", async () => {
    const { gh, calls } = fakeGh([() => ({ stdout: { id: 1 } }), () => ({ stdout: {} }), () => ({ stdout: [] })]);
    await postReview({ pr: 3, notes: [notes[0]!], repo: "muchanem/marin-viewer", gh });
    expect(calls[0]!.args[3]).toBe("repos/muchanem/marin-viewer/pulls/3/reviews");
    expect(calls[1]!.input).toEqual({ event: "COMMENT" });
  });

  it("surfaces gh errors and deletes the pending review when submit fails", async () => {
    const { gh, calls } = fakeGh([() => ({ stdout: { id: 77 } }), () => ({ code: 1, stderr: "HTTP 422: Validation Failed" }), () => ({ stdout: "" })]);
    await expect(postReview({ pr: 10640, notes, gh })).rejects.toThrow(/submitting review 77 failed, pending review deleted: .*422/);
    expect(calls[2]!.args).toEqual(["api", "--method", "DELETE", "repos/marin-community/marin/pulls/10640/reviews/77"]);

    const second = fakeGh([() => ({ code: 1, stderr: "HTTP 422: User can only have one pending review per pull request" })]);
    await expect(postReview({ pr: 10640, notes, gh: second.gh })).rejects.toThrow(/one pending review/);
    expect(second.calls).toHaveLength(1);
  });

  it("never calls gh for invalid notes", async () => {
    const { gh, calls } = fakeGh([]);
    await expect(postReview({ pr: 1, notes: [{ ...notes[0]!, status: "rejected" }], gh })).rejects.toThrow(/only approved/);
    expect(calls).toHaveLength(0);
  });
});

describe("recordPosted", () => {
  it("marks posted notes in notes.jsonl", async () => {
    const wb = mkdtempSync(path.join(tmpdir(), "wb-post-"));
    try {
      mkdirSync(path.join(wb, "prs/10640"), { recursive: true });
      const file = path.join(wb, "prs/10640/notes.jsonl");
      const { body: _b, ...n1 } = { ...notes[0]!, body: "" };
      const { body: _c, ...n2 } = notes[1]!;
      writeFileSync(file, [JSON.stringify(n1), JSON.stringify(n2), ""].join("\n"));
      expect(await recordPosted(wb, 10640, [{ note_id: "f2", github_comment_id: 5002 }], "2026-11-01T22:00:00Z")).toBe(1);
      const lines = readFileSync(file, "utf8").trim().split("\n").map((l) => JSON.parse(l));
      expect(lines[0]).toEqual(n1);
      expect(lines[1]).toEqual({ ...n2, status: "posted", github_comment_id: 5002, updated: "2026-11-01T22:00:00Z" });
      expect(await recordPosted(wb, 999, [])).toBe(0);
    } finally {
      rmSync(wb, { recursive: true, force: true });
    }
  });
});
