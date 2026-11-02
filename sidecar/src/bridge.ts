// Requests from the sidecar to the app (`app.request`), answered by `app.response`.

import { randomUUID } from "node:crypto";
import type { RequestId, SidecarMessage } from "./protocol.js";

export type AppRequestName = "find_symbol" | "selection_context";

export class AppRequestError extends Error {}

interface Pending {
  resolve: (v: unknown) => void;
  reject: (e: Error) => void;
  timer: NodeJS.Timeout;
  name: string;
}

export class AppBridge {
  private readonly pending = new Map<string, Pending>();

  constructor(
    private readonly send: (m: SidecarMessage) => void,
    private readonly timeoutMs = 5000,
  ) {}

  request(name: AppRequestName, args: Record<string, unknown>): Promise<unknown> {
    const id = `req-${randomUUID()}`;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new AppRequestError(`the viewer did not answer ${name} within ${this.timeoutMs / 1000} s`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer, name });
      this.send({ type: "app.request", id, name, args });
    });
  }

  /** Returns false when no request with this id is waiting (late or unknown answer). */
  handleResponse(msg: { id: RequestId; result?: unknown; error?: string | undefined }): boolean {
    const key = String(msg.id);
    const p = this.pending.get(key);
    if (!p) return false;
    this.pending.delete(key);
    clearTimeout(p.timer);
    if (msg.error !== undefined) p.reject(new AppRequestError(`the viewer could not answer ${p.name}: ${msg.error}`));
    else p.resolve(msg.result);
    return true;
  }

  get size(): number {
    return this.pending.size;
  }

  cancelAll(reason: string): void {
    for (const [id, p] of this.pending) {
      clearTimeout(p.timer);
      p.reject(new AppRequestError(reason));
      this.pending.delete(id);
    }
  }
}
