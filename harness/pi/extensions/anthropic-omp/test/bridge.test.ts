import { afterEach, describe, expect, test } from "bun:test";
import { normalizeContext } from "@earendil-works/pi-ai";
import { fileURLToPath } from "node:url";
import type { AssistantMessage, AssistantMessageEvent } from "@oh-my-pi/pi-ai/types";
import { Bridge } from "../src/bridge";
import { encodeEvent, EventDecoder, type EventFrame } from "../src/event-wire";
import { fromOmpEvent, toOmpContext } from "../src/adapter";

const bridges: Bridge[] = [];
function bridge(): Bridge {
  const value = new Bridge(fileURLToPath(new URL("./fixtures/bridge-child.ts", import.meta.url)), {
    ...process.env, PI_OMP_BUN: process.execPath,
  });
  bridges.push(value);
  return value;
}
afterEach(async () => { await Promise.all(bridges.splice(0).map(value => value.close())); });

// Clone through JSON: the real transport cannot preserve object identity or undefined fields.
function wire(event: AssistantMessageEvent): EventFrame {
  return JSON.parse(JSON.stringify(encodeEvent(event))) as EventFrame;
}
function message(content: AssistantMessage["content"] = []): AssistantMessage {
  return {
    role: "assistant", content, api: "anthropic-messages", provider: "anthropic", model: "fixture",
    stopReason: "stop", timestamp: 123,
    usage: { input: 1, output: 2, cacheRead: 0, cacheWrite: 0, totalTokens: 3,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
  };
}

describe("stdio bridge", () => {
  test("Unicode line/paragraph separators do not split protocol frames", async () => {
    const runtime = bridge();
    const value = { text: "new\u2028line\u2029para\u0085nel\rcr\u0001", emoji: "🍜" };
    expect(await runtime.request<typeof value>("echo", value)).toEqual(value);
    expect(await runtime.request<string>("echo", "still alive")).toBe("still alive");
  });

  test("already aborted requests invoke no callbacks and do not prevent a later request", async () => {
    const runtime = bridge();
    const controller = new AbortController();
    controller.abort();
    let calls = 0;
    await expect((async () => runtime.request("callback", {}, {
      signal: controller.signal, callback: async () => { calls++; },
    }))()).rejects.toMatchObject({ name: "AbortError" });
    expect(await runtime.request<string>("echo", "alive")).toBe("alive");
    expect(calls).toBe(0);
  });

  test("abort during a pending callback rejects promptly and aborts its signal", async () => {
    const runtime = bridge();
    const controller = new AbortController();
    const entered = Promise.withResolvers<AbortSignal>();
    const release = Promise.withResolvers<unknown>();
    const pending = runtime.request("callback", {}, {
      signal: controller.signal,
      callback: async (_method, _value, signal) => { entered.resolve(signal); return release.promise; },
    });
    const rejected = pending.catch((error: unknown) => error);
    const signal = await entered.promise;
    controller.abort();
    expect(await rejected).toMatchObject({ name: "AbortError" });
    expect(signal.aborted).toBe(true);
    release.resolve("late reply");
    expect(await runtime.request<string>("echo", "still alive")).toBe("still alive");
  });

  test("child cancellation reaches the callback without cancelling the whole request", async () => {
    const runtime = bridge();
    const result = await runtime.request("cancelCallback", { original: true }, {
      callback: async (_method, _value, signal) => {
        const aborted = Promise.withResolvers<void>();
        if (signal.aborted) aborted.resolve();
        else signal.addEventListener("abort", () => aborted.resolve(), { once: true });
        await aborted.promise;
        return { cancelled: signal.aborted };
      },
    });
    expect(result).toEqual({ cancelled: true });
  });

  test("child exit settles all outstanding requests and aborts outstanding callbacks", async () => {
    const runtime = bridge();
    const entered = Promise.withResolvers<AbortSignal>();
    const release = Promise.withResolvers<unknown>();
    const first = runtime.request("callback", "first", {
      callback: async (_method, _value, signal) => { entered.resolve(signal); return release.promise; },
    });
    const signal = await entered.promise;
    const second = runtime.request("hold", "second");
    const exit = runtime.request("exit", null);
    const results = await Promise.allSettled([first, second, exit]);
    expect(results.map(result => result.status)).toEqual(["rejected", "rejected", "rejected"]);
    for (const result of results) {
      if (result.status === "rejected") expect(String(result.reason)).toContain("runtime exited (23)");
    }
    expect(signal.aborted).toBe(true);
    release.resolve(null);
  });

  test("interleaved requests retain separate events and replacement callback payloads", async () => {
    const runtime = bridge();
    const entered = Promise.withResolvers<void>();
    const release = Promise.withResolvers<unknown>();
    const eventsA: unknown[] = [];
    const eventsB: unknown[] = [];
    const first = runtime.request("callback", { stream: "A" }, {
      event: value => eventsA.push(value),
      callback: async (method, value) => {
        expect(method).toBe("onPayload");
        expect(value).toEqual({ stream: "A" });
        entered.resolve();
        return release.promise;
      },
    });
    await entered.promise;
    const second = await runtime.request("callback", { stream: "B" }, {
      event: value => eventsB.push(value), callback: async () => ({ replacement: "B" }),
    });
    expect(second).toEqual({ replacement: "B" });
    release.resolve({ replacement: "A" });
    expect(await first).toEqual({ replacement: "A" });
    expect(eventsA).toEqual([{ stream: "A" }]);
    expect(eventsB).toEqual([{ stream: "B" }]);
  });

  test("callback exceptions round-trip as request errors without poisoning later calls", async () => {
    const runtime = bridge();
    await expect(runtime.request("callback", null, {
      callback: async () => { throw new Error("payload hook refused"); },
    })).rejects.toThrow("payload hook refused");
    expect(await runtime.request<number>("echo", 42)).toBe(42);
  });
});

describe("incremental event framing and Pi adaptation", () => {
  test("long text deltas have bounded frame sizes and preserve text and signatures", () => {
    const decoder = new EventDecoder();
    const partial = message([{ type: "text", text: "", textSignature: "signed-text" }]);
    decoder.decode(wire({ type: "start", partial }));
    decoder.decode(wire({ type: "text_start", contentIndex: 0, partial }));
    const delta = "hello 😀\n";
    let final: AssistantMessageEvent | undefined;
    const sizes: number[] = [];
    for (let i = 0; i < 2048; i++) {
      partial.content[0] = { type: "text", text: delta.repeat(i + 1), textSignature: "signed-text" };
      const frame = wire({ type: "text_delta", contentIndex: 0, delta, partial });
      sizes.push(Buffer.byteLength(JSON.stringify(frame)));
      final = decoder.decode(frame);
    }
    expect(Math.max(...sizes)).toBeLessThan(1024);
    expect(new Set(sizes).size).toBe(1);
    if (!final || final.type !== "text_delta") throw new Error("Missing text delta");
    const adapted = fromOmpEvent(final);
    if (adapted.type !== "text_delta") throw new Error("Missing adapted delta");
    expect(adapted.partial.content).toEqual([{ type: "text", text: delta.repeat(2048), textSignature: "signed-text" }]);
    expect(adapted.partial.stopReason).toBe("pending");
    expect(adapted.partial.provider).toBe("anthropic-omp");
  });

  test("a lagging consumer does not display future text twice from mutable start events", () => {
    const decoder = new EventDecoder();
    const partial = message([{ type: "text", text: "already produced" }]);
    decoder.decode(wire({ type: "start", partial }));
    const start = decoder.decode(wire({ type: "text_start", contentIndex: 0, partial }));
    if (start.type !== "text_start") throw new Error("Missing start");
    expect(start.partial.content[0]).toEqual({ type: "text", text: "" });
    const delta = decoder.decode(wire({ type: "text_delta", contentIndex: 0, delta: "already produced", partial }));
    if (delta.type !== "text_delta") throw new Error("Missing delta");
    expect(delta.partial.content[0]).toEqual({ type: "text", text: "already produced" });
  });

  test("thinking signatures and parsed tool JSON survive incremental and terminal events", () => {
    const decoder = new EventDecoder();
    const partial = message([{ type: "thinking", thinking: "" }]);
    decoder.decode(wire({ type: "start", partial }));
    decoder.decode(wire({ type: "thinking_start", contentIndex: 0, partial }));
    for (const delta of ["consider ", "工具"]) {
      const block = partial.content[0];
      if (block.type !== "thinking") throw new Error("Missing thinking");
      block.thinking += delta;
      decoder.decode(wire({ type: "thinking_delta", contentIndex: 0, delta, partial }));
    }
    partial.content[0] = { type: "thinking", thinking: "consider 工具", thinkingSignature: "signature-final" };
    decoder.decode(wire({ type: "thinking_end", contentIndex: 0, content: "consider 工具", partial }));
    const toolCall = { type: "toolCall" as const, id: "tool-1", name: "search", arguments: {} };
    partial.content.push(toolCall);
    decoder.decode(wire({ type: "toolcall_start", contentIndex: 1, partial }));
    partial.content[1] = { ...toolCall, arguments: { query: "quoted \"text\"", nested: [1, true] } };
    decoder.decode(wire({ type: "toolcall_delta", contentIndex: 1, delta: '{"query":"quoted \\"text\\"","nested":[1,true]}', partial }));
    const last = fromOmpEvent(decoder.decode(wire({ type: "toolcall_end", contentIndex: 1, toolCall: partial.content[1], partial })));
    if (last.type !== "toolcall_end") throw new Error("Missing tool completion");
    expect(last.toolCall.arguments).toEqual({ query: 'quoted "text"', nested: [1, true] });
    expect(last.partial.content[0]).toEqual(partial.content[0]);
    const done = fromOmpEvent(decoder.decode(wire({ type: "done", reason: "toolUse", message: { ...partial, stopReason: "toolUse" } })));
    if (done.type !== "done") throw new Error("Missing completion");
    expect(toOmpContext(normalizeContext({ messages: [done.message] })).messages[0]).toMatchObject({
      provider: "anthropic", content: partial.content, stopReason: "toolUse",
    });
  });

  test("independent decoders do not mix partials and terminal errors retain partial output", () => {
    const left = new EventDecoder();
    const right = new EventDecoder();
    for (const decoder of [left, right]) {
      decoder.decode(wire({ type: "start", partial: message() }));
      decoder.decode(wire({ type: "text_start", contentIndex: 0, partial: message([{ type: "text", text: "" }]) }));
    }
    for (const [decoder, delta] of [[left, "left"], [right, "right"]] as const) {
      const result = decoder.decode(wire({ type: "text_delta", contentIndex: 0, delta, partial: message([{ type: "text", text: delta }]) }));
      if (result.type !== "text_delta") throw new Error("Missing delta");
      expect(result.partial.content).toEqual([{ type: "text", text: delta }]);
    }
    const error = { ...message([{ type: "text" as const, text: "left" }]), stopReason: "error" as const, errorMessage: "upstream disconnected" };
    const terminal = fromOmpEvent(left.decode(wire({ type: "error", reason: "error", error })));
    expect(terminal).toMatchObject({ type: "error", reason: "error", error: {
      provider: "anthropic-omp", stopReason: "error", errorMessage: "upstream disconnected", content: error.content,
    } });
  });
});
