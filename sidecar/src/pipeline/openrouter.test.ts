import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { openRouterKey, type Config } from "../config.js";
import { MODEL_ORDER, measuredModel, renderReport, repriced, type ModelRun } from "../compare.js";
import { passCost, passUnits } from "./estimate.js";
import { OpenRouterBackend, parseOpenRouter } from "./openrouter.js";

const KEY = "sk-or-v1-test-not-a-real-key";

type Seen = { url: string; body?: Record<string, unknown>; auth?: string };
function fetcher(replies: { status: number; body: string }[], seen: Seen[] = []): typeof fetch {
  return (async (input: string | URL | Request, init?: RequestInit) => {
    const headers = (init?.headers ?? {}) as Record<string, string>;
    seen.push({ url: String(input), ...(init?.body ? { body: JSON.parse(String(init.body)) } : {}), ...(headers.Authorization ? { auth: headers.Authorization } : {}) });
    const r = replies.shift() ?? { status: 500, body: "no reply left" };
    return new Response(r.body, { status: r.status });
  }) as typeof fetch;
}

const sse = (chunks: unknown[]) => ": OPENROUTER PROCESSING\n\n" + chunks.map((c) => `data: ${JSON.stringify(c)}\n\n`).join("") + "data: [DONE]\n\n";

const STREAM = sse([
  { id: "gen-1", model: "openai/gpt-6.1-terra-20261026", provider: "OpenAI", service_tier: "priority", choices: [{ delta: { content: '{"a":' } }] },
  { id: "gen-1", choices: [{ delta: { content: "1}" }, finish_reason: "stop" }] },
  { id: "gen-1", service_tier: "priority", choices: [], usage: { prompt_tokens: 1000, completion_tokens: 300, cost: 0.0051, prompt_tokens_details: { cached_tokens: 200 }, completion_tokens_details: { reasoning_tokens: 220 } } },
]);

describe("OpenRouter replies", () => {
  it("joins streamed deltas and keeps the served tier, provider and usage", () => {
    const r = parseOpenRouter(STREAM);
    expect(r).toMatchObject({ id: "gen-1", provider: "OpenAI", service_tier: "priority", content: '{"a":1}', finish_reason: "stop" });
    expect(r.usage?.cost).toBe(0.0051);
  });

  it("throws on an error chunk in the stream", () => {
    expect(() => parseOpenRouter(sse([{ error: { code: 502, message: "upstream overloaded" } }]))).toThrow(/OpenRouter error 502: upstream overloaded/);
  });
});

