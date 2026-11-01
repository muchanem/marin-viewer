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
  };
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
