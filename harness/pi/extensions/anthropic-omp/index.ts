import {
  createAssistantMessageEventStream, createProvider,
  type AssistantMessage, type AuthEvent, type AuthPrompt, type Model, type Api,
  type SimpleStreamOptions, type TranscriptContext, type Provider, type OAuthCredential,
} from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import models from "./models.json" with { type: "json" };
import { Bridge } from "./src/bridge";
import { EventDecoder, type EventFrame } from "./src/event-wire";
import { PROVIDER, MANAGED_AUTH, failure, fromOmpEvent, toOmpContext, toOmpOptions } from "./src/adapter";

function validateCredential(credential: OAuthCredential): void {
  if (credential.access !== MANAGED_AUTH || credential.refresh !== MANAGED_AUTH) {
    throw new Error("Anthropic OMP requires its own login. Existing Pi/Claude Code tokens are not imported.");
  }
}

export function createOmpProvider(bridge: Bridge): Provider<"anthropic-messages"> {
  const streamSimple = (model: Model<Api>, context: TranscriptContext, options: SimpleStreamOptions = {}) => {
    const stream = createAssistantMessageEventStream();
    void (async () => {
      let terminal = false;
      let live: AssistantMessage | undefined;
      try {
        if (options.apiKey !== MANAGED_AUTH) throw new Error("Run /login and select Anthropic subscription (OMP) first.");
        const known = models.find(entry => entry.id === model.id);
        if (!known || model.baseUrl !== known.baseUrl) throw new Error("Anthropic OMP accepts only its pinned Anthropic models and endpoints.");
        const decoder = new EventDecoder();
        await bridge.request("stream", {
          modelId: model.id, context: toOmpContext(context), options: toOmpOptions(options),
        }, {
          signal: options.signal,
          event(value) {
            if (terminal) throw new Error("OMP emitted an event after its terminal response");
            const event = fromOmpEvent(decoder.decode(value as EventFrame));
            if (event.type === "done" || event.type === "error") terminal = true;
            else {
              if (live) Object.assign(live, event.partial); else live = event.partial;
              event.partial = live;
            }
            stream.push(event);
          },
          async callback(method, value) {
            if (method === "payload") return options.onPayload?.(value, model);
            if (method === "response") {
              await options.onResponse?.(value as { status: number; headers: Record<string, string> }, model);
              return;
            }
            throw new Error(`Unexpected inference callback: ${method}`);
          },
        });
        if (!terminal) throw new Error("OMP stream ended without a terminal event");
      } catch (error) {
        if (!terminal) {
          const aborted = options.signal?.aborted === true;
          const message = failure(model, error, aborted);
          if (live) {
            const { stopReason, errorMessage } = message;
            Object.assign(message, live, { stopReason, errorMessage });
          }
          stream.push({ type: "error", reason: aborted ? "aborted" : "error", error: message });
        }
      } finally { stream.end(); }
    })();
    return stream;
  };

  return createProvider<"anthropic-messages">({
    id: PROVIDER, name: "Anthropic subscription (OMP)", baseUrl: "https://api.anthropic.com",
    models: models as Model<"anthropic-messages">[],
    auth: {
      oauth: {
        name: "Anthropic subscription (OMP)", isSubscription: true,
        async login(interaction) {
          const identity = await bridge.request<Record<string, unknown>>("login", null, {
            signal: interaction.signal,
            event: event => interaction.notify(event as AuthEvent),
            async callback(method, value, signal) {
              if (method !== "prompt") throw new Error("Unexpected login callback");
              return interaction.prompt({ ...(value as AuthPrompt), signal });
            },
          });
          // Only a non-secret marker enters Pi's auth.json. The unchanged fork
          // manages real tokens and rotating refresh grants in its private SQLite DB.
          return { type: "oauth", access: MANAGED_AUTH, refresh: MANAGED_AUTH,
            expires: Number.MAX_SAFE_INTEGER, ompIdentity: identity };
        },
        async refresh(credential, signal) {
          validateCredential(credential);
          const accounts = await bridge.request<unknown[]>("status", null, { signal });
          if (!accounts.length) throw new Error("Anthropic OMP credentials were removed; log in again.");
          return { ...credential, expires: Number.MAX_SAFE_INTEGER };
        },
        async toAuth(credential) { validateCredential(credential); return { apiKey: MANAGED_AUTH }; },
      },
    },
    api: {
      streamSimple,
      stream(model, context, options = {}) {
        // Pi's agent uses streamSimple. Reject native-only controls rather than
        // silently translating them into different fork reasoning behavior.
        const native = options as Record<string, unknown>;
        if (["thinkingEnabled", "thinkingBudgetTokens", "thinkingDisplay", "effort", "interleavedThinking", "client"].some(key => native[key] !== undefined)) {
          const result = createAssistantMessageEventStream();
          result.push({ type: "error", reason: "error", error: failure(model, new Error("Use streamSimple with reasoning for Anthropic OMP; Pi-native Anthropic controls are unsupported.")) });
          result.end();
          return result;
        }
        return streamSimple(model, context, options);
      },
    },
  });
}

export default function anthropicOmp(pi: ExtensionAPI): void {
  const bridge = new Bridge();
  pi.registerProvider(createOmpProvider(bridge));
  const unsubscribeUsage = pi.events.on("anthropic-omp:usage", data => {
    const request = data as { sessionId: string; signal: AbortSignal; resolve: (value: unknown) => void; reject: (error: unknown) => void };
    if (!request || typeof request.sessionId !== "string" || typeof request.resolve !== "function"
      || typeof request.reject !== "function" || !request.signal) return;
    void bridge.request("usage", { sessionId: request.sessionId }, { signal: request.signal })
      .then(request.resolve, request.reject);
  });
  pi.on("session_shutdown", () => { unsubscribeUsage(); return bridge.close(); });
  pi.registerCommand("omp-anthropic-status", {
    description: "Check the isolated OMP Anthropic runtime and stored account count",
    handler: async (_args, ctx) => {
      const health = await bridge.request<{ revision: string; runtime: string }>("health", null);
      const accounts = await bridge.request<unknown[]>("status", null);
      ctx.ui.notify(`OMP ${health.revision.slice(0, 12)} · Bun ${health.runtime} · ${accounts.length} subscription account(s)`, "info");
    },
  });
  pi.registerCommand("omp-anthropic-forget", {
    description: "Delete the extension's stored Anthropic subscription grants",
    handler: async (_args, ctx) => {
      if (!ctx.hasUI) throw new Error("Removing grants requires interactive confirmation");
      if (!await ctx.ui.confirm("Remove Anthropic OMP credentials?", "Delete all subscription grants stored by this extension? This does not affect Pi's built-in Anthropic provider.")) return;
      await bridge.request("forget", null);
      ctx.ui.notify("OMP grants removed. Use /logout to remove the Anthropic subscription (OMP) marker from Pi too.", "info");
    },
  });
}
