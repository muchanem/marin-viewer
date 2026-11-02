// Messages API prices in USD per million tokens (first-party rates, cached 2026-10-06 from the
// claude-api reference). Agent SDK runs report their own `total_cost_usd`; these prices cover the
// direct Messages API calls that description runs make.

export interface Price {
  input: number;
  output: number;
  cacheRead: number;
  /** Five-minute cache writes cost 1.25 times the input price. */
  cacheWrite: number;
}

export const PRICES: Record<string, Price> = {
  // Claude Fable 5.1: $10 / $50 per MTok from the claude-api reference's Current Models table (cached
  // 2026-10-06); cache reads $0.25 from its Fable 5.1 section; writes at 1.25 times input. Thinking
  // is always on and bills as output.
  "claude-fable-5-1": { input: 10, output: 50, cacheRead: 0.25, cacheWrite: 12.5 },
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 },
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.2, cacheWrite: 2.5 },
  "claude-haiku-5-5": { input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite: 0.125 },
};

export interface TokenUsage {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens?: number | null;
  cache_creation_input_tokens?: number | null;
}

export function costUsd(model: string, u: TokenUsage): number {
  const p = PRICES[model];
  if (!p) throw new Error(`no price for model ${model}; add it to pricing.ts`);
  return (
    (u.input_tokens * p.input + u.output_tokens * p.output + (u.cache_read_input_tokens ?? 0) * p.cacheRead + (u.cache_creation_input_tokens ?? 0) * p.cacheWrite) /
    1_000_000
  );
}
