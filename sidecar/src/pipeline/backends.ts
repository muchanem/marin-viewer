// Text backends for description runs: Claude on the Console API key, and GLM-5.3 through its router
// (Marin's CLAUDE.md section 11). Both take a list of chat turns and return text, usage, cost and
// latency. Neither has tools: the unit prompt carries everything the model reads.

import { readFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import Anthropic from "@anthropic-ai/sdk";
import { parseDotenv, type Config } from "../config.js";
import { costUsd, PRICES } from "./pricing.js";

export interface Turn {
  role: "user" | "assistant";
  content: string;
}

export interface Completion {
  text: string;
  model: string;
  input_tokens: number;
  output_tokens: number;
  cache_read_tokens: number;
  cost_usd: number;
  latency_ms: number;
  /** Where `cost_usd` came from, when the backend does not compute it from a price table. */
  cost_source?: string;
  /** The service tier the provider reports serving, for backends that take one. */
  served_tier?: string | null;
  reasoning_tokens?: number;
  /** The upstream provider that served the request, as OpenRouter reports it. */
  provider?: string;
  generation_id?: string;
}

export interface CompleteOptions {
  maxTokens?: number;
  system?: string;
  /** Claude only: false sends no cache breakpoint, for a prompt that is read once. */
  cache?: boolean;
  /**
   * Claude only: a prefix of the first turn to send as its own block with a cache breakpoint, so a
   * second call that shares it reads it from cache. Implies no automatic breakpoint.
   */
  cachePrefix?: string;
  /** Claude only: a JSON schema the reply must follow (structured outputs, `output_config.format`). */
  jsonSchema?: Record<string, unknown>;
}

export interface Backend {
  /** A short label for summaries and the ledger, such as `claude-sonnet-5-5` or `glm-5.3`. */
  readonly name: string;
  complete(turns: Turn[], opts?: CompleteOptions): Promise<Completion>;
}

// ---------------------------------------------------------------------------
// Claude

export function apiKey(config: Config): string {
  let text: string;
  try {
    text = readFileSync(config.envFile, "utf8");
  } catch {
    throw new Error(`cannot read ${config.envFile}; background runs need CLAUDE_API_KEY there`);
  }
  const key = parseDotenv(text).CLAUDE_API_KEY;
  if (!key) throw new Error(`CLAUDE_API_KEY is not set in ${config.envFile}`);
  return key;
}

export class ClaudeBackend implements Backend {
  private readonly client: Anthropic;

  constructor(
    config: Config,
    readonly name: string = "claude-sonnet-5-5",
    private readonly effort: "low" | "medium" | "high" = "medium",
    client?: Anthropic,
  ) {
    this.client = client ?? new Anthropic({ apiKey: apiKey(config), maxRetries: 3, timeout: 20 * 60_000 });
  }

  async complete(turns: Turn[], opts: CompleteOptions = {}): Promise<Completion> {
    const started = Date.now();
    // Streaming keeps long outputs clear of HTTP timeouts. `fallbacks: "default"` lets the API rerun a
    // refused request on another model inside the same call.
    const stream = this.client.beta.messages.stream({
      model: this.name,
      max_tokens: opts.maxTokens ?? 32_000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: this.effort, ...(opts.jsonSchema ? { format: { type: "json_schema", schema: opts.jsonSchema } } : {}) },
      // The rewrite and fix turns resend the whole unit context; the automatic breakpoint lets them read it from cache.
      ...(opts.cache === false || opts.cachePrefix ? {} : { cache_control: { type: "ephemeral" } }),
      ...(opts.system ? { system: opts.system } : {}),
      messages: turns.map((t, i) =>
        i === 0 && opts.cachePrefix && t.content.startsWith(opts.cachePrefix) && t.content.length > opts.cachePrefix.length
          ? {
              role: t.role,
              content: [
                { type: "text", text: opts.cachePrefix, cache_control: { type: "ephemeral" } },
                { type: "text", text: t.content.slice(opts.cachePrefix.length) },
              ],
            }
          : { role: t.role, content: t.content },
      ),
    } as Anthropic.Beta.Messages.MessageCreateParamsStreaming);
    const msg = await stream.finalMessage();
    if (msg.stop_reason === "refusal") throw new Error(`${this.name} refused the request (${msg.stop_details?.category ?? "no category"})`);
    if (msg.stop_reason === "max_tokens") throw new Error(`${this.name} hit max_tokens (${opts.maxTokens ?? 32_000}) before finishing`);
    const text = msg.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
    const usage = {
      input_tokens: msg.usage.input_tokens,
      output_tokens: msg.usage.output_tokens,
      cache_read_input_tokens: msg.usage.cache_read_input_tokens ?? 0,
      cache_creation_input_tokens: msg.usage.cache_creation_input_tokens ?? 0,
    };
    // A fallback bills at the serving model's rates; price on the model that answered when known.
    const served = msg.model in PRICES ? msg.model : this.name;
    return {
      text,
      model: msg.model,
      input_tokens: usage.input_tokens + usage.cache_read_input_tokens + usage.cache_creation_input_tokens,
      output_tokens: usage.output_tokens,
      cache_read_tokens: usage.cache_read_input_tokens,
      cost_usd: costUsd(served, usage),
      latency_ms: Date.now() - started,
    };
  }
}

