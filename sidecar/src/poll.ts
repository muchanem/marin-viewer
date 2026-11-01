// `npm run poll`: the foreground poller (DESIGN.md section 8). `npm run poll -- --once` runs one tick.
//
// Flags:
//   --once                   one tick, then exit
//   --interval <s>           seconds between ticks (default 300)
//   --monthly-budget <usd>   the month's API credit, for pacing (default 200, or MARIN_VIEWER_MONTHLY_USD)
//   --max-tick-usd <usd>     stop starting description units past this spend in one tick (default 10)
//   --backend claude|glm     description backend (default claude)
//   --model <id>             Claude model for descriptions (default claude-sonnet-5-5)
//   --pr <n>                 prepare only this PR (repeatable); a PR missing from the search is prepared anyway
//   --max-preps <n>          start at most n preparation runs this tick (0 lists PRs only)
//   --no-prs, --no-describe  skip a step
//   --prep-budget <usd>      per-run cap for a preparation session (default 8)
//   --prep-effort <level>    effort for the preparation session (default high)
//   --reset-described <rev>  record <rev> as the last described commit before the tick

import { loadConfig } from "./config.js";
import { MarinRepo } from "./pipeline/repo.js";
import { DEFAULTS, Poller, type PollerOptions } from "./pipeline/poller.js";
import { readJson, stateFiles, writeJson, type MainState } from "./pipeline/state.js";

function parseArgs(argv: string[]): { opts: PollerOptions; once: boolean; resetDescribed: string | null } {
  const opts: PollerOptions = { ...DEFAULTS, onlyPrs: [] };
  if (process.env.MARIN_VIEWER_MONTHLY_USD) opts.monthlyBudgetUsd = Number(process.env.MARIN_VIEWER_MONTHLY_USD);
  let once = false;
  let resetDescribed: string | null = null;
  const num = (v: string | undefined, flag: string) => {
    const n = Number(v);
    if (!Number.isFinite(n) || n < 0) throw new Error(`${flag} needs a non-negative number`);
    return n;
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    const v = () => argv[++i];
    switch (a) {
      case "--once":
        once = true;
        break;
      case "--interval":
        opts.intervalSec = num(v(), a);
        break;
      case "--monthly-budget":
        opts.monthlyBudgetUsd = num(v(), a);
        break;
      case "--max-tick-usd":
        opts.maxTickUsd = num(v(), a);
        break;
      case "--backend": {
        const b = v();
        if (b !== "claude" && b !== "glm") throw new Error("--backend is claude or glm");
        opts.backend = b;
        break;
      }
      case "--model":
        opts.describeModel = v() ?? opts.describeModel;
        break;
      case "--pr":
        opts.onlyPrs.push(num(v(), a));
        break;
      case "--max-preps":
        opts.maxPreps = num(v(), a);
        break;
      case "--no-prs":
        opts.prs = false;
        break;
      case "--no-describe":
        opts.describe = false;
        break;
      case "--prep-budget":
        opts.prepBudgetUsd = num(v(), a);
        break;
      case "--prep-effort": {
        const e = v();
        if (e !== "low" && e !== "medium" && e !== "high" && e !== "xhigh") throw new Error("--prep-effort is low, medium, high or xhigh");
        opts.prepEffort = e;
        break;
      }
      case "--reset-described":
        resetDescribed = v() ?? null;
        break;
      default:
        throw new Error(`unknown flag ${a}`);
    }
  }
  return { opts, once, resetDescribed };
}

async function main(): Promise<void> {
  const { opts, once, resetDescribed } = parseArgs(process.argv.slice(2));
  const config = loadConfig();
  const poller = new Poller(config, opts);
  poller.print(
    `poller: marin ${config.marin} · wordbase ${config.wordbase} · state ${config.state} · prompts ${config.prompts} · describe ${opts.backend === "glm" ? "glm-5.3" : opts.describeModel} · prep claude-opus-5-5 (effort ${opts.prepEffort}, cap $${opts.prepBudgetUsd}) · interval ${opts.intervalSec} s · budget $${opts.monthlyBudgetUsd}/month · tick cap $${opts.maxTickUsd}${opts.onlyPrs.length ? ` · PRs ${opts.onlyPrs.map((n) => `#${n}`).join(", ")} only` : ""}`,
  );
  if (resetDescribed) {
    const files = stateFiles(config.state);
    const state = await readJson<MainState>(files.main, { described: null });
    const sha = await new MarinRepo(config.marin).rev(resetDescribed);
    poller.print(`reset: described ${state.described?.slice(0, 7) ?? "(none)"} -> ${sha.slice(0, 7)} (${resetDescribed})`);
    state.described = sha;
    await writeJson(files.main, state);
  }
  if (once) {
    try {
      await poller.tick();
    } finally {
      await poller.shutdown();
    }
    return;
  }
  const stop = new AbortController();
  process.on("SIGINT", () => {
    poller.print("stopping after this tick (Ctrl-C)");
    stop.abort();
  });
  await poller.loop(stop.signal);
  await poller.shutdown();
}

main().catch((e) => {
  process.stderr.write(`ERROR ${(e as Error).message}\n`);
  process.exitCode = 1;
});
