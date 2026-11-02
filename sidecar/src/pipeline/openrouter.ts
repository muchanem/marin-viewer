// OpenRouter backend: OpenAI-compatible chat completions for description runs on models outside
// Anthropic and the GLM fleet, such as GPT-6.1 Terra. It streams, requests a service tier and a
// reasoning effort, and records what OpenRouter reports back: the tier that served the request, the
// reasoning tokens, and the cost from `usage.cost` (or the generation record when that is missing).

import type { Backend, Completion, Turn } from "./backends.js";

export interface OpenRouterOptions {
  model: string;
  /** The service tier to request: `priority` (OpenRouter also accepts `fast`), `default` or `flex`. */
  tier?: string;
  /** Reasoning effort, sent as `reasoning: { effort }`. */
  effort?: string;
  key: string;
  url?: string;
  fetchFn?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
  log?: (line: string) => void;
  /** Attempts for a 429 or 5xx answered before any output. */
  attempts?: number;
  /**
   * OpenRouter's provider routing object, sent as `provider`. The first pass pins the flex endpoint
   * with `{ only: ["openai/flex"], allow_fallbacks: false }` so a request cannot be served, and
   * billed, on another tier.
   */
  provider?: Record<string, unknown>;
}

/** A failed OpenRouter request, with the HTTP status (or the code of an error sent inside the stream). */
export class OpenRouterError extends Error {
  constructor(
    message: string,
    readonly status: number | null,
    readonly code: string | null = null,
  ) {
    super(message);
  }
}

export interface OpenRouterUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  cost?: number | null;
  prompt_tokens_details?: { cached_tokens?: number; cache_write_tokens?: number };
  completion_tokens_details?: { reasoning_tokens?: number | null };
}

export interface OpenRouterReply {
  id?: string;
  model?: string;
  provider?: string;
  service_tier?: string | null;
  content: string;
  finish_reason?: string;
  usage?: OpenRouterUsage;
}

type Choice = { delta?: { content?: string | null }; message?: { content?: string | null }; finish_reason?: string | null };

/** Reads an OpenRouter chat completion streamed as server-sent events, or sent as one JSON document. */
export function parseOpenRouter(body: string): OpenRouterReply {
  const out: OpenRouterReply = { content: "" };
  const take = (doc: Record<string, unknown>, delta: boolean): void => {
    if (doc.error) {
      const e = doc.error as { code?: unknown; message?: unknown };
      const code = e.code === undefined || e.code === null ? null : String(e.code);
      throw new OpenRouterError(`OpenRouter error ${code ?? ""}: ${String(e.message ?? JSON.stringify(doc.error)).slice(0, 300)}`, /^\d{3}$/.test(code ?? "") ? Number(code) : null, code);
    }
    if (typeof doc.id === "string") out.id ??= doc.id;
    if (typeof doc.model === "string") out.model ??= doc.model;
    if (typeof doc.provider === "string") out.provider ??= doc.provider;
    if (typeof doc.service_tier === "string") out.service_tier = doc.service_tier;
    else if (doc.service_tier === null && out.service_tier === undefined) out.service_tier = null;
    if (doc.usage) out.usage = doc.usage as OpenRouterUsage;
    for (const c of (doc.choices as Choice[] | undefined) ?? []) {
      out.content += (delta ? c.delta?.content : c.message?.content) ?? "";
      if (c.finish_reason) out.finish_reason = c.finish_reason;
    }
  };
  const start = body.trimStart();
  if (!start.startsWith("data:") && !start.startsWith(":")) {
    take(JSON.parse(body) as Record<string, unknown>, false);
    return out;
  }
  // Lines starting with ":" are OpenRouter's keep-alive comments.
  for (const line of body.split("\n")) {
    if (!line.startsWith("data:")) continue;
    const data = line.slice(5).trim();
    if (!data || data === "[DONE]") continue;
    take(JSON.parse(data) as Record<string, unknown>, true);
  }
  return out;
}

export class OpenRouterBackend implements Backend {
  readonly name: string;
  private readonly url: string;
  private readonly fetchFn: typeof fetch;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly log: (line: string) => void;

