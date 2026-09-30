import { afterEach, describe, expect, test, spyOn, vi } from "bun:test";
import * as cowork from "@oh-my-pi/pi-ai/providers/cowork-fetch";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { Backend } from "../runtime/backend";
import { streamSimple } from "@oh-my-pi/pi-ai/stream";
import { getBundledModel } from "@oh-my-pi/pi-catalog/models";
import type { AuthStorageOptions, OAuthCredential } from "@oh-my-pi/pi-ai/auth/types";
import type { Context, FetchImpl, AssistantMessage } from "@oh-my-pi/pi-ai/types";
import { normalizeContext, type Tool } from "@earendil-works/pi-ai";
import { fromOmpMessage, toOmpContext, toOmpOptions } from "../src/adapter";
import documentationContext from "./fixtures/pi-docs-context.md" with { type: "text" };

const ACCESS = "sk-ant-oat01-offline-test-only";
const REFRESH = "sk-ant-ort01-offline-test-only";
const MODEL = "claude-sonnet-4-6";
const SESSION = "b95317a0-4276-4913-bb1e-e6f6f7978eb9";
const ACCOUNT = "296c77e1-7c04-4d37-b2a1-861aa180c144";
const ORG = "90f27224-63cb-4912-9e8a-29002142f6ad";
const USER_ID = JSON.stringify({ session_id: SESSION, account_uuid: ACCOUNT, device_id: "a".repeat(64) });
const dirs: string[] = [];
const engines: Backend[] = [];
const fresh = (): OAuthCredential => ({ type: "oauth", access: ACCESS, refresh: REFRESH,
  expires: Date.now() + 3_600_000, accountId: ACCOUNT, email: "test@example.invalid", orgId: ORG });
const ctx = (): Context => ({ systemPrompt: ["Test system"],
  messages: [{ role: "user", content: "Read the fixture", timestamp: 1 }],
  tools: [{ name: "read", description: "Read a fixture", parameters: {
    type: "object", properties: { path: { type: "string" } }, required: ["path"],
  } }],
});
const options = { reasoning: undefined, disableReasoning: true, sessionId: SESSION, metadata: { user_id: USER_ID } };

function sse(tool = false): Response {
  const events: object[] = [
    { type: "message_start", message: { id: "msg_offline", type: "message", role: "assistant", model: MODEL,
      content: [], stop_reason: null, stop_sequence: null,
      usage: { input_tokens: 11, output_tokens: 0, cache_creation_input_tokens: 7, cache_read_input_tokens: 13 } } },
  ];
  if (tool) events.push(
    { type: "content_block_start", index: 0, content_block: { type: "tool_use", id: "toolu_test", name: "_read", input: {} } },
    { type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: '{"path":"café.txt"}' } },
    { type: "content_block_stop", index: 0 },
  );
  else events.push(
    { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
    { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "Hello 🌍" } },
    { type: "content_block_stop", index: 0 },
  );
  events.push(
    { type: "message_delta", delta: { stop_reason: tool ? "tool_use" : "end_turn", stop_sequence: null }, usage: { output_tokens: 5 } },
    { type: "message_stop" },
  );
  return new Response(events.map(event => `event: ${(event as { type: string }).type}\ndata: ${JSON.stringify(event)}\n\n`).join(""), {
    headers: { "Content-Type": "text/event-stream", "request-id": "req_offline" },
  });
}
interface Captured { url: string; headers: Headers; body: string }
function capture(requests: Captured[], tool = false): FetchImpl {
  return async (input, init) => {
    const request = input instanceof Request ? new Request(input, init) : new Request(input.toString(), init);
    requests.push({ url: request.url, headers: request.headers, body: await request.text() });
    return sse(tool);
  };
}
async function engine(fetchImpl?: FetchImpl, config: AuthStorageOptions = {}): Promise<Backend> {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "pi-omp-test-"));
  dirs.push(dir);
  const backend = await Backend.create(path.join(dir, "auth.db"), { usageProviderResolver: () => undefined, ...config }, fetchImpl);
  engines.push(backend);
  return backend;
}
afterEach(async () => {
  vi.restoreAllMocks();
  for (const backend of engines.splice(0)) backend.close();
  for (const dir of dirs.splice(0)) await fs.rm(dir, { recursive: true, force: true });
});

