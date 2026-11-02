// The full first-pass cost model behind the estimates in plans/pipeline.md and the comparison report.
// It groups every non-empty Python file under lib/ into the poller's directory units (split when a
// directory's sources pass `sliceChars`), sizes each unit's prompt from its sources plus a measured
// per-unit overhead, and prices one first call plus a cached rewrite on the measured share of units.

import path from "node:path";

export interface PassUnit {
  chars: number;
  files: number;
}

/** Directory units from file sizes, as `groupByDirectory` forms them, split at `sliceChars`. */
export function passUnits(sizes: Map<string, number>, sliceChars = 280_000): PassUnit[] {
  const dirs = new Map<string, number[]>();
  for (const [p, n] of sizes) {
    if (!p.startsWith("lib/") || !p.endsWith(".py") || n === 0) continue;
    const d = path.posix.dirname(p);
    dirs.set(d, [...(dirs.get(d) ?? []), n]);
  }
  const units: PassUnit[] = [];
  for (const list of dirs.values()) {
    let cur = 0;
    let files = 0;
    for (const n of [...list].sort((a, b) => a - b)) {
      if (cur && cur + n > sliceChars) {
        units.push({ chars: cur, files });
        cur = 0;
        files = 0;
      }
      cur += n;
      files++;
    }
    units.push({ chars: cur, files });
  }
  return units;
}

/** USD per million tokens. `firstInput` is what a first call's prompt costs (a cache write where caching is explicit). */
export interface PassPrices {
  firstInput: number;
  cachedInput: number;
  output: number;
}

export interface PassModel {
  /** Output tokens per file, reasoning included, from the comparison. */
  outPerFile: number;
  /** Share of units that needed a rewrite turn. */
  rewriteRate: number;
  /** Input tokens relative to Sonnet 5.5 on the same prompts (tokenizer difference). */
  tokenRatio: number;
}

/** Measured on Sonnet 5.5 (2026-11-01): characters per token, fixed prompt tokens, per-unit context characters. */
export const SONNET_SHAPE = { charsPerToken: 2.4, templateTokens: 5_000, overheadChars: 36_000 };

export function passCost(units: PassUnit[], m: PassModel, p: PassPrices): { usd: number; inputTokens: number; outputTokens: number } {
  let usd = 0;
  let inputTokens = 0;
  let outputTokens = 0;
  for (const u of units) {
    const input = (SONNET_SHAPE.templateTokens + (u.chars + SONNET_SHAPE.overheadChars) / SONNET_SHAPE.charsPerToken) * m.tokenRatio;
    const output = m.outPerFile * u.files;
    usd += (input * p.firstInput + m.rewriteRate * input * p.cachedInput + output * p.output) / 1e6;
    inputTokens += input * (1 + m.rewriteRate);
    outputTokens += output;
  }
  return { usd, inputTokens, outputTokens };
}