  constructor(private readonly opts: OpenRouterOptions) {
    this.name = opts.model;
    this.url = opts.url ?? "https://openrouter.ai/api/v1";
    this.fetchFn = opts.fetchFn ?? fetch;
    this.sleep = opts.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
    this.log = opts.log ?? ((l) => process.stderr.write(`${l}\n`));
  }

  /** The request body, without the key. Exported for tests and for the report. */
  request(turns: Turn[], opts: { maxTokens?: number; system?: string } = {}): Record<string, unknown> {
    const messages = [...(opts.system ? [{ role: "system", content: opts.system }] : []), ...turns];
    return {
      model: this.opts.model,
      messages,
      stream: true,
      ...(this.opts.tier ? { service_tier: this.opts.tier } : {}),
      ...(this.opts.effort ? { reasoning: { effort: this.opts.effort } } : {}),
      ...(this.opts.provider ? { provider: this.opts.provider } : {}),
      ...(opts.maxTokens ? { max_tokens: opts.maxTokens } : {}),
    };
  }

  private headers(): Record<string, string> {
    return { Authorization: `Bearer ${this.opts.key}`, "Content-Type": "application/json", "X-Title": "marin-viewer" };
  }

  async complete(turns: Turn[], opts: { maxTokens?: number; system?: string } = {}): Promise<Completion> {
    const started = Date.now();
    const body = JSON.stringify(this.request(turns, opts));
    const attempts = this.opts.attempts ?? 3;
    let reply: OpenRouterReply;
    for (let attempt = 1; ; attempt++) {
      // Streaming sends the headers at once; Node's fetch gives up on headers after 300 s.
      const r = await this.fetchFn(`${this.url}/chat/completions`, { method: "POST", headers: this.headers(), body, signal: AbortSignal.timeout(30 * 60_000) });
      const text = await r.text();
      if (r.status === 200) {
        reply = parseOpenRouter(text);
        break;
      }
      if (!(r.status === 429 || r.status >= 500) || attempt >= attempts) throw new OpenRouterError(`OpenRouter answered ${r.status}: ${text.slice(0, 300)}`, r.status);
      this.log(`openrouter: ${r.status}, retrying (${attempt} of ${attempts})`);
      await this.sleep(2_000 * 2 ** (attempt - 1));
    }
    if (reply.finish_reason === "length") throw new Error(`${this.name} hit the length limit before finishing`);
    if (!reply.content.trim()) throw new Error(`${this.name} returned no text (finish ${reply.finish_reason ?? "none"})`);
    const u = reply.usage ?? {};
    let cost = typeof u.cost === "number" ? u.cost : null;
    let source = "usage.cost";
    if (cost === null && reply.id) {
      const g = await this.generation(reply.id);
      if (g && typeof g.total_cost === "number") {
        cost = g.total_cost;
        source = "generation endpoint";
      }
    }
    // A missing cost is an error: recording it as free would hide spend.
    if (cost === null) throw new Error(`OpenRouter reported no cost for ${reply.id ?? "the request"}`);
    return {
      text: reply.content.trim(),
      model: reply.model ?? this.name,
      input_tokens: u.prompt_tokens ?? 0,
      output_tokens: u.completion_tokens ?? 0,
      cache_read_tokens: u.prompt_tokens_details?.cached_tokens ?? 0,
      cost_usd: cost,
      cost_source: source,
      served_tier: reply.service_tier ?? null,
      reasoning_tokens: u.completion_tokens_details?.reasoning_tokens ?? 0,
      ...(reply.provider ? { provider: reply.provider } : {}),
      ...(reply.id ? { generation_id: reply.id } : {}),
      latency_ms: Date.now() - started,
    };
  }

  /** The generation record (`GET /generation?id=`). It can lag the reply by a few seconds. */
  async generation(id: string): Promise<Record<string, unknown> | null> {
    for (let attempt = 0; attempt < 4; attempt++) {
      const r = await this.fetchFn(`${this.url}/generation?id=${encodeURIComponent(id)}`, { headers: this.headers(), signal: AbortSignal.timeout(30_000) });
      if (r.status === 200) return ((await r.json()) as { data?: Record<string, unknown> }).data ?? null;
      await this.sleep(1_500 * (attempt + 1));
    }
    return null;
  }
}
