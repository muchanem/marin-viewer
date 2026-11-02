import { execFileSync, spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { isBrokenPipe } from "./main.js";

const built = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "dist", "main.js");

function alive(pid: number): boolean {
  return spawnSync("ps", ["-p", String(pid), "-o", "pid="]).stdout.toString().trim() !== "";
}

describe("sidecar lifetime", () => {
  it("recognises a broken pipe", () => {
    expect(isBrokenPipe(Object.assign(new Error("write EPIPE"), { code: "EPIPE" }))).toBe(true);
    expect(isBrokenPipe(new Error("other"))).toBe(false);
    expect(isBrokenPipe(null)).toBe(false);
  });

  // The app owns the sidecar's pipes. When the app dies, the sidecar must exit, not spin.
  it.skipIf(!existsSync(built))("exits when its parent dies", async () => {
    // A stand-in app spawns the sidecar on pipes, lets it start, then exits without closing them,
    // the way the app does when it crashes or a test host quits.
    const app = `const c = require("node:child_process").spawn(process.execPath, [${JSON.stringify(built)}], { stdio: "pipe", detached: true });
setTimeout(() => { console.log(c.pid); process.exit(0); }, 1500);`;
    const pid = Number(execFileSync(process.execPath, ["-e", app]).toString().trim());
    expect(pid).toBeGreaterThan(0);
    const deadline = Date.now() + 8_000;
    while (alive(pid) && Date.now() < deadline) await new Promise((r) => setTimeout(r, 200));
    const stillAlive = alive(pid);
    if (stillAlive) spawnSync("kill", [String(pid)]);
    expect(stillAlive).toBe(false);
  }, 15_000);
});
