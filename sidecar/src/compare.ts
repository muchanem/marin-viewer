// `npm run compare`: the 20-file description comparison of DESIGN.md section 8. Describes the same
// directory units with each model on the first-pass shape (no existing entries), and writes lint
// hits, cost, latency and the texts side by side to `state/reports/describe-comparison.md`. Results
// are kept in `describe-comparison.json` beside it, so a later `--models glm` run fills in a model
// without rerunning the others. Nothing is written to the wordbase.
//
//   npm run compare -- [--models sonnet,opus,glm] [--commit <rev>] [--fresh]
//
// A model with earlier results keeps its successful units and reruns the others; --fresh reruns all.

import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { loadConfig } from "./config.js";
import { lint } from "./lint.js";
import { ClaudeBackend, FleetHold, GlmBackend, TunnelDown, type Backend } from "./pipeline/backends.js";
import { checkOutput, describeUnit, type EntryOut } from "./pipeline/describe.js";
import { MarinRepo } from "./pipeline/repo.js";
import { Ledger, readJson, stateFiles, writeJson } from "./pipeline/state.js";
import { buildContext, groupByDirectory, loadUnit, type Unit } from "./pipeline/units.js";

export const UNITS = ["lib/shellbox/src/shellbox/backends/local", "lib/shellbox/src/shellbox/backends/daytona", "lib/iris/src/iris/actor", "lib/finelog/src/finelog/client"];

const MODELS: Record<string, { label: string; make: (c: ReturnType<typeof loadConfig>) => Backend }> = {
  sonnet: { label: "Sonnet 5.5", make: (c) => new ClaudeBackend(c, "claude-sonnet-5-5", "medium") },
  opus: { label: "Opus 5.5", make: (c) => new ClaudeBackend(c, "claude-opus-5-5", "medium") },
  glm: { label: "GLM-5.3", make: () => new GlmBackend({ holdMs: 5 * 60_000 }) },
};

interface UnitRun {
  unit: string;
  ok: boolean;
  error?: string;
  cost_usd: number;
  latency_ms: number;
  input_tokens: number;
  output_tokens: number;
  rewritten: boolean;
  first_lint: number;
  final_lint: number;
  hits: string[];
  entries: Record<string, EntryOut | { keep: true }>;
}

interface ModelRun {
  model: string;
  label: string;
  backend: string;
  at: string;
  commit: string;
  effort?: string;
  units: UnitRun[];
  error?: string;
}

interface Results {
  commit: string;
  runs: Record<string, ModelRun>;
}

async function runModel(key: string, units: Unit[], ctxs: Map<string, Awaited<ReturnType<typeof buildContext>>>, config: ReturnType<typeof loadConfig>, ledger: Ledger, commit: string, prior: ModelRun | undefined): Promise<ModelRun> {
  const m = MODELS[key]!;
  // Units that already succeeded for this model are kept; only failed or missing units run again.
  const kept = (prior?.units ?? []).filter((u) => u.ok && units.some((x) => x.dir === u.unit));
  const run: ModelRun = { model: key, label: m.label, backend: prior?.backend ?? "", at: new Date().toISOString(), commit, ...(key !== "glm" ? { effort: "medium" } : {}), units: [...kept] };
  let backend: Backend;
  try {
    backend = m.make(config);
    run.backend = backend.name;
  } catch (e) {
    run.error = (e as Error).message;
    return run;
  }
  for (const u of units) {
    if (kept.some((k) => k.unit === u.dir)) {
      process.stderr.write(`compare: ${m.label} on ${u.dir}: kept from ${prior!.at}\n`);
      continue;
    }
    const ctx = ctxs.get(u.dir)!;
    process.stderr.write(`compare: ${m.label} on ${u.dir} (${u.targets.length} files, ${ctx.stats.chars} chars)\n`);
    try {
      const r = await describeUnit(backend, config.prompts, ctx);
      const first = checkOutput(r.completions[0]!.text, u.targets, new Set(), u.package);
      const hits = [...r.lint.entries()].flatMap(([p, hs]) => hs.map((h) => `${p} ${h}`));
      run.units.push({
        unit: u.dir,
        ok: true,
        cost_usd: r.cost_usd,
        latency_ms: r.latency_ms,
        input_tokens: r.completions.reduce((a, c) => a + c.input_tokens, 0),
        output_tokens: r.completions.reduce((a, c) => a + c.output_tokens, 0),
        rewritten: r.rewritten,
        first_lint: [...first.lint.values()].reduce((a, h) => a + h.length, 0),
        final_lint: hits.length,
        hits,
        entries: r.output,
      });
      await ledger.add({ at: new Date().toISOString(), kind: "compare", run: `compare ${u.dir}`, model: backend.name, cost_usd: r.cost_usd, latency_ms: r.latency_ms });
      process.stderr.write(`compare: ${m.label} on ${u.dir}: $${r.cost_usd.toFixed(3)}, ${(r.latency_ms / 1000).toFixed(0)} s, lint ${hits.length}\n`);
    } catch (e) {
      const cost = (e as { cost_usd?: number }).cost_usd ?? 0;
      run.units.push({ unit: u.dir, ok: false, error: (e as Error).message, cost_usd: cost, latency_ms: 0, input_tokens: 0, output_tokens: 0, rewritten: true, first_lint: 0, final_lint: 0, hits: [], entries: {} });
      if (cost) await ledger.add({ at: new Date().toISOString(), kind: "compare", run: `compare ${u.dir} (failed)`, model: backend.name, cost_usd: cost });
      process.stderr.write(`compare: ${m.label} on ${u.dir} failed: ${(e as Error).message}\n`);
      if (e instanceof TunnelDown || e instanceof FleetHold) {
        run.error = (e as Error).message;
        break;
      }
    }
  }
  return run;
}