// ---------------------------------------------------------------------------
// GLM-5.3

export class TunnelDown extends Error {}
export class FleetHold extends Error {}

export interface FleetSample {
  kv_median: number | null;
  kv_max: number | null;
  /** Nodes above 0.85 KV with requests waiting on them. */
  hot_waiting: number;
  waiting: number;
  running: number;
  preemptions: number;
  /** Healthy workers in the scrape. */
  workers: number;
}

const METRIC = /^(vllm:[a-z_]+)\{[^}]*\}\s+([0-9.eE+-]+)\s*$/gm;

/** Parse `/admin/engines/metrics` (JSON with each worker's Prometheus text under `.workers[addr].text`). */
export function parseEngineMetrics(doc: unknown): FleetSample {
  const workers = (doc as { workers?: Record<string, { healthy?: boolean; text?: string }> } | null)?.workers;
  if (!workers || typeof workers !== "object") throw new Error("engine metrics have no workers object");
  const kv: number[] = [];
  let hot = 0;
  let waiting = 0;
  let running = 0;
  let pre = 0;
  let n = 0;
  for (const w of Object.values(workers)) {
    if (!w?.healthy) continue;
    n++;
    const vals: Record<string, number[]> = {};
    for (const m of (w.text ?? "").matchAll(METRIC)) (vals[m[1]!] ??= []).push(Number(m[2]));
    const nodeKv = vals["vllm:kv_cache_usage_perc"]?.length ? Math.max(...vals["vllm:kv_cache_usage_perc"]) : null;
    const nodeWaiting = (vals["vllm:num_requests_waiting"] ?? []).reduce((a, b) => a + b, 0);
    if (nodeKv !== null) {
      kv.push(nodeKv);
      if (nodeKv > 0.85 && nodeWaiting > 0) hot++;
    }
    waiting += nodeWaiting;
    running += (vals["vllm:num_requests_running"] ?? []).reduce((a, b) => a + b, 0);
    pre += (vals["vllm:num_preemptions_total"] ?? []).reduce((a, b) => a + b, 0);
  }
  const sorted = [...kv].sort((a, b) => a - b);
  const median = sorted.length ? (sorted.length % 2 ? sorted[(sorted.length - 1) / 2]! : (sorted[sorted.length / 2 - 1]! + sorted[sorted.length / 2]!) / 2) : null;
  return { kv_median: median, kv_max: sorted.length ? sorted.at(-1)! : null, hot_waiting: hot, waiting, running, preemptions: pre, workers: n };
}

/** The median KV line. 0.70 is the strict line; nothing here reads positive evidence that the high pool is empty. */
export const SHED_MEDIAN = 0.7;

/**
 * The shed rule: median node KV above the line, any node above 0.85 with requests waiting, or
 * preemptions above the highest count seen so far. Missing KV fails closed.
 */
export function shedReason(s: FleetSample, maxPreemptionsSeen: number | null): string | null {
  if (s.workers === 0) return "no healthy workers in the engine metrics";
  if (s.kv_median === null) return "engine metrics carry no KV readings";
  if (s.kv_median > SHED_MEDIAN) return `median node KV ${s.kv_median.toFixed(3)} is above ${SHED_MEDIAN}`;
  if (s.hot_waiting > 0) return `${s.hot_waiting} node(s) above 0.85 KV with requests waiting`;
  if (maxPreemptionsSeen !== null && s.preemptions > maxPreemptionsSeen) return `preemptions rose from ${maxPreemptionsSeen} to ${s.preemptions}`;
  return null;
}

