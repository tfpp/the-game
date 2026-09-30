import { expect, test } from "bun:test";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { createModels, InMemoryCredentialStore, normalizeContext, type AssistantMessage, type AuthEvent } from "@earendil-works/pi-ai";
import { createOmpProvider } from "../index";
import { Bridge, type RequestHandlers } from "../src/bridge";
import { MANAGED_AUTH, PROVIDER, toOmpContext } from "../src/adapter";
import { encodeEvent } from "../src/event-wire";
import type { AssistantMessage as OmpAssistant } from "@oh-my-pi/pi-ai/types";

class ControlledBridge extends Bridge {
  readonly calls: string[] = [];
  run: (method: string, value: unknown, handlers: RequestHandlers) => Promise<unknown> = async () => undefined;
  override async request<T>(method: string, value: unknown, handlers: RequestHandlers = {}): Promise<T> {
    this.calls.push(method);
    return await this.run(method, value, handlers) as T;
  }
}
const context = () => normalizeContext({ systemPrompt: "Test", messages: [{ role: "user", content: "hello", timestamp: 1 }] });
const partial = (): OmpAssistant => ({ role: "assistant", provider: "anthropic", api: "anthropic-messages", model: "claude-sonnet-4-6",
  content: [], timestamp: 2, stopReason: "stop", usage: { input: 11, output: 0, cacheRead: 0, cacheWrite: 0,
    totalTokens: 11, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } } });
function emit(handlers: RequestHandlers, event: Parameters<typeof encodeEvent>[0]): void {
  // Exercise the JSON boundary as well as event conversion.
  handlers.event?.(JSON.parse(JSON.stringify(encodeEvent(event))));
}

test("Pi login and SDK timeout/retry options allow authenticated streaming without overriding fork policy", async () => {
  const bridge = new ControlledBridge();
  const provider = createOmpProvider(bridge);
  const store = new InMemoryCredentialStore();
  const models = createModels({ credentials: store });
  models.setProvider(provider);
  let promptAbortSignal: AbortSignal | undefined;
  bridge.run = async (method, value, handlers) => {
    if (method === "login") {
      handlers.event?.({ type: "auth_url", url: "https://claude.ai/oauth/authorize?test=true" });
      await handlers.callback?.("prompt", { type: "manual_code", message: "Code" }, new AbortController().signal);
      return { type: "oauth", accountId: "test-account", orgId: "test-org" };
    }
    expect(method).toBe("stream");
    expect(JSON.stringify(value)).not.toContain(MANAGED_AUTH);
    const request = value as { options: Record<string, unknown> };
    expect(request.options).not.toHaveProperty("timeoutMs");
    expect(request.options).not.toHaveProperty("maxRetries");
    const replacement = await handlers.callback?.("payload", { max_tokens: 10 }, new AbortController().signal);
    expect(replacement).toEqual({ max_tokens: 20 });
    await handlers.callback?.("response", { status: 200, headers: { "request-id": "req_test" } }, new AbortController().signal);
    const message = partial();
    emit(handlers, { type: "start", partial: message });
    message.content.push({ type: "text", text: "" });
    emit(handlers, { type: "text_start", contentIndex: 0, partial: message });
    message.content[0] = { type: "text", text: "hello" };
    emit(handlers, { type: "text_delta", contentIndex: 0, delta: "hello", partial: message });
    emit(handlers, { type: "text_end", contentIndex: 0, content: "hello", partial: message });
    emit(handlers, { type: "done", reason: "stop", message });
  };
  const events: AuthEvent[] = [];
  await models.login(PROVIDER, "oauth", { notify: event => events.push(event), prompt: async prompt => { promptAbortSignal = prompt.signal; return "code"; } });
  const credential = await store.read(PROVIDER);
  expect(credential).toMatchObject({ type: "oauth", access: MANAGED_AUTH, refresh: MANAGED_AUTH });
  expect(promptAbortSignal).toBeInstanceOf(AbortSignal);
  expect(events[0]).toMatchObject({ type: "auth_url" });
  const model = models.getModel(PROVIDER, "claude-sonnet-4-6")!;
  let responseStatus = 0;
  const stream = models.streamSimple(model, { messages: [{ role: "user", content: "hello", timestamp: 1 }] }, {
    // sdk.buildRequestOptions supplies timeoutMs even when the user sets no override.
    timeoutMs: 300_000, maxRetries: 0,
    onPayload: () => ({ max_tokens: 20 }), onResponse: response => { responseStatus = response.status; },
  });
  const live: AssistantMessage[] = [];
  const order: string[] = [];
  for await (const event of stream) { order.push(event.type); if ("partial" in event) live.push(event.partial); }
  const result = await stream.result();
  expect(order).toEqual(["start", "text_start", "text_delta", "text_end", "done"]);
  expect(live.every(message => message === live[0])).toBe(true);
  expect(result.content).toEqual([{ type: "text", text: "hello" }]);
  expect(result.provider).toBe(PROVIDER);
  expect(responseStatus).toBe(200);
});

