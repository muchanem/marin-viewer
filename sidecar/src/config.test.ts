import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { backgroundEnv, interactiveEnv, loadConfig, parseDotenv } from "./config.js";

const dirs: string[] = [];
afterEach(() => {
  for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true });
});

const base = { PATH: "/usr/bin", HOME: "/h", ANTHROPIC_API_KEY: "sk-parent", CLAUDE_API_KEY: "sk-parent-2", ANTHROPIC_AUTH_TOKEN: "tok" };

describe("session environments", () => {
  it("interactive: claude login only, no claude.ai connectors", () => {
    const env = interactiveEnv(base);
    expect(env.ANTHROPIC_API_KEY).toBeUndefined();
    expect(env.CLAUDE_API_KEY).toBeUndefined();
    expect(env.ANTHROPIC_AUTH_TOKEN).toBeUndefined();
    expect(env.ENABLE_CLAUDEAI_MCP_SERVERS).toBe("false");
    expect(env.PATH).toBe("/usr/bin");
    expect(env.CLAUDE_AGENT_SDK_CLIENT_APP).toMatch(/^marin-viewer-sidecar\//);
  });

  it("background: the .env key as ANTHROPIC_API_KEY, never the parent's, and no connectors", () => {
    const root = mkdtempSync(path.join(tmpdir(), "cfg-test-"));
    dirs.push(root);
    writeFileSync(path.join(root, ".env"), '# keys\nexport OTHER=1\nCLAUDE_API_KEY="sk-from-dotenv"\n');
    const env = backgroundEnv(loadConfig({ MARIN_VIEWER_ROOT: root }), base);
    expect(env.ANTHROPIC_API_KEY).toBe("sk-from-dotenv");
    expect(env.CLAUDE_API_KEY).toBeUndefined();
    expect(env.ENABLE_CLAUDEAI_MCP_SERVERS).toBe("false");
  });

  it("background: a missing key fails without echoing any value", () => {
    const root = mkdtempSync(path.join(tmpdir(), "cfg-test-"));
    dirs.push(root);
    writeFileSync(path.join(root, ".env"), "CLAUDE_STORAGE=sk-unrelated\n");
    expect(() => backgroundEnv(loadConfig({ MARIN_VIEWER_ROOT: root }), base)).toThrow(/CLAUDE_API_KEY is not set in .*\.env$/);
    try {
      backgroundEnv(loadConfig({ MARIN_VIEWER_ROOT: root }), base);
    } catch (e) {
      expect((e as Error).message).not.toMatch(/sk-/);
    }
  });

  it("parses dotenv lines", () => {
    expect(parseDotenv("A=1\nB='two words'\nC=3 # note\n#D=4\nexport E=5")).toEqual({ A: "1", B: "two words", C: "3", E: "5" });
  });
});
