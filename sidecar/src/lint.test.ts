import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { lint } from "./lint.js";

const VIEWER = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

const rules = (text: string) => [...new Set(lint(text).map((h) => h.rule))].sort();

// Each bad sentence and the rule that must fire on it. Sentences marked "gist" are the gist's own examples.
const BAD: [string, string][] = [
  ["The relay drains the queue — then exits.", "dash"],
  ["Retries run 3–5 times.", "dash"],
  ["The worker -- unlike the driver -- restarts.", "dash"],
  ["Three interfaces, one underlying structure.", "counting-opener"], // gist
  ["One migration: move the table, then drop the old column.", "counting-opener"], // gist
  ["Two structures: a queue and a map.", "counting-opener"], // gist
  ["Two findings, and one of them's worse than it looks.", "counting-opener"], // gist
  ["Here's the thing: the cache is cold.", "signpost"], // gist
  ["The real question is whether the lock is held.", "signpost"], // gist
  ["The distinction worth keeping straight: a task is not a machine.", "signpost"], // gist
  ["Short version: the PR is fine.", "signpost"], // gist
  ["It is worth noting that the pump is serial.", "signpost"],
  ["Two things this buys over a raw call.", "banned-word"], // gist
  ["A trigger names no moment in the schedule.", "banned-word"], // gist
  ["One pass names the column no fold sees.", "banned-word"], // gist
  ["The controller owns the lease and reaches the workers.", "banned-word"],
  ["This change will ship tomorrow after triage.", "banned-word"],
  ["The relay sits between the guest and the host.", "banned-word"],
  ["Additionally, the worker retries the request.", "cadence-word"],
  ["The design is robust and seamless.", "cadence-word"],
  ["The issue is query execution, not the metadata path.", "stock-contrast"],
  ["The change improves reliability, not just performance.", "stock-contrast"],
  ["Not only does it retry, but it also logs.", "stock-contrast"], // gist
  ["The issue is not query execution, but the metadata path.", "stock-contrast"],
  ["It's not a cache. It's a queue.", "stock-contrast"], // gist
  ["The tool is more than a linter.", "stock-contrast"],
  ["The worker polls rather than waits.", "stock-contrast"],
  ["## How the relay works", "question-heading"],
  ["### What changed", "question-heading"],
  ["**Result:** the build passes.", "bold-label"],
  ["**Risk**: the cache can go stale.", "bold-label"],
];

// Sentences that must stay clean: adjective "own", noun "name", grammatical negation, measured comparisons,
// and banned words inside code spans.
const GOOD: string[] = [
  "Each machine gets its own child cgroup under the delegated parent.",
  "The worker writes the container names into each member's `/etc/hosts`.",
  "`single_container_task` wraps a plain `MachineSpec` under the name `task`.",
  "Shellbox can start a task as a group of named containers.",
  "The ablation has not run.",
  "The pump answers in 4 ms rather than 40 ms after the change.",
  "`own_cleanup` keeps cleanup tasks in a module-level set, and `see_also` lists `pin` and `wire`.",
  "```\nwant = touch(see)\n```\nThe helper returns the parsed frame.",
  "## Relay limits",
  "The relay accepts at most 16 pending requests and drops further connections without a response.",
  "Metadata loading takes 12 seconds. Query execution takes 400 ms.",
];

describe("lint: known-bad sentences", () => {
  it.each(BAD)("%s -> %s", (text, rule) => {
    expect(rules(text)).toContain(rule);
  });

  it("reports the offending text and its index in the original string", () => {
    const text = "Use `see` here; the controller sees the queue — always.";
    const hits = lint(text);
    expect(hits).toEqual([
      { rule: "banned-word", match: "sees", index: text.indexOf("sees") },
      { rule: "dash", match: "—", index: text.indexOf("—") },
    ]);
  });
});

