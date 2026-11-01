// Stdio entry point: JSON lines in on stdin, JSON lines out on stdout, logs on stderr.

import { AppBridge } from "./bridge.js";
import { loadConfig, type Config } from "./config.js";
import { postReview, recordPosted, type GhRunner } from "./github.js";
import { layoutDiagram } from "./layout.js";
import { LineWriter, log, readLines, type AppMessage, type RequestId, type SidecarMessage } from "./protocol.js";
import { SessionManager } from "./sessions.js";

export interface Router {
  handle(m: AppMessage): Promise<void>;
  sessions: SessionManager;
  bridge: AppBridge;
}

export function createRouter(p: { config: Config; send: (m: SidecarMessage) => void; sessions?: SessionManager; gh?: GhRunner }): Router {
  const { config, send } = p;
  const bridge = new AppBridge(send);
  const sessions = p.sessions ?? new SessionManager({ config, send, bridge });
  const reply = (id: RequestId | undefined, result: unknown) => {
    if (id !== undefined) send({ type: "response", id, result });
  };

  async function handle(m: AppMessage): Promise<void> {
    switch (m.type) {
      case "session.open": {
        const r = await sessions.open({ scope: m.scope, resume: m.resume, fork: m.fork, fresh: m.fresh, cwd: m.cwd });
        reply(m.id, r);
        return;
      }
      case "session.send":
        await sessions.send(m.session, m.text, m.chips);
        reply(m.id, { queued: true });
        return;
      case "session.interrupt":
        await sessions.interrupt(m.session);
        reply(m.id, { interrupted: true });
        return;
      case "session.close": {
        const notes = await sessions.close(m.session, m.propose_notes);
        reply(m.id, { closed: true, proposed: notes.length });
        return;
      }
      case "notes.keep":
        reply(m.id, await sessions.keepNotes(m.session, m.notes));
        return;
      case "layout":
        reply(m.id, await layoutDiagram(m.diagram, { ...(m.options ?? {}), sizes: m.sizes }));
        return;
      case "review.post": {
        const result = await postReview({ pr: m.pr, notes: m.notes, repo: m.repo, body: m.body, ...(p.gh ? { gh: p.gh } : {}) });
        const recorded = await recordPosted(config.wordbase, m.pr, result.comments).catch((e: Error) => {
          log("could not record github_comment_id in notes.jsonl:", e.message);
          return 0;
        });
        reply(m.id, { ...result, recorded });
        return;
      }
      case "app.response":
        if (!bridge.handleResponse(m)) log(`app.response ${m.id} matches no waiting request (late or unknown)`);
        return;
    }
  }

  return { handle, sessions, bridge };
}

async function main(): Promise<void> {
  const config = loadConfig();
  const writer = new LineWriter(process.stdout);
  const router = createRouter({ config, send: (m) => writer.send(m) });
  process.on("uncaughtException", (e) => log("uncaught exception:", e));
  process.on("unhandledRejection", (e) => log("unhandled rejection:", e));
  log(`sidecar ready (root ${config.root}, wordbase ${config.wordbase}, state ${config.state})`);
  await readLines(process.stdin, writer, (m) => router.handle(m));
  log("stdin closed; shutting down");
  router.bridge.cancelAll("the sidecar is shutting down");
  await router.sessions.shutdown();
}

const isEntry = import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("/main.js");
if (isEntry) {
  main().catch((e) => {
    log("fatal:", e);
    process.exitCode = 1;
  });
}
