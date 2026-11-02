// Paths and environment for the sidecar. Every path can be overridden through the environment,
// which is how tests and scratch runs keep away from the real wordbase and state.

import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url)); // sidecar/src or sidecar/dist

export interface Config {
  root: string; // ~/openathena/marin-viewer
  marin: string; // the Marin clone
  wordbase: string;
  state: string;
  prompts: string;
  envFile: string;
  /**
   * Where the OpenRouter key may live, tried in order: a variable name in a dotenv file. Defaults to
   * `OPENROUTER_API_KEY` in `envFile`, then `OR_KEY_SCALE_UP` in the parent directory's `.env`.
   */
  openRouterKeys?: KeySource[];
}

export interface KeySource {
  file: string;
  name: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const root = path.resolve(env.MARIN_VIEWER_ROOT ?? path.join(here, "..", ".."));
  return {
    root,
    marin: path.resolve(env.MARIN_VIEWER_MARIN ?? path.join(root, "marin")),
    wordbase: path.resolve(env.MARIN_VIEWER_WORDBASE ?? path.join(root, "wordbase")),
    state: path.resolve(env.MARIN_VIEWER_STATE ?? path.join(root, "state")),
    prompts: path.resolve(env.MARIN_VIEWER_PROMPTS ?? path.join(root, "prompts")),
    envFile: path.resolve(env.MARIN_VIEWER_ENV_FILE ?? path.join(root, ".env")),
    openRouterKeys: openRouterKeySources(root, env),
  };
}

/** `MARIN_VIEWER_OPENROUTER_ENV_FILE` and `MARIN_VIEWER_OPENROUTER_KEY_NAME` replace the first source. */
export function openRouterKeySources(root: string, env: NodeJS.ProcessEnv = process.env): KeySource[] {
  return [
    { file: path.resolve(env.MARIN_VIEWER_OPENROUTER_ENV_FILE ?? env.MARIN_VIEWER_ENV_FILE ?? path.join(root, ".env")), name: env.MARIN_VIEWER_OPENROUTER_KEY_NAME ?? "OPENROUTER_API_KEY" },
    { file: path.resolve(root, "..", ".env"), name: "OR_KEY_SCALE_UP" },
  ];
}

/**
 * The OpenRouter key and where it came from. The returned `source` names the file and variable and is
 * safe to print; the key never is. Throws, naming the places it looked, when no source has it.
 */
export function openRouterKey(config: Config): { key: string; source: string } {
  const sources = config.openRouterKeys ?? openRouterKeySources(config.root);
  for (const s of sources) {
    let text: string;
    try {
      text = readFileSync(s.file, "utf8");
    } catch {
      continue;
    }
    const key = parseDotenv(text)[s.name]?.trim();
    if (key) return { key, source: `${s.name} in ${s.file}` };
  }
  throw new Error(`no OpenRouter key: looked for ${sources.map((s) => `${s.name} in ${s.file}`).join(", then ")}`);
}

/** Parse a dotenv file into a map. Values are never logged. */
export function parseDotenv(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const m = /^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    let value = m[2]!;
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    } else {
      value = value.replace(/\s+#.*$/, "");
    }
    out[m[1]!] = value;
  }
  return out;
}

/** Interactive sessions use the `claude` login: no API key may reach them. */
export function interactiveEnv(base: NodeJS.ProcessEnv = process.env): Record<string, string> {
  const env: Record<string, string> = {};
  for (const [k, v] of Object.entries(base)) if (v !== undefined) env[k] = v;
  delete env.ANTHROPIC_API_KEY;
  delete env.CLAUDE_API_KEY;
  delete env.ANTHROPIC_AUTH_TOKEN;
  env.CLAUDE_AGENT_SDK_CLIENT_APP = "marin-viewer-sidecar/0.1.0";
  // No claude.ai connectors (Gmail, Drive, Docs, ...) in viewer sessions. `strictMcpConfig` alone
  // already keeps them out with the bundled CLI 2.1.302; this is the CLI's own switch, read via
  // its falsy-env check ("0", "false", "no", "off").
  env.ENABLE_CLAUDEAI_MCP_SERVERS = "false";
  return env;
}

/**
 * Background runs bill the Console key: `CLAUDE_API_KEY` from `.env`, passed as
 * `ANTHROPIC_API_KEY`. Throws (without the value) when the key is missing.
 */
export function backgroundEnv(config: Config, base: NodeJS.ProcessEnv = process.env): Record<string, string> {
  let text: string;
  try {
    text = readFileSync(config.envFile, "utf8");
  } catch {
    throw new Error(`cannot read ${config.envFile}; background runs need CLAUDE_API_KEY there`);
  }
  const key = parseDotenv(text).CLAUDE_API_KEY;
  if (!key) throw new Error(`CLAUDE_API_KEY is not set in ${config.envFile}`);
  const env = interactiveEnv(base);
  env.ANTHROPIC_API_KEY = key;
  return env;
}