describe("display-only subscription usage", () => {
  const reportFixture = () => ({
    provider: "anthropic" as const, fetchedAt: 1_750_000_000_000,
    limits: ["anthropic:5h", "anthropic:7d", "anthropic:7d:sonnet", "anthropic:monthly"].map((id, index) => ({
      id, label: ACCESS, scope: { provider: "anthropic" as const, accountId: ACCOUNT },
      amount: { unit: "percent" as const, used: 20 + index },
      ...(index === 0 ? { window: { id: "5h", label: REFRESH, resetsAt: 1_750_001_000_000 } } : {}),
      notes: [REFRESH],
    })),
    raw: fresh(), metadata: { credential: fresh() }, notes: [ACCESS],
    resetCredits: { availableCount: 1, nextCreditId: "private-grant-id" },
  });

  test("uses the session-pinned pool account and returns only sanitized 5h/7d limits", async () => {
    const backend = await engine();
    await backend.auth.credentials.upsert("anthropic", fresh());
    const second = { ...fresh(), accountId: "second-account", email: "second@example.invalid",
      access: `${ACCESS}-second`, refresh: `${REFRESH}-second` };
    await backend.auth.credentials.upsert("anthropic", second);
    const accounts = backend.auth.oauth.accounts("anthropic", SESSION);
    expect(accounts).toHaveLength(2);
    const selected = accounts.find(account => account.accountId === second.accountId)!;
    expect(backend.auth.sessions.pin("anthropic", SESSION, selected.credentialId)).toBe(true);
    const report = spyOn(backend.auth.usage, "report").mockResolvedValue(reportFixture());
    const signal = new AbortController().signal;
    const result = await backend.usage(SESSION, signal);
    expect(report).toHaveBeenCalledTimes(1);
    expect(report).toHaveBeenCalledWith("anthropic", expect.objectContaining(second), { timeoutMs: 10_000, signal });
    expect(result).toEqual({ fetchedAt: 1_750_000_000_000, limits: [
      { id: "anthropic:5h", usedPercent: 20, resetAt: 1_750_001_000_000 },
      { id: "anthropic:7d", usedPercent: 21, resetAt: null },
    ] });
    for (const secret of [ACCESS, REFRESH, second.access, second.refresh, "private-grant-id"]) {
      expect(JSON.stringify(result)).not.toContain(secret);
    }
    expect(backend.auth.oauth.accounts("anthropic", SESSION).find(account => account.active)?.credentialId)
      .toBe(selected.credentialId);
  });

  test("does not select an arbitrary account from an unselected pool", async () => {
    const backend = await engine();
    await backend.auth.credentials.upsert("anthropic", fresh());
    await backend.auth.credentials.upsert("anthropic", { ...fresh(), accountId: "second-account", email: "second@example.invalid" });
    const report = spyOn(backend.auth.usage, "report").mockResolvedValue(reportFixture());
    expect(backend.auth.oauth.accounts("anthropic", SESSION)).toHaveLength(2);
    expect(await backend.usage(SESSION, new AbortController().signal)).toBeNull();
    expect(report).not.toHaveBeenCalled();
    expect(backend.auth.oauth.accounts("anthropic", SESSION).some(account => account.active)).toBe(false);
  });

  test("falls back to the sole account without pinning it", async () => {
    const backend = await engine();
    await backend.auth.credentials.set("anthropic", fresh());
    const report = spyOn(backend.auth.usage, "report").mockResolvedValue(reportFixture());
    const signal = new AbortController().signal;
    expect(backend.auth.oauth.accounts("anthropic", SESSION)[0].active).toBe(false);
    expect(await backend.usage(SESSION, signal)).not.toBeNull();
    expect(report).toHaveBeenCalledWith("anthropic", expect.objectContaining({ access: ACCESS }), { timeoutMs: 10_000, signal });
    expect(backend.auth.oauth.accounts("anthropic", SESSION)[0].active).toBe(false);
  });

  test("returns null for missing accounts or a missing usage report", async () => {
    const backend = await engine();
    const report = spyOn(backend.auth.usage, "report").mockResolvedValue(null);
    const signal = new AbortController().signal;
    expect(await backend.usage(SESSION, signal)).toBeNull();
    expect(report).not.toHaveBeenCalled();
    await backend.auth.credentials.set("anthropic", fresh());
    expect(await backend.usage(SESSION, signal)).toBeNull();
    expect(report).toHaveBeenCalledTimes(1);
  });

  test("rejects pre-cancelled lookups before fetching usage", async () => {
    const backend = await engine();
    await backend.auth.credentials.set("anthropic", fresh());
    const report = spyOn(backend.auth.usage, "report").mockResolvedValue(reportFixture());
    const controller = new AbortController();
    const reason = new Error("cancelled before lookup");
    controller.abort(reason);
    await expect(backend.usage(SESSION, controller.signal)).rejects.toBe(reason);
    expect(report).not.toHaveBeenCalled();
  });

  test("passes cancellation to the report and rejects a result arriving after cancellation", async () => {
    const backend = await engine();
    await backend.auth.credentials.set("anthropic", fresh());
    const controller = new AbortController();
    const reason = new Error("cancelled during report");
    spyOn(backend.auth.usage, "report").mockImplementation(async (_provider, _credential, options) => {
      expect(options?.signal).toBe(controller.signal);
      controller.abort(reason);
      return reportFixture();
    });
    await expect(backend.usage(SESSION, controller.signal)).rejects.toBe(reason);
  });
});