function readToken(file: string, key: string): string {
  let text: string;
  try {
    text = readFileSync(file, "utf8");
  } catch {
    throw new Error(`cannot read ${file}; GLM-5.3 needs ${key} there`);
  }
  const v = parseDotenv(text)[key] ?? (text.trim().includes("=") ? undefined : text.trim());
  if (!v) throw new Error(`${key} is not set in ${file}`);
  return v;
}

export interface GlmOptions {
  url?: string;
  pool?: string;
  model?: string;
  /** How long a hold (non-200, too few workers, shed) may last before the call fails. */
  holdMs?: number;
  pollMs?: number;
  log?: (line: string) => void;
  fetchFn?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
}

export class GlmBackend implements Backend {
  readonly name: string;
  private readonly url: string;
  private readonly pool: string;
  private readonly bulkToken: string;
  private readonly adminToken: string;
  private readonly fetchFn: typeof fetch;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly log: (line: string) => void;
  private maxPreemptions: number | null = null;

  constructor(private readonly opts: GlmOptions = {}) {
    this.url = (opts.url ?? process.env.GLM_URL ?? "http://127.0.0.1:18000").replace(/\/$/, "");
    this.pool = opts.pool ?? "bulk";
    this.name = opts.model ?? "glm-5.3";
    const dir = process.env.GLM_TOKEN_DIR ?? path.join(os.homedir(), "openathena", "glm-infer");
    this.bulkToken = process.env.GLM_BULK_TOKEN ?? readToken(path.join(dir, "glm_bulk_token.txt"), "GLM_BULK_TOKEN");
    this.adminToken = process.env.GLM_API_TOKEN ?? readToken(path.join(dir, "glm_api_token.txt"), "GLM_API_TOKEN");
    this.fetchFn = opts.fetchFn ?? fetch;
    this.sleep = opts.sleep ?? ((ms) => new Promise((r) => setTimeout(r, ms)));
    this.log = opts.log ?? ((l) => process.stderr.write(`${l}\n`));
  }

  private async get(pathname: string, token?: string): Promise<{ status: number; body: string }> {
    try {
      const r = await this.fetchFn(`${this.url}${pathname}`, { headers: token ? { Authorization: `Bearer ${token}` } : {}, signal: AbortSignal.timeout(60_000) });
      return { status: r.status, body: await r.text() };
    } catch (e) {
      const cause = (e as { cause?: { code?: string } }).cause;
      if (cause?.code === "ECONNREFUSED") throw new TunnelDown(`connection refused at ${this.url}: the kubectl port-forward is down (the fleet may be fine)`);
      throw e;
    }
  }

  /** One gate reading: null when requests may go, else the reason to hold. */
  async gate(): Promise<string | null> {
    const h = await this.get("/health");
    if (h.status !== 200) return `/health answered ${h.status}: ${h.body.slice(0, 160)}`;
    let workers: number | undefined;
    try {
      workers = (JSON.parse(h.body) as { workers?: Record<string, number> }).workers?.[this.pool];
    } catch {
      return "/health body is not JSON";
    }
    if (typeof workers !== "number" || workers < 1) return `/health reports workers.${this.pool}=${workers ?? "missing"}, need >= 1`;
    const m = await this.get("/admin/engines/metrics", this.adminToken);
    if (m.status !== 200) return `/admin/engines/metrics answered ${m.status}: ${m.body.slice(0, 160)}`;
    let sample: FleetSample;
    try {
      sample = parseEngineMetrics(JSON.parse(m.body));
    } catch (e) {
      return `engine metrics unreadable: ${(e as Error).message}`;
    }
    const reason = shedReason(sample, this.maxPreemptions);
    this.maxPreemptions = Math.max(this.maxPreemptions ?? sample.preemptions, sample.preemptions);
    this.log(
      `glm gate: workers.${this.pool}=${workers} kv_median=${sample.kv_median?.toFixed(3)} (line ${SHED_MEDIAN}, strict) kv_max=${sample.kv_max?.toFixed(3)} waiting=${sample.waiting} hot_waiting=${sample.hot_waiting} preemptions=${sample.preemptions}${reason ? ` SHED: ${reason}` : ""}`,
    );
    return reason;
  }