describe("OpenRouterBackend", () => {
  const make = (replies: { status: number; body: string }[], seen: Seen[] = []) =>
    new OpenRouterBackend({ model: "openai/gpt-6.1-terra", tier: "priority", effort: "medium", key: KEY, url: "https://or.test/api/v1", fetchFn: fetcher(replies, seen), sleep: async () => {}, log: () => {} });

  it("streams with the tier and reasoning effort, and takes the cost from usage.cost", async () => {
    const seen: Seen[] = [];
    const c = await make([{ status: 200, body: STREAM }], seen).complete([{ role: "user", content: "hi" }]);
    expect(seen[0]!.url).toBe("https://or.test/api/v1/chat/completions");
    expect(seen[0]!.auth).toBe(`Bearer ${KEY}`);
    expect(seen[0]!.body).toMatchObject({ model: "openai/gpt-6.1-terra", stream: true, service_tier: "priority", reasoning: { effort: "medium" } });
    expect("max_tokens" in seen[0]!.body!).toBe(false);
    expect(c).toMatchObject({ text: '{"a":1}', input_tokens: 1000, output_tokens: 300, cache_read_tokens: 200, cost_usd: 0.0051, cost_source: "usage.cost", served_tier: "priority", reasoning_tokens: 220, provider: "OpenAI", generation_id: "gen-1" });
  });

  it("falls back to the generation record when usage has no cost, and fails rather than record a free call", async () => {
    const noCost = STREAM.replace('"cost":0.0051,', "");
    const c = await make([{ status: 200, body: noCost }, { status: 404, body: "not yet" }, { status: 200, body: JSON.stringify({ data: { id: "gen-1", total_cost: 0.0049 } }) }]).complete([{ role: "user", content: "hi" }]);
    expect(c.cost_usd).toBe(0.0049);
    expect(c.cost_source).toBe("generation endpoint");
    const gone = Array.from({ length: 4 }, () => ({ status: 404, body: "missing" }));
    await expect(make([{ status: 200, body: noCost }, ...gone]).complete([{ role: "user", content: "hi" }])).rejects.toThrow(/reported no cost/);
  });

  it("retries a 429 or 5xx, and gives up after the attempts", async () => {
    const seen: Seen[] = [];
    const c = await make([{ status: 429, body: "slow down" }, { status: 503, body: "busy" }, { status: 200, body: STREAM }], seen).complete([{ role: "user", content: "hi" }]);
    expect(seen).toHaveLength(3);
    expect(c.text).toBe('{"a":1}');
    await expect(make([{ status: 502, body: "a" }, { status: 502, body: "b" }, { status: 502, body: "c" }]).complete([{ role: "user", content: "hi" }])).rejects.toThrow(/answered 502: c/);
    await expect(make([{ status: 400, body: "bad tier" }]).complete([{ role: "user", content: "hi" }])).rejects.toThrow(/answered 400: bad tier/);
  });

  it("rejects a reply cut by the length limit", async () => {
    const cut = sse([{ id: "g", choices: [{ delta: { content: "{" }, finish_reason: "length" }], usage: { cost: 0.1 } }]);
    await expect(make([{ status: 200, body: cut }]).complete([{ role: "user", content: "hi" }])).rejects.toThrow(/length limit/);
  });
});

describe("the OpenRouter key", () => {
  const dirs: string[] = [];
  afterEach(() => {
    for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
  });
  const setup = () => {
    const parent = mkdtempSync(path.join(tmpdir(), "orkey-"));
    dirs.push(parent);
    const root = path.join(parent, "marin-viewer");
    mkdirSync(root);
    const config: Config = { root, marin: "", wordbase: "", state: "", prompts: "", envFile: path.join(root, ".env") };
    return { parent, root, config };
  };

  it("prefers OPENROUTER_API_KEY in the viewer's .env, then OR_KEY_SCALE_UP in the parent's", () => {
    const { parent, root, config } = setup();
    writeFileSync(path.join(parent, ".env"), `OTHER=1\nOR_KEY_SCALE_UP="${KEY}-parent"\n`);
    expect(openRouterKey(config)).toEqual({ key: `${KEY}-parent`, source: `OR_KEY_SCALE_UP in ${path.join(parent, ".env")}` });
    writeFileSync(path.join(root, ".env"), `CLAUDE_API_KEY=x\nOPENROUTER_API_KEY='${KEY}-viewer'\n`);
    expect(openRouterKey(config).key).toBe(`${KEY}-viewer`);
  });

  it("names where it looked, and never the value, when no source has the key", () => {
    const { config } = setup();
    let message = "";
    try {
      openRouterKey(config);
    } catch (e) {
      message = (e as Error).message;
    }
    expect(message).toMatch(/no OpenRouter key: looked for OPENROUTER_API_KEY in .*, then OR_KEY_SCALE_UP in /);
    expect(message).not.toMatch(/sk-or/);
  });
});