describe("lint: known-good sentences", () => {
  it.each(GOOD)("%s", (text) => {
    expect(lint(text)).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// The demo's hand-written text is the style reference (DESIGN.md section 2). The test reads it from
// demo/index.html, applies the rewrites in prompts/fixture-rewrites.json (the same ones the #10640
// fixture applies), and expects no hits anywhere: descriptions, steps, review notes, memory notes and
// every diagram label and subtitle.

type Json = string | number | boolean | null | Json[] | { [key: string]: Json };
interface Rewrite {
  path: string[];
  from: string;
  to: string;
}

function step(obj: Json, seg: string): Json {
  if (Array.isArray(obj)) {
    const byId = obj.find((item) => typeof item === "object" && item !== null && !Array.isArray(item) && String(item["id"]) === seg);
    return byId ?? (obj[Number(seg)] as Json);
  }
  if (typeof obj === "object" && obj !== null) return obj[seg] as Json;
  throw new Error(`cannot descend into ${JSON.stringify(obj)} at ${seg}`);
}

function loadDemo(): { [key: string]: Json } {
  const html = readFileSync(path.join(VIEWER, "demo/index.html"), "utf8");
  const start = html.indexOf('const SRC = "lib/shellbox/src/shellbox/";');
  const stop = html.indexOf("/* ---------------- State ---------------- */");
  const memory = html.indexOf("S.memory = [");
  if (start < 0 || stop < 0 || memory < 0) throw new Error("demo/index.html no longer has the wordbase constants or memory notes");
  const demo = new Function(`${html.slice(start, stop)}\nreturn { PR, FILES, STEPS, FINDINGS, CTX, SUB, STEP_DIA };`)() as { [key: string]: Json };
  demo["MEMORY"] = new Function(`return ${html.slice(memory + "S.memory = ".length, html.indexOf("];", memory) + 1)};`)() as Json;
  return demo;
}

const REWRITES = JSON.parse(readFileSync(path.join(VIEWER, "prompts/fixture-rewrites.json"), "utf8")) as Rewrite[];

function applyRewrites(demo: { [key: string]: Json }): void {
  for (const r of REWRITES) {
    const field = r.path.at(-1)!;
    const holder = r.path.slice(0, -1).reduce<Json>(step, demo) as { [key: string]: Json };
    const text = holder[field];
    if (typeof text !== "string" || text.split(r.from).length !== 2) {
      throw new Error(`rewrite ${r.path.join(".")}: "${r.from}" must occur exactly once`);
    }
    holder[field] = text.replace(r.from, r.to);
  }
}

/** Every string in the demo's text fields, with its location. */
function texts(demo: { [key: string]: Json }): [string, string][] {
  const TEXT = new Set(["l1", "l2", "l3", "s", "title", "label", "sub", "text"]);
  const out: [string, string][] = [];
  const visit = (value: Json, where: string, key: string) => {
    if (typeof value === "string") {
      if (TEXT.has(key)) out.push([where, value]);
    } else if (Array.isArray(value)) {
      value.forEach((v, i) => visit(v, `${where}[${i}]`, key));
    } else if (value && typeof value === "object") {
      for (const [k, v] of Object.entries(value)) visit(v, `${where}.${k}`, k);
    }
  };
  for (const section of ["PR", "FILES", "STEPS", "FINDINGS", "MEMORY", "CTX", "SUB", "STEP_DIA"]) visit(demo[section]!, section, section);
  return out;
}

describe("lint: demo text", () => {
  const raw = loadDemo();
  const rewritten = loadDemo();
  applyRewrites(rewritten);

  it("finds every demo text", () => {
    expect(texts(rewritten).length).toBeGreaterThan(150);
  });

  it("has no hits once the fixture rewrites are applied", () => {
    const got = texts(rewritten).flatMap(([where, text]) => lint(text).map((h) => [where, h.rule, h.match]));
    expect(got).toEqual([]);
  });

  it("needs every rewrite: each one removes a hit from the original text", () => {
    for (const r of REWRITES) {
      const before = r.path.reduce<Json>(step, raw) as string;
      const after = r.path.reduce<Json>(step, rewritten) as string;
      expect(lint(before).length, r.path.join(".")).toBeGreaterThan(lint(after).length);
    }
  });
});

describe("lint: prompts", () => {
  const dir = path.join(VIEWER, "prompts");
  const files = readdirSync(dir).filter((f) => f.endsWith(".md"));

  it("finds the prompts", () => {
    expect(files.length).toBeGreaterThanOrEqual(5);
  });

  it.each(files)("prompts/%s passes", (file) => {
    const hits = lint(readFileSync(path.join(dir, file), "utf8")).map((h) => [h.rule, h.match]);
    expect(hits).toEqual([]);
  });
});