  /** Wait until the gate opens. Holds on every non-200; fails only after `holdMs`. */
  async waitForGate(): Promise<void> {
    const deadline = Date.now() + (this.opts.holdMs ?? 10 * 60_000);
    for (;;) {
      const reason = await this.gate();
      if (!reason) return;
      this.log(`glm hold: ${reason}`);
      if (Date.now() >= deadline) throw new FleetHold(`GLM-5.3 held for ${Math.round((this.opts.holdMs ?? 600_000) / 1000)} s: ${reason}`);
      await this.sleep(this.opts.pollMs ?? 30_000);
    }
  }

  async complete(turns: Turn[], opts: { maxTokens?: number; system?: string } = {}): Promise<Completion> {
    await this.waitForGate();
    const started = Date.now();
    const messages = [...(opts.system ? [{ role: "system", content: opts.system }] : []), ...turns];
    let r: Response;
    try {
      r = await this.fetchFn(`${this.url}/v1/chat/completions`, {
        method: "POST",
        headers: { Authorization: `Bearer ${this.bulkToken}`, "Content-Type": "application/json" },
        // No max_tokens unless asked: the deployed vLLM then allows the remaining context, and reasoning
        // spends from the same budget (agent-docs/glm53-fleet-log.md, the 2026-10-23 output-length audit).
        // Streamed, so the headers arrive at once: a non-streaming reply sends them only when generation ends,
        // and Node's fetch gives up on headers after 300 s.
        body: JSON.stringify({ model: this.name, messages, ...(opts.maxTokens ? { max_tokens: opts.maxTokens } : {}), stream: true, stream_options: { include_usage: true } }),
        signal: AbortSignal.timeout(30 * 60_000),
      });
    } catch (e) {
      if ((e as { cause?: { code?: string } }).cause?.code === "ECONNREFUSED") throw new TunnelDown(`connection refused at ${this.url}: the port-forward died`);
      throw e;
    }
    if (r.status !== 200) throw new FleetHold(`chat completion answered ${r.status}: ${(await r.text()).slice(0, 300)}`);
    const doc = await readCompletion(r);
    const choice = doc.choices?.[0];
    if (!choice) throw new Error("glm-5.3 returned no choices");
    if (choice?.finish_reason === "length") throw new Error(`glm-5.3 hit the length limit (${opts.maxTokens ? `max_tokens ${opts.maxTokens}` : "remaining context"}) before finishing`);
    const text = (choice?.message?.content ?? "").replace(/<think>[\s\S]*?<\/think>/g, "").trim();
    return {
      text,
      model: doc.model ?? this.name,
      input_tokens: doc.usage?.prompt_tokens ?? 0,
      output_tokens: doc.usage?.completion_tokens ?? 0,
      cache_read_tokens: doc.usage?.prompt_tokens_details?.cached_tokens ?? 0,
      // The fleet is self-hosted; requests carry no per-token charge.
      cost_usd: 0,
      latency_ms: Date.now() - started,
    };
  }
}

interface ChatDoc {
  model?: string;
  choices?: { message?: { content?: string | null }; finish_reason?: string }[];
  usage?: { prompt_tokens?: number; completion_tokens?: number; prompt_tokens_details?: { cached_tokens?: number } };
}

/** Reads an OpenAI-style chat completion, streamed as server-sent events or as one JSON document. */
export async function readCompletion(r: Response): Promise<ChatDoc> {
  const body = await r.text();
  if (!body.trimStart().startsWith("data:")) return JSON.parse(body) as ChatDoc;
  let content = "";
  let finish: string | undefined;
  let model: string | undefined;
  let usage: ChatDoc["usage"];
  let sawChoice = false;
  for (const line of body.split("\n")) {
    if (!line.startsWith("data:")) continue;
    const data = line.slice(5).trim();
    if (!data || data === "[DONE]") continue;
    const chunk = JSON.parse(data) as { model?: string; choices?: { delta?: { content?: string | null }; finish_reason?: string | null }[]; usage?: ChatDoc["usage"] };
    model ??= chunk.model;
    if (chunk.usage) usage = chunk.usage;
    for (const c of chunk.choices ?? []) {
      sawChoice = true;
      content += c.delta?.content ?? "";
      if (c.finish_reason) finish = c.finish_reason;
    }
  }
  return { ...(model ? { model } : {}), ...(usage ? { usage } : {}), choices: sawChoice ? [{ message: { content }, ...(finish ? { finish_reason: finish } : {}) }] : [] };
}
