import * as path from "node:path";
import { readJsonl } from "@oh-my-pi/pi-utils";
import { Backend, type StreamRequest } from "./backend";
import { encodeEvent } from "../src/event-wire";
import { encodeLine } from "../src/jsonl";
import snapshot from "./snapshot.json" with { type: "json" };

interface Incoming {
  kind: "request" | "reply" | "cancel";
  id: string;
  method?: string;
  callId?: string;
  value?: unknown;
  error?: string;
}
interface Operation { controller: AbortController; task: Promise<void> }
interface Reply { resolve(value: unknown): void; reject(error: Error): void }
const operations = new Map<string, Operation>();
const replies = new Map<string, Reply>();
let sequence = 0;
let backend: Promise<Backend> | undefined;
const stateDir = process.env.PI_OMP_STATE_DIR ?? path.resolve(import.meta.dir, "../state");

function send(value: object): void { process.stdout.write(encodeLine(value)); }
function safeError(error: unknown): string {
  return (error instanceof Error ? error.message : String(error))
    .replace(/sk-ant-[A-Za-z0-9_-]+/g, "[redacted]")
    .replace(/("(?:access_token|refresh_token)"\s*:\s*")[^"]*/g, "$1[redacted]");
}
function getBackend(): Promise<Backend> {
  return backend ??= Backend.create(path.join(stateDir, "auth.db"));
}
async function callback(id: string, method: string, value: unknown, signal: AbortSignal): Promise<unknown> {
  signal.throwIfAborted();
  const callId = String(++sequence);
  const { promise, resolve, reject } = Promise.withResolvers<unknown>();
  const key = `${id}:${callId}`;
  replies.set(key, { resolve, reject });
  const abort = () => {
    send({ kind: "cancelCallback", id, callId });
    reject(new DOMException("Request aborted", "AbortError"));
  };
  signal.addEventListener("abort", abort, { once: true });
  try {
    send({ kind: "callback", id, callId, method, value });
    if (signal.aborted) abort();
    return await promise;
  } finally {
    replies.delete(key);
    signal.removeEventListener("abort", abort);
  }
}
async function handle(message: Incoming, signal: AbortSignal): Promise<void> {
  const id = message.id;
  if (message.method === "health") {
    send({ kind: "result", id, value: { revision: snapshot.revision, runtime: Bun.version } });
    return;
  }
  const engine = await getBackend();
  signal.throwIfAborted();
  switch (message.method) {
    case "login": {
      const identity = await engine.login({
        signal,
        onAuth: info => send({ kind: "event", id, value: { type: "auth_url", url: info.launchUrl ?? info.url, instructions: info.instructions } }),
        onProgress: progress => send({ kind: "event", id, value: { type: "progress", message: progress } }),
        onPrompt: async prompt => String(await callback(id, "prompt", { type: "text", ...prompt }, signal)),
        onManualCodeInput: async promptSignal => String(await callback(id, "prompt", {
          type: "manual_code", message: "Paste the final redirect URL or authorization code (or complete login in your browser):",
          placeholder: "http://localhost:54545/callback",
        }, promptSignal ? AbortSignal.any([signal, promptSignal]) : signal)),
      });
      if (!identity) throw new Error("Anthropic login did not store a credential");
      send({ kind: "result", id, value: identity });
      return;
    }
    case "usage": {
      const sessionId = (message.value as { sessionId?: unknown } | null)?.sessionId;
      if (typeof sessionId !== "string" || !sessionId) throw new Error("Usage requires a session ID");
      send({ kind: "result", id, value: await engine.usage(sessionId, signal) });
      return;
    }
    case "status": send({ kind: "result", id, value: await engine.status() }); return;
    case "forget": await engine.forget(); send({ kind: "result", id, value: null }); return;
    case "stream": {
      const request = message.value as StreamRequest;
      const stream = engine.stream(request, signal, {
        onPayload: payload => callback(id, "payload", payload, signal),
        onResponse: async response => { await callback(id, "response", response, signal); },
      });
      for await (const event of stream) {
        if (event.type === "error" && event.error.errorMessage) event.error.errorMessage = safeError(event.error.errorMessage);
        send({ kind: "event", id, value: encodeEvent(event) });
      }
      send({ kind: "result", id, value: null });
      return;
    }
    default: throw new Error("Unknown Anthropic OMP operation");
  }
}

async function shutdown(): Promise<void> {
  for (const operation of operations.values()) operation.controller.abort();
  await Promise.allSettled([...operations.values()].map(operation => operation.task));
  if (backend) (await backend).close();
}
process.once("SIGTERM", () => { void shutdown().finally(() => process.exit(0)); });
process.once("SIGINT", () => { void shutdown().finally(() => process.exit(0)); });

for await (const message of readJsonl<Incoming>(Bun.stdin.stream())) {
  if (!message || typeof message.id !== "string") throw new Error("Invalid Anthropic OMP protocol");
  if (message.kind === "reply" && message.callId) {
    const reply = replies.get(`${message.id}:${message.callId}`);
    if (message.error !== undefined) reply?.reject(new Error(message.error)); else reply?.resolve(message.value);
  } else if (message.kind === "cancel") operations.get(message.id)?.controller.abort();
  else if (message.kind === "request") {
    const controller = new AbortController();
    const task = handle(message, controller.signal)
      .catch(error => send({ kind: "error", id: message.id, error: safeError(error) }))
      .finally(() => operations.delete(message.id));
    operations.set(message.id, { controller, task });
  }
}
await shutdown();