const esc = (s: string) => s.replace(/\|/g, "\\|").replace(/\n/g, " ");

export function renderReport(res: Results, units: Unit[]): string {
  const order = ["sonnet", "opus", "glm"].filter((k) => res.runs[k]);
  const runs = order.map((k) => res.runs[k]!);
  const out: string[] = [];
  out.push(
    "# Description model comparison",
    "",
    `The same ${units.reduce((a, u) => a + u.targets.length, 0)} files in ${units.length} directory units, described at Marin commit \`${res.commit.slice(0, 12)}\` with \`prompts/describe-unit.md\` on the first-pass shape: full sources, the package README, neighbour signatures and \`l1\` lines, the subsystem page, and no existing entries. Each reply was validated and linted; a reply with problems got one rewrite turn, as in the poller. Generated by \`npm run compare\`; nothing here was written to the wordbase. The verdict is left to the reader.`,
    "",
    `Units: ${units.map((u) => `\`${u.dir.replace(/^lib\//, "")}\` (${u.targets.length})`).join(", ")}.`,
    "",
    "## Totals",
    "",
    "| Model | Backend | Units done | Files | Cost | Latency (sum) | Input tokens | Output tokens | Lint, first draft | Lint, final | Rewrites |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
  );
  for (const r of runs) {
    const ok = r.units.filter((u) => u.ok);
    const files = ok.reduce((a, u) => a + Object.keys(u.entries).length, 0);
    const sum = (f: (u: UnitRun) => number) => r.units.reduce((a, u) => a + f(u), 0);
    out.push(
      `| ${r.label} | \`${r.backend || "unavailable"}\`${r.effort ? ` (effort ${r.effort})` : ""} | ${ok.length} of ${units.length} | ${files} | $${sum((u) => u.cost_usd).toFixed(3)}${r.model === "glm" ? " (self-hosted)" : ""} | ${(sum((u) => u.latency_ms) / 1000).toFixed(0)} s | ${sum((u) => u.input_tokens)} | ${sum((u) => u.output_tokens)} | ${sum((u) => u.first_lint)} | ${sum((u) => u.final_lint)} | ${r.units.filter((u) => u.rewritten).length} |`,
    );
  }
  for (const r of runs) if (r.error) out.push("", `${r.label} did not complete: ${r.error}`);
  out.push("", "## Per unit", "", "| Unit | " + runs.map((r) => `${r.label} cost / latency / lint`).join(" | ") + " |", "| --- | " + runs.map(() => "---").join(" | ") + " |");
  for (const u of units) {
    const cells = runs.map((r) => {
      const x = r.units.find((y) => y.unit === u.dir);
      if (!x) return "not run";
      if (!x.ok) return `failed: ${esc(x.error ?? "").slice(0, 120)}`;
      return `$${x.cost_usd.toFixed(3)} / ${(x.latency_ms / 1000).toFixed(0)} s / ${x.first_lint} then ${x.final_lint}${x.rewritten ? " (rewritten)" : ""}`;
    });
    out.push(`| \`${u.dir.replace(/^lib\//, "")}\` | ${cells.join(" | ")} |`);
  }
  out.push("", "## Remaining lint hits", "");
  for (const r of runs) {
    const hits = r.units.flatMap((u) => u.hits);
    out.push(`- ${r.label}: ${hits.length ? hits.map((h) => `\`${h.replace(/`/g, "'")}\``).join("; ") : "none"}`);
  }
  out.push("", "## Texts", "");
  for (const u of units) {
    out.push(`### \`${u.dir.replace(/^lib\//, "")}\``, "");
    for (const f of u.targets) {
      out.push(`#### \`${f.split("/").at(-1)}\``, "", "| | " + runs.map((r) => r.label).join(" | ") + " |", "| --- | " + runs.map(() => "---").join(" | ") + " |");
      const get = (r: ModelRun) => {
        const e = r.units.find((y) => y.unit === u.dir)?.entries[f];
        return e && !("keep" in e) ? e : null;
      };
      const row = (label: string, pick: (e: EntryOut) => string) => out.push(`| ${label} | ${runs.map((r) => (get(r) ? esc(pick(get(r)!)) || " " : "(none)")).join(" | ")} |`);
      row("l1", (e) => e.l1);
      row("l2", (e) => e.l2 ?? "");
      row("l3", (e) => (e.l3 ?? []).join(" ¶ "));
      row("symbols", (e) => (e.symbols ?? []).map((s) => `\`${s.name}\`: ${s.l1}`).join(" ¶ "));
      row("lint", (e) => {
        const n = [e.l1, e.l2 ?? "", ...(e.l3 ?? []), ...(e.symbols ?? []).flatMap((s) => [s.l1, s.l2 ?? ""])].reduce((a, t) => a + lint(t).length, 0);
        return String(n);
      });
      out.push("");
    }
  }
  return out.join("\n") + "\n";
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  let models = ["sonnet", "opus", "glm"];
  let rev = "HEAD";
  let fresh = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--models") models = (argv[++i] ?? "").split(",").filter(Boolean);
    else if (argv[i] === "--commit") rev = argv[++i] ?? rev;
    else if (argv[i] === "--fresh") fresh = true;
    else throw new Error(`unknown flag ${argv[i]}`);
  }
  for (const m of models) if (!MODELS[m]) throw new Error(`unknown model ${m}; use ${Object.keys(MODELS).join(", ")}`);
  const config = loadConfig();
  const files = stateFiles(config.state);
  const repo = new MarinRepo(config.marin);
  const jsonFile = path.join(files.reports, "describe-comparison.json");
  const prior = await readJson<Results | null>(jsonFile, null);
  const commit = prior?.commit ?? (await repo.rev(rev));
  const units: Unit[] = [];
  for (const dir of UNITS) {
    const base = groupByDirectory([`${dir}/x.py`], commit)[0]!;
    const loaded = await loadUnit(repo, { ...base, targets: [] });
    units.push({ ...loaded, targets: loaded.files });
  }
  const total = units.reduce((a, u) => a + u.targets.length, 0);
  process.stderr.write(`compare: ${total} files in ${units.length} units at ${commit.slice(0, 10)}; models ${models.join(", ")}\n`);
  const ctxs = new Map<string, Awaited<ReturnType<typeof buildContext>>>();
  for (const u of units) ctxs.set(u.dir, await buildContext(repo, u, { wordbase: config.wordbase, ignoreExisting: true }));
  const ledger = new Ledger(files.spend);
  const runs = await Promise.all(models.map((m) => runModel(m, units, ctxs, config, ledger, commit, fresh ? undefined : prior?.runs[m])));
  const res: Results = { commit, runs: { ...(prior?.runs ?? {}) } };
  for (const r of runs) res.runs[r.model] = r;
  await mkdir(files.reports, { recursive: true });
  await writeJson(jsonFile, res);
  const md = path.join(files.reports, "describe-comparison.md");
  await writeFile(md, renderReport(res, units), "utf8");
  for (const r of runs) {
    const cost = r.units.reduce((a, u) => a + u.cost_usd, 0);
    process.stdout.write(`${r.label}: ${r.units.filter((u) => u.ok).length}/${units.length} units, $${cost.toFixed(3)}, lint ${r.units.reduce((a, u) => a + u.final_lint, 0)}${r.error ? `, error: ${r.error}` : ""}\n`);
  }
  process.stdout.write(`report: ${md}\n`);
}

const isEntry = process.argv[1]?.endsWith("/compare.js");
if (isEntry) {
  main().catch((e) => {
    process.stderr.write(`ERROR ${(e as Error).message}\n`);
    process.exitCode = 1;
  });
}