describe("fork-backed subscription behavior", () => {
  test("browser PKCE login persists a scoped grant and returns identity, not tokens", async () => {
    const requests: Captured[] = [];
    const backend = await engine(async (input, init) => {
      const request = input instanceof Request ? new Request(input, init) : new Request(input.toString(), init);
      requests.push({ url: request.url, headers: request.headers, body: await request.text() });
      if (new URL(request.url).pathname !== "/v1/oauth/token") throw new Error("Unexpected network operation");
      return Response.json({ access_token: ACCESS, refresh_token: REFRESH, expires_in: 3600,
        account: { uuid: ACCOUNT, email_address: "test@example.invalid" }, organization: { uuid: ORG, name: "Personal" } });
    });
    const ready = Promise.withResolvers<URL>();
    const before = Date.now();
    const identity = await backend.login({
      onAuth: info => ready.resolve(new URL(info.url)),
      onPrompt: async () => { throw new Error("Unexpected fallback prompt"); },
      onManualCodeInput: async () => `test-code#${(await ready.promise).searchParams.get("state")}`,
    });
    const authUrl = await ready.promise;
    const token = JSON.parse(requests[0].body);
    expect(authUrl.origin + authUrl.pathname).toBe("https://claude.ai/oauth/authorize");
    expect(authUrl.searchParams.get("scope")?.split(" ")).toContain("user:inference");
    expect(token.grant_type).toBe("authorization_code");
    expect(token.redirect_uri).toBe("http://localhost:54545/callback");
    expect(token.code).toBe("test-code");
    const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token.code_verifier));
    expect(Buffer.from(hash).toString("base64url")).toBe(authUrl.searchParams.get("code_challenge")!);
    expect(token.state).toBe(authUrl.searchParams.get("state"));
    expect(identity).toMatchObject({ type: "oauth", accountId: ACCOUNT, orgId: ORG });
    expect(JSON.stringify(identity)).not.toContain(ACCESS);
    expect(JSON.stringify(identity)).not.toContain(REFRESH);
    const stored = backend.auth.credentials.getOAuth("anthropic")!;
    expect(stored.access).toBe(ACCESS);
    expect(stored.expires).toBeGreaterThanOrEqual(before + 3_300_000);
    expect(stored.expires).toBeLessThanOrEqual(Date.now() + 3_300_000);
    expect((await fs.stat(path.join(dirs[0], "auth.db"))).mode & 0o777).toBe(0o600);
    expect((await backend.status())[0]).toMatchObject({ accountId: ACCOUNT, orgId: ORG });
    expect(JSON.stringify(await backend.status())).not.toContain(REFRESH);
  });

  test("adapter and direct fork produce byte-identical OAuth requests, including final billing checksum", async () => {
    const requests: Captured[] = [];
    const fetchImpl = capture(requests, true);
    const backend = await engine(fetchImpl);
    await backend.auth.credentials.set("anthropic", fresh());
    const originalContext = toOmpContext(normalizeContext({
      systemPrompt: "Test system",
      messages: [{ role: "user", content: "Read the fixture", timestamp: 1 }],
      tools: [{ name: "read", description: "Read a fixture", parameters: ctx().tools![0].parameters as unknown as Tool["parameters"] }],
    }));
    const through = await backend.stream({ modelId: MODEL, context: originalContext,
      options: toOmpOptions({ sessionId: SESSION, metadata: { user_id: USER_ID }, timeoutMs: 300_000, maxRetries: 0 }),
    }, new AbortController().signal).result();
    const direct = await streamSimple(getBundledModel("anthropic", MODEL), ctx(), {
      ...options, apiKey: ACCESS, fetch: fetchImpl,
    }).result();
    expect(through.stopReason).toBe("toolUse");
    expect(through.content).toEqual(direct.content);
    expect(requests).toHaveLength(2);
    expect(requests[0].body).toBe(requests[1].body);
    expect(requests[0].url).toBe("https://api.anthropic.com/v1/messages?beta=true");
    expect(requests[0].headers.get("authorization")).toBe(`Bearer ${ACCESS}`);
    expect(requests[0].headers.has("x-api-key")).toBe(false);
    expect(requests[0].headers.get("anthropic-beta")).toBe(requests[1].headers.get("anthropic-beta"));
    expect(requests[0].headers.get("user-agent")).toBe(requests[1].headers.get("user-agent"));
    const payload = JSON.parse(requests[0].body);
    expect(payload.system[0].text).toMatch(/cch=[0-9a-f]{5}/);
    expect(payload.system[0].text).not.toContain("cch=00000");
    expect(payload.tools[0].name).toBe("_read");
    expect(through.content[0]).toMatchObject({ type: "toolCall", name: "read", arguments: { path: "café.txt" } });
    expect(through.usage).toMatchObject({ input: 11, output: 5, cacheRead: 13, cacheWrite: 7 });
  });

  test("diagnostics retain the fork transport when generic fetch would fail", async () => {
    const requests: Captured[] = [];
    spyOn(cowork, "coworkFetch").mockImplementation(capture(requests));
    spyOn(globalThis, "fetch").mockRejectedValue(new Error("Generic fetch loses the fork transport profile"));
    const backend = await engine();
    await backend.auth.credentials.set("anthropic", fresh());
    const result = await backend.stream({ modelId: MODEL, context: ctx(), options }, new AbortController().signal).result();
    expect(result.stopReason).toBe("stop");
    expect(result.content[0]).toMatchObject({ type: "text", text: "Hello 🌍" });
    expect(requests).toHaveLength(1);
    expect(JSON.parse(requests[0].body).system[0].text).not.toContain("cch=00000");
  });

  test("outgoing documentation becomes a usable pointer without changing project content or source context", async () => {
    const requests: Captured[] = [];
    const backend = await engine(capture(requests));
    await backend.auth.credentials.set("anthropic", fresh());
    const context = { ...ctx(), systemPrompt: [documentationContext] };
    const before = structuredClone(context);
    const result = await backend.stream({ modelId: MODEL, context, options }, new AbortController().signal).result();
    expect(result.stopReason).toBe("stop");
    const payload = JSON.parse(requests[0].body) as { system: {text: string}[] };
    const outgoing = payload.system[2].text;
    expect(outgoing).toContain("`/tmp/Pi reference & examples/README.md`");
    expect(outgoing).not.toContain("SDK integrations (docs/sdk.md)");
    expect(outgoing).not.toContain("- Additional docs:");
    const beforeDocs = documentationContext.indexOf("<docs>\nPi documentation");
    const afterDocs = documentationContext.indexOf("</docs>", beforeDocs) + "</docs>".length;
    expect(outgoing.startsWith(documentationContext.slice(0, beforeDocs))).toBe(true);
    expect(outgoing.endsWith(documentationContext.slice(afterDocs))).toBe(true);
    expect(context).toEqual(before);
    expect(payload.system[0].text).not.toContain("cch=00000");
  });

  test("request hooks run before CCH signing and response consumption", async () => {
    const requests: Captured[] = [];
    const backend = await engine(capture(requests));
    await backend.auth.credentials.set("anthropic", fresh());
    const order: string[] = [];
    const result = backend.stream({ modelId: MODEL, context: ctx(), options }, new AbortController().signal, {
      onPayload(payload) { order.push("payload"); return { ...(payload as object), max_tokens: 17 }; },
      onResponse(response) { expect(response.status).toBe(200); order.push("response"); },
    });
    for await (const event of result) if (event.type === "text_delta") order.push("delta");
    expect(order).toEqual(["payload", "response", "delta"]);
    expect(JSON.parse(requests[0].body).max_tokens).toBe(17);
    expect(JSON.parse(requests[0].body).system[0].text).not.toContain("cch=00000");
  });

  test("response rate-limit headers refresh the display usage snapshot", async () => {
    const backend = await engine(capture([]));
    await backend.auth.credentials.set("anthropic", fresh());
    const ingest = spyOn(backend.auth.usage, "ingestHeaders").mockImplementation(() => { throw new Error("ignored"); });
    let forwarded = false;
    const result = await backend.stream({ modelId: MODEL, context: ctx(), options }, new AbortController().signal, {
      onResponse() { forwarded = true; },
    }).result();
    expect(result.stopReason).toBe("stop");
    expect(forwarded).toBe(true);
    expect(ingest).toHaveBeenCalledWith("anthropic", expect.objectContaining({ "request-id": "req_offline" }),
      { sessionId: SESSION, responseStatus: 200 });
  });

  test("concurrent requests refresh an expired rotating grant once and persist it", async () => {
    const requests: Captured[] = [];
    let refreshes = 0;
    const backend = await engine(capture(requests), {
      async refreshOAuthCredential(_provider, _id, credential) {
        refreshes++;
        await Bun.sleep(10);
        return { ...credential, access: "sk-ant-oat01-rotated-test", refresh: "sk-ant-ort01-rotated-test", expires: Date.now() + 3_600_000 };
      },
    });
    await backend.auth.credentials.set("anthropic", { ...fresh(), expires: 1 });
    const results = await Promise.all(["one", "two"].map(sessionId => backend.stream({
      modelId: MODEL, context: ctx(), options: { ...options, sessionId },
    }, new AbortController().signal).result()));
    expect(results.map(result => result.stopReason)).toEqual(["stop", "stop"]);
    expect(refreshes).toBe(1);
    expect(requests.map(request => request.headers.get("authorization"))).toEqual([
      "Bearer sk-ant-oat01-rotated-test", "Bearer sk-ant-oat01-rotated-test",
    ]);
    const reopened = await Backend.create(path.join(dirs[0], "auth.db"), { usageProviderResolver: () => undefined });
    engines.push(reopened);
    expect(reopened.auth.credentials.getOAuth("anthropic")).toMatchObject({ refresh: "sk-ant-ort01-rotated-test", orgId: ORG });
  });

  test("a 401 refreshes the same account through the fork auth-retry policy before replay", async () => {
    let calls = 0;
    let refreshes = 0;
    const backend = await engine(async (_input, init) => {
      calls++;
      if (new Headers(init?.headers).get("authorization") === `Bearer ${ACCESS}`) {
        return Response.json({ type: "error", error: { type: "authentication_error", message: "Invalid bearer token" } }, { status: 401 });
      }
      return sse();
    }, { async refreshOAuthCredential(_provider, _id, credential) {
      refreshes++;
      return { ...credential, access: "sk-ant-oat01-refreshed-test", expires: Date.now() + 3_600_000 };
    } });
    await backend.auth.credentials.set("anthropic", fresh());
    const result = await backend.stream({ modelId: MODEL, context: ctx(), options }, new AbortController().signal).result();
    expect(result.stopReason).toBe("stop");
    expect(refreshes).toBe(1);
    expect(calls).toBe(2);
  });

  test("subscription provider rejects stored API keys instead of silently billing API usage", async () => {
    let requests = 0;
    const backend = await engine(async () => { requests++; return sse(); });
    await backend.auth.credentials.set("anthropic", { type: "api_key", key: "sk-ant-api03-offline-key" });
    await expect(backend.stream({ modelId: MODEL, context: ctx(), options }, new AbortController().signal).result())
      .rejects.toThrow("API-key fallback is disabled");
    expect(requests).toBe(0);
    await backend.forget();
    expect(await backend.status()).toEqual([]);
  });

  test("Pi session serialization retains signed/redacted blocks and fork request-control history", () => {
    const original: AssistantMessage = {
      role: "assistant", provider: "anthropic", api: "anthropic-messages", model: MODEL, timestamp: 2,
      content: [{ type: "thinking", thinking: "reason", thinkingSignature: "signed-block" },
        { type: "redactedThinking", data: "encrypted-block" },
        { type: "toolCall", id: "toolu_test", name: "read", arguments: { path: "café.txt" } }],
      usage: { input: 1, output: 2, cacheRead: 0, cacheWrite: 0, totalTokens: 3,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
      stopReason: "toolUse", credentialId: 7,
      requestControls: { messageIndex: 1, tools: { declared: ["read"], deferred: [], active: ["read"] }, effort: { topLevel: "high", tail: "high" } },
    };
    const persisted = JSON.parse(JSON.stringify(fromOmpMessage(original)));
    const restored = toOmpContext(normalizeContext({ messages: [persisted] })).messages[0];
    expect(restored).toEqual(original);
  });
});