test("missing login and endpoint overrides fail without passing context to the runtime", async () => {
  const bridge = new ControlledBridge();
  const provider = createOmpProvider(bridge);
  const model = provider.getModels()[0];
  const absent = await provider.streamSimple(model, context()).result();
  expect(absent.stopReason).toBe("error");
  const redirected = await provider.streamSimple({ ...model, baseUrl: "https://example.invalid" }, context(), { apiKey: MANAGED_AUTH }).result();
  expect(redirected.stopReason).toBe("error");
  expect(bridge.calls).toEqual([]);
});

test("runtime failure after partial output emits exactly one error and retains known usage", async () => {
  const bridge = new ControlledBridge();
  const provider = createOmpProvider(bridge);
  bridge.run = async (_method, _value, handlers) => {
    const message = partial();
    emit(handlers, { type: "start", partial: message });
    message.content.push({ type: "text", text: "partial" });
    emit(handlers, { type: "text_start", contentIndex: 0, partial: message });
    emit(handlers, { type: "text_delta", contentIndex: 0, delta: "partial", partial: message });
    throw new Error("worker exited");
  };
  const stream = provider.streamSimple(provider.getModels()[0], context(), { apiKey: MANAGED_AUTH });
  const order: string[] = [];
  for await (const event of stream) order.push(event.type);
  const result = await stream.result();
  expect(order).toEqual(["start", "text_start", "text_delta", "error"]);
  expect(result.errorMessage).toContain("worker exited");
  expect(result.content).toEqual([{ type: "text", text: "partial" }]);
  expect(result.usage.input).toBe(11);
});

test("the real Bun worker refuses environment endpoint redirects before resolving subscription auth", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "pi-omp-route-test-"));
  const bridge = new Bridge(undefined, { ...process.env, PI_OMP_STATE_DIR: dir, ANTHROPIC_BASE_URL: "https://example.invalid", CLAUDE_CODE_USE_FOUNDRY: "0" });
  try {
    const provider = createOmpProvider(bridge);
    const result = await provider.streamSimple(provider.getModels()[0], context(), { apiKey: MANAGED_AUTH }).result();
    expect(result.stopReason).toBe("error");
    expect(result.errorMessage).toContain("environment-overridden endpoint");
  } finally {
    await bridge.close();
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test("system deltas are applied and removed tools remain available to fork history reconstruction", () => {
  const schema = { type: "object", properties: {}, additionalProperties: false };
  const normalized = normalizeContext({ messages: [
    { role: "system", content: "Base", sections: { task: "Old task" }, toolsAdded: [
      { name: "read", description: "Read", parameters: schema },
    ], timestamp: 1 },
    { role: "user", content: "hello", timestamp: 2 },
    { role: "system", content: "", sections: { task: "New task" }, toolsRemoved: [{ name: "read" }], toolsAdded: [
      { name: "write", description: "Write", parameters: schema, constrainedSampling: false },
    ], timestamp: 3 },
  ] });
  const converted = toOmpContext(normalized);
  expect(converted.systemPrompt?.join("\n")).toContain("New task");
  expect(converted.systemPrompt?.join("\n")).not.toContain("Old task");
  expect(converted.messages.map(message => message.role)).toEqual(["user"]);
  expect(converted.tools?.map(tool => ({ name: tool.name, strict: tool.strict }))).toEqual([{ name: "write", strict: false }]);
  expect(converted.inactiveTools?.map(tool => tool.name)).toEqual(["read"]);
});
