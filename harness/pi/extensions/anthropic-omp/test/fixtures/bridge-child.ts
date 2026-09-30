import { createInterface } from "node:readline";

interface Request { kind: string; id: string; method?: string; value?: unknown; callId?: string; error?: string }
const active = new Map<string, Request>();
const send = (message: object) => process.stdout.write(`${JSON.stringify(message)}\n`);
createInterface({ input: process.stdin }).on("line", line => {
  const message = JSON.parse(line) as Request;
  if (message.kind === "cancel") {
    active.delete(message.id);
    return;
  }
  if (message.kind === "reply") {
    if (!active.delete(message.id)) return;
    send(message.error === undefined
      ? { kind: "result", id: message.id, value: message.value }
      : { kind: "error", id: message.id, error: message.error });
    return;
  }
  if (message.kind !== "request") return;
  if (message.method === "exit") process.exit(23);
  if (message.method === "echo") {
    send({ kind: "result", id: message.id, value: message.value });
    return;
  }
  active.set(message.id, message);
  send({ kind: "event", id: message.id, value: message.value });
  if (message.method === "hold") return;
  send({ kind: "callback", id: message.id, callId: `call-${message.id}`, method: "onPayload", value: message.value });
  if (message.method === "cancelCallback") {
    send({ kind: "cancelCallback", id: message.id, callId: `call-${message.id}` });
  }
});