describe("cost estimates", () => {
  it("groups files into directory units and splits large directories", () => {
    const sizes = new Map([
      ["lib/a/x.py", 200_000],
      ["lib/a/y.py", 150_000],
      ["lib/a/z.py", 0],
      ["lib/b/w.py", 10],
      ["lib/b/README.md", 99],
      ["docs/q.py", 5],
    ]);
    expect(passUnits(sizes).sort((p, q) => p.chars - q.chars)).toEqual([
      { chars: 10, files: 1 },
      { chars: 150_000, files: 1 },
      { chars: 200_000, files: 1 },
    ]);
  });

  it("prices a first call, a cached rewrite share and output", () => {
    const c = passCost([{ chars: 120_000, files: 2 }], { outPerFile: 1000, rewriteRate: 0.5, tokenRatio: 1 }, { firstInput: 2, cachedInput: 0.2, output: 10 });
    // input = 5,000 + 156,000 / 2.4 = 70,000 tokens
    expect(c.inputTokens).toBeCloseTo(105_000);
    expect(c.usd).toBeCloseTo((70_000 * 2 + 35_000 * 0.2 + 2_000 * 10) / 1e6);
  });

  const unit = (over: object = {}) => ({ unit: "lib/x", ok: true, cost_usd: 0.5, latency_ms: 1000, input_tokens: 20_000, output_tokens: 4_000, rewritten: true, first_lint: 1, final_lint: 0, hits: [], entries: { "lib/x/a.py": { l1: "Does a thing.", system: "x" }, "lib/x/b.py": { l1: "Does another.", system: "x" } }, ...over });
  const sonnet: ModelRun = { model: "sonnet", label: "Sonnet 5.5", backend: "claude-sonnet-5-5", at: "t", commit: "c".repeat(40), effort: "medium", units: [unit()] };
  const terra: ModelRun = {
    model: "terra",
    label: "GPT-6.1 Terra",
    backend: "openai/gpt-6.1-terra",
    at: "t",
    commit: "c".repeat(40),
    effort: "medium",
    tier: "priority",
    units: [
      unit({
        input_tokens: 25_000,
        output_tokens: 6_000,
        calls: [
          { served_tier: "priority", cost_source: "usage.cost", reasoning_tokens: 2_000, input_tokens: 12_000, cache_read_tokens: 0, output_tokens: 3_000, cost_usd: 0.054, provider: "OpenAI" },
          { served_tier: "priority", cost_source: "usage.cost", reasoning_tokens: 1_000, input_tokens: 13_000, cache_read_tokens: 11_000, output_tokens: 3_000, cost_usd: 0.0351, provider: "OpenAI" },
        ],
      }),
    ],
  };

  it("measures each model's parameters against Sonnet and reprices its calls", () => {
    expect(measuredModel(terra, sonnet)).toEqual({ outPerFile: 3000, rewriteRate: 1, tokenRatio: 1.2 });
    expect(repriced(terra, { input: 0.5, cachedInput: 0.025, output: 2.5 })).toBeCloseTo((14_000 * 0.5 + 11_000 * 0.025 + 6_000 * 2.5) / 1e6);
  });

  it("adds Terra's column, its tier and cost source, and the flex and full-pass estimates", () => {
    const md = renderReport({ commit: "c".repeat(40), runs: { sonnet, terra } }, [{ dir: "lib/x", package: "x", commit: "c", files: ["lib/x/a.py", "lib/x/b.py"], targets: ["lib/x/a.py", "lib/x/b.py"] }], { units: [{ chars: 120_000, files: 2 }], files: 2 });
    expect(MODEL_ORDER.at(-1)).toBe("terra");
    expect(md).toMatch(/\| GPT-6\.1 Terra \| `openai\/gpt-6\.1-terra` \(effort medium, tier priority requested, priority served\) \| 1 of 1 \|/);
    expect(md).toMatch(/- GPT-6\.1 Terra: OpenRouter's reported cost .*The 2 calls recorded usage\.cost, and reported 3000 reasoning tokens\./);
    expect(md).toMatch(/\| Unit \| Sonnet 5\.5 cost \/ latency \/ lint \| GPT-6\.1 Terra cost \/ latency \/ lint \|/);
    // Repriced at priority prices, the calls must reproduce what OpenRouter charged: 12,000 x 2.5 + 3,000 x 10, then 2,000 x 2.5 + 11,000 x 0.1 + 3,000 x 10.
    expect(md).toMatch(/come to \$0\.096 at priority prices/);
    expect(md).toMatch(/\*\*\$\d\.\d{3} on the flex tier\*\*\. .*The flex prices are \$0\.50 input, \$0\.625 cache write/);
    expect(md).toMatch(/\| GPT-6\.1 Terra, flex \| \$\d+ \|/);
    expect(md).toMatch(/\| Sonnet 5\.5, Batch API \| \$\d+ \|/);
    expect(md).toMatch(/\| l1 \| Does a thing\. \| Does a thing\. \|/);
  });
});
