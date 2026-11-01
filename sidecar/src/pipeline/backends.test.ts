import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { FleetHold, GlmBackend, parseEngineMetrics, shedReason, TunnelDown, type FleetSample } from "./backends.js";

function worker(kv: number, waiting = 0, running = 1, pre = 0) {
  return {
    healthy: true,
    text: [
      `vllm:kv_cache_usage_perc{engine="0"} ${kv}`,
      `vllm:num_requests_waiting{engine="0"} ${waiting}`,
      `vllm:num_requests_running{engine="0"} ${running}`,
      `vllm:num_preemptions_total{engine="0"} ${pre}`,
    ].join("\n"),
  };
}

const sample = (over: Partial<FleetSample> = {}): FleetSample => ({ kv_median: 0.2, kv_max: 0.3, hot_waiting: 0, waiting: 0, running: 3, preemptions: 10, workers: 3, ...over });

describe("engine metrics and the shed rule", () => {
  it("parses per-worker Prometheus text and skips unhealthy workers", () => {
    const s = parseEngineMetrics({ workers: { a: worker(0.1, 0, 2, 5), b: worker(0.9, 3, 4, 7), c: worker(0.3), d: { healthy: false, text: worker(1).text } } });
    expect(s).toEqual({ kv_median: 0.3, kv_max: 0.9, hot_waiting: 1, waiting: 3, running: 7, preemptions: 12, workers: 3 });
  });

  it("fails closed on a scrape without workers or KV", () => {
    expect(() => parseEngineMetrics({})).toThrow();
    expect(shedReason(sample({ workers: 0 }), null)).toMatch(/no healthy workers/);
    expect(shedReason(sample({ kv_median: null }), null)).toMatch(/no KV readings/);
  });

  it("sheds on the median line, a hot node with waiting work, and rising preemptions", () => {
    expect(shedReason(sample(), null)).toBeNull();
    expect(shedReason(sample({ kv_median: 0.71 }), null)).toMatch(/above 0.7/);
    expect(shedReason(sample({ kv_median: 0.7 }), null)).toBeNull();
    expect(shedReason(sample({ hot_waiting: 1 }), null)).toMatch(/0.85/);
    expect(shedReason(sample({ preemptions: 11 }), 10)).toMatch(/preemptions rose from 10 to 11/);
    // A cumulative counter summed over a varying set can fall; only a new maximum counts.
    expect(shedReason(sample({ preemptions: 8 }), 10)).toBeNull();
  });
});

describe("GlmBackend", () => {
  beforeEach(() => {
    process.env.GLM_BULK_TOKEN = "bulk-test";
    process.env.GLM_API_TOKEN = "admin-test";
  });
  afterEach(() => {
    delete process.env.GLM_BULK_TOKEN;
    delete process.env.GLM_API_TOKEN;
  });

  type Route = (url: string, init?: RequestInit) => { status: number; body: unknown } | Error;
  const fetcher = (route: Route, seen: string[] = []) =>
    (async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      seen.push(`${init?.method ?? "GET"} ${url.replace("http://glm", "")} ${(init?.headers as Record<string, string> | undefined)?.Authorization ?? ""}`);
      const r = route(url, init);
      if (r instanceof Error) throw r;
      return new Response(typeof r.body === "string" ? r.body : JSON.stringify(r.body), { status: r.status });
    }) as typeof fetch;

  const healthy: Route = (url) => {
    if (url.endsWith("/health")) return { status: 200, body: { status: "ok", workers: { high: 1, bulk: 2 } } };
    if (url.endsWith("/admin/engines/metrics")) return { status: 200, body: { workers: { a: worker(0.1), b: worker(0.2) } } };
    if (url.endsWith("/v1/chat/completions")) return { status: 200, body: { model: "glm-5.3", choices: [{ message: { content: "<think>x</think>{\"a\":1}" }, finish_reason: "stop" }], usage: { prompt_tokens: 100, completion_tokens: 20 } } };
    return { status: 404, body: "no" };
  };

  it("gates on /health workers and the shed rule, then completes on the bulk token", async () => {
    const seen: string[] = [];
    const g = new GlmBackend({ url: "http://glm", fetchFn: fetcher(healthy, seen), log: () => {} });
    const c = await g.complete([{ role: "user", content: "hi" }]);
    expect(c.text).toBe('{"a":1}');
    expect(c.input_tokens).toBe(100);
    expect(c.cost_usd).toBe(0);
    expect(seen).toEqual(["GET /health ", "GET /admin/engines/metrics Bearer admin-test", "POST /v1/chat/completions Bearer bulk-test"]);
  });

  it("holds on a non-200 and on too few workers, then fails with FleetHold", async () => {
    let n = 0;
    const route: Route = (url) => (url.endsWith("/health") ? (n++ % 2 ? { status: 200, body: { workers: { bulk: 0 } } } : { status: 503, body: "relay" }) : healthy(url));
    const holds: string[] = [];
    const g = new GlmBackend({ url: "http://glm", fetchFn: fetcher(route), log: (l) => holds.push(l), holdMs: 0, sleep: async () => {} });
    expect(await g.gate()).toMatch(/answered 503/);
    expect(await g.gate()).toMatch(/workers.bulk=0/);
    await expect(g.complete([{ role: "user", content: "hi" }])).rejects.toBeInstanceOf(FleetHold);
    expect(holds.some((l) => l.startsWith("glm hold:"))).toBe(true);
  });

  it("holds while the fleet sheds and sends once it clears", async () => {
    let calls = 0;
    const route: Route = (url) => (url.endsWith("/admin/engines/metrics") ? { status: 200, body: { workers: { a: worker(calls++ ? 0.1 : 0.8), b: worker(calls > 1 ? 0.1 : 0.8) } } } : healthy(url));
    const log: string[] = [];
    const g = new GlmBackend({ url: "http://glm", fetchFn: fetcher(route), log: (l) => log.push(l), sleep: async () => {} });
    await g.complete([{ role: "user", content: "hi" }]);
    expect(log.some((l) => l.startsWith("glm hold: median node KV 0.800"))).toBe(true);
  });

  it("tells a dead port-forward apart from a dead fleet", async () => {
    const refused = Object.assign(new TypeError("fetch failed"), { cause: { code: "ECONNREFUSED" } });
    const g = new GlmBackend({ url: "http://glm", fetchFn: fetcher(() => refused), log: () => {} });
    await expect(g.gate()).rejects.toBeInstanceOf(TunnelDown);
  });

  it("reports a 403 from the admin path as a hold reason, never as an empty read", async () => {
    const route: Route = (url) => (url.endsWith("/admin/engines/metrics") ? { status: 403, body: "primary token required" } : healthy(url));
    const g = new GlmBackend({ url: "http://glm", fetchFn: fetcher(route), log: () => {} });
    expect(await g.gate()).toMatch(/answered 403/);
  });
});
