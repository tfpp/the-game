import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import * as path from "node:path";
import * as os from "node:os";
import { fileURLToPath } from "node:url";
import { encodeLine, onLines } from "./jsonl";

export interface CallbackMessage {
  kind: "callback";
  id: string;
  callId: string;
  method: string;
  value: unknown;
}
export interface RequestHandlers {
  signal?: AbortSignal;
  event?(value: unknown): void;
  callback?(method: string, value: unknown, signal: AbortSignal): Promise<unknown>;
}
interface Pending {
  resolve(value: unknown): void;
  reject(error: Error): void;
  handlers: RequestHandlers;
  cleanup(): void;
  callbacks: Map<string, AbortController>;
}
interface WireMessage {
  kind: "result" | "error" | "event" | "callback" | "cancelCallback";
  id: string;
  callId?: string;
  method?: string;
  value?: unknown;
  error?: string;
}

/** Private stdio transport: no TCP listener, tokens in argv, or transcript logging. */
export class Bridge {
  #child?: ChildProcessWithoutNullStreams;
  #detachLines?: () => void;
  #pending = new Map<string, Pending>();
  #sequence = 0;
  #worker: string;
  #env?: NodeJS.ProcessEnv;
  #closing: Promise<void> = Promise.resolve();

  constructor(worker = fileURLToPath(new URL("../runtime/worker.ts", import.meta.url)), env?: NodeJS.ProcessEnv) {
    this.#worker = worker;
    this.#env = env;
  }

  #start(): void {
    if (this.#child) return;
    const env = this.#env ?? process.env;
    const state = path.resolve(env.PI_OMP_STATE_DIR ?? fileURLToPath(new URL("../state", import.meta.url)));
    const child = spawn(env.PI_OMP_BUN ?? "bun", [this.#worker], {
      cwd: path.dirname(this.#worker), stdio: ["pipe", "pipe", "pipe"],
      env: { ...env, PI_OMP_STATE_DIR: state, OMP_PROFILE: "", PI_PROFILE: "",
        PI_CONFIG_DIR: path.relative(os.homedir(), state), PI_CODING_AGENT_DIR: path.join(state, "agent") },
    });
    this.#child = child;
    // Never echo backend stderr: authentication errors may contain response bodies.
    child.stderr.resume();
    this.#detachLines = onLines(child.stdout, line => {
      if (this.#child !== child) return;
      try {
        const message = JSON.parse(line) as WireMessage;
        if (!message || typeof message.id !== "string" || typeof message.kind !== "string") {
          throw new Error("Invalid runtime protocol");
        }
        this.#receive(message);
      } catch {
        this.close(new Error("Anthropic OMP runtime emitted invalid protocol data"));
      }
    });
    child.stdin.on("error", () => {
      if (this.#child === child) this.close(new Error("Anthropic OMP runtime pipe closed"));
    });
    child.on("error", () => {
      if (this.#child === child) this.close(new Error("Cannot start the Anthropic OMP runtime. Check that Bun is installed."));
    });
    child.on("close", code => {
      if (this.#child === child) this.close(new Error(`Anthropic OMP runtime exited (${code ?? "signal"}). Run its offline checks.`));
    });
  }

  #send(message: object): void {
    if (!this.#child || this.#child.stdin.destroyed) throw new Error("Anthropic OMP runtime is unavailable");
    this.#child.stdin.write(encodeLine(message));
  }

  #receive(message: WireMessage): void {
    const pending = this.#pending.get(message.id);
    if (!pending) return;
    if (message.kind === "event") {
      try { pending.handlers.event?.(message.value); }
      catch (error) {
        this.#send({ kind: "cancel", id: message.id });
        this.#settle(message.id, undefined, error instanceof Error ? error : new Error(String(error)));
      }
      return;
    }
    if (message.kind === "cancelCallback") {
      if (message.callId) pending.callbacks.get(message.callId)?.abort();
      return;
    }
    if (message.kind === "callback" && message.callId && message.method) {
      const callId = message.callId;
      const controller = new AbortController();
      pending.callbacks.set(callId, controller);
      const signal = pending.handlers.signal
        ? AbortSignal.any([controller.signal, pending.handlers.signal]) : controller.signal;
      void (async () => {
        try {
          if (!pending.handlers.callback) throw new Error(`Unhandled runtime callback: ${message.method}`);
          const value = await pending.handlers.callback(message.method!, message.value, signal);
          if (this.#pending.has(message.id)) this.#send({ kind: "reply", id: message.id, callId, value });
        } catch (error) {
          if (this.#pending.has(message.id)) this.#send({ kind: "reply", id: message.id, callId, error: error instanceof Error ? error.message : String(error) });
        } finally { pending.callbacks.delete(callId); }
      })();
      return;
    }
    if (message.kind === "result") this.#settle(message.id, message.value);
    else if (message.kind === "error") this.#settle(message.id, undefined, new Error(message.error ?? "Anthropic OMP request failed"));
    else throw new Error("Unknown runtime message");
  }

  #settle(id: string, value?: unknown, error?: Error): void {
    const pending = this.#pending.get(id);
    if (!pending) return;
    this.#pending.delete(id);
    pending.cleanup();
    for (const controller of pending.callbacks.values()) controller.abort();
    if (error) pending.reject(error); else pending.resolve(value);
  }

  request<T>(method: string, value: unknown, handlers: RequestHandlers = {}): Promise<T> {
    handlers.signal?.throwIfAborted();
    this.#start();
    const id = String(++this.#sequence);
    const { promise, resolve, reject } = Promise.withResolvers<unknown>();
    const abort = () => {
      if (!this.#pending.has(id)) return;
      this.#send({ kind: "cancel", id });
      this.#settle(id, undefined, new DOMException("Request aborted", "AbortError"));
    };
    this.#pending.set(id, {
      resolve, reject, handlers, callbacks: new Map(),
      cleanup: () => handlers.signal?.removeEventListener("abort", abort),
    });
    handlers.signal?.addEventListener("abort", abort, { once: true });
    try {
      if (handlers.signal?.aborted) abort();
      else this.#send({ kind: "request", id, method, value });
    } catch (error) { this.#settle(id, undefined, error instanceof Error ? error : new Error(String(error))); }
    return promise as Promise<T>;
  }

  close(error = new Error("Anthropic OMP runtime stopped")): Promise<void> {
    const child = this.#child;
    this.#child = undefined;
    this.#detachLines?.();
    this.#detachLines = undefined;
    for (const id of this.#pending.keys()) this.#settle(id, undefined, error);
    if (child && child.exitCode === null && child.signalCode === null) {
      const { promise, resolve } = Promise.withResolvers<void>();
      this.#closing = promise;
      const timer = setTimeout(() => { if (child.exitCode === null) child.kill("SIGKILL"); }, 2000);
      timer.unref();
      child.once("close", () => { clearTimeout(timer); resolve(); });
      child.stdin.end();
      child.kill("SIGTERM");
    }
    return this.#closing;
  }
}
