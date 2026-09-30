import * as fs from "node:fs/promises";
import * as path from "node:path";
import { AuthStorage } from "@oh-my-pi/pi-ai/auth-storage";
import type { UsageService } from "./vendor/ai/src/auth/usage";
import type { AuthStorageOptions, OAuthLoginController } from "@oh-my-pi/pi-ai/auth/types";
import type { ApiKeyResolver } from "@oh-my-pi/pi-ai/auth-retry";
import { resolvedApiKeyBearer } from "@oh-my-pi/pi-ai/auth-retry";
import { streamSimple } from "@oh-my-pi/pi-ai/stream";
import type { Context, SimpleStreamOptions, ProviderSessionState, FetchImpl } from "@oh-my-pi/pi-ai/types";
import { getBundledModel } from "@oh-my-pi/pi-catalog/models";
import { isAnthropicOAuthToken } from "@oh-my-pi/pi-catalog/utils";
import { isOfficialAnthropicApiUrl } from "@oh-my-pi/pi-catalog/compat/anthropic";
import { resolveDirectAnthropicBaseUrl } from "@oh-my-pi/pi-ai/providers/anthropic-state";
import { coworkFetch } from "@oh-my-pi/pi-ai/providers/cowork-fetch";
import { buildSessionMetadata } from "./vendor/coding-agent/src/session/session-metadata";
import { withWireDiagnostics } from "./wire-diagnostics";
import { compactPiDocumentation } from "./system-prompt";
import { claudeUsageProvider } from "./vendor/ai/src/usage/claude";
import { defaultUsageProvider } from "./vendor/ai/src/usage/registry";
import { UsagePollCoordinator } from "./usage-poll";

export interface StreamRequest {
  modelId: string;
  context: Context;
  options: Omit<SimpleStreamOptions, "apiKey" | "signal" | "fetch" | "providerSessionState">;
}

/** The fork owns login, SQLite storage, refresh leases, selection, auth retries and wire conversion. */
export class Backend {
  // The pinned AuthStorage constructs UsageService, whose per-account report()
  // is not exposed by its narrower public UsageApi interface.
  readonly auth: AuthStorage & { readonly usage: UsageService };
  #sessions = new Map<string, Map<string, ProviderSessionState>>();
  #fetch?: FetchImpl;
  #defaultSessionId = crypto.randomUUID();
  #diagnosticDirectory?: string;
  #poll?: UsagePollCoordinator;

  constructor(auth: AuthStorage, fetchImpl?: FetchImpl, diagnosticDirectory?: string, poll?: UsagePollCoordinator) {
    this.auth = auth as Backend["auth"]; this.#fetch = fetchImpl; this.#diagnosticDirectory = diagnosticDirectory;
    this.#poll = poll;
  }

  static async create(dbPath: string, options?: AuthStorageOptions, fetchImpl?: FetchImpl): Promise<Backend> {
    await fs.mkdir(path.dirname(dbPath), { recursive: true, mode: 0o700 });
    await fs.chmod(path.dirname(dbPath), 0o700);
    let poll: UsagePollCoordinator | undefined;
    const config: AuthStorageOptions = { ...options };
    if (!config.usageProviderResolver) {
      // Coordinate /usage polling across every session's worker (see usage-poll.ts).
      const pollPath = path.join(path.dirname(dbPath), "usage-poll.db");
      poll = new UsagePollCoordinator(pollPath);
      await fs.chmod(pollPath, 0o600);
      const claude = poll.wrap(claudeUsageProvider);
      config.usageProviderResolver = provider => provider === "anthropic" ? claude : defaultUsageProvider(provider);
    }
    const auth = await AuthStorage.create(dbPath, config);
    await fs.chmod(dbPath, 0o600);
    await auth.credentials.reload();
    return new Backend(auth, fetchImpl, path.dirname(dbPath), poll);
  }

  async login(controller: OAuthLoginController) {
    return this.auth.oauth.login("anthropic", { ...controller, ...(this.#fetch ? { fetch: this.#fetch } : {}) });
  }

  async status() {
    await this.auth.credentials.reload();
    // Return only identity/status data, never the stored grant or token bytes.
    return this.auth.oauth.accounts("anthropic").map(account => ({
      accountId: account.accountId, email: account.email, orgId: account.orgId, orgName: account.orgName,
    }));
  }

  async forget(): Promise<void> { await this.auth.credentials.remove("anthropic"); }

  /** Display-only lookup: never select/rotate accounts or return credential bytes. */
  async usage(sessionId: string, signal: AbortSignal) {
    await this.auth.credentials.reload();
    signal.throwIfAborted();
    const accounts = this.auth.oauth.accounts("anthropic", sessionId);
    const account = accounts.find(account => account.active) ?? (accounts.length === 1 ? accounts[0] : undefined);
    if (!account) return null;
    const stored = this.auth.credentials.list("anthropic").find(entry => entry.id === account.credentialId);
    if (!stored || stored.disabledCause || stored.credential.type !== "oauth") return null;
    const report = await this.auth.usage.report("anthropic", stored.credential, { timeoutMs: 10_000, signal });
    signal.throwIfAborted();
    if (!report) return null;
    return {
      fetchedAt: report.fetchedAt,
      limits: report.limits.filter(limit => limit.id === "anthropic:5h" || limit.id === "anthropic:7d")
        .map(limit => ({ id: limit.id, usedPercent: limit.amount?.used,
          resetAt: limit.window?.resetsAt ?? null })),
    };
  }

  stream(request: StreamRequest, signal: AbortSignal, callbacks: Pick<SimpleStreamOptions, "onPayload" | "onResponse"> = {}) {
    const model = getBundledModel<"anthropic-messages">("anthropic", request.modelId);
    if (!model || model.api !== "anthropic-messages") throw new Error(`Unknown OMP Anthropic model: ${request.modelId}`);
    if (!isOfficialAnthropicApiUrl(resolveDirectAnthropicBaseUrl(model))) {
      throw new Error("Anthropic OMP refuses to send subscription credentials to an environment-overridden endpoint");
    }
    const sessionId = request.options.sessionId ?? this.#defaultSessionId;
    let state = this.#sessions.get(sessionId);
    if (!state) { state = new Map(); this.#sessions.set(sessionId, state); }
    const metadata: Record<string, unknown> = { ...request.options.metadata };
    const resolve = this.auth.keys.resolver("anthropic", { sessionId, modelId: model.id, baseUrl: model.baseUrl });
    const apiKey: ApiKeyResolver = async context => {
      const resolved = await resolve(context);
      const token = resolvedApiKeyBearer(resolved);
      // A subscription-only provider must never fall back to an ambient paid API key.
      if (token && !isAnthropicOAuthToken(token)) throw new Error("Anthropic OMP requires a subscription login; API-key fallback is disabled");
      if (!token && context.error === undefined) throw new Error("No Anthropic OMP subscription credential. Run /login and select Anthropic subscription (OMP).");
      if (request.options.metadata?.user_id === undefined) {
        Object.assign(metadata, buildSessionMetadata(sessionId, "anthropic", this.auth));
      }
      return resolved;
    };
    const transport = this.#diagnosticDirectory
      ? withWireDiagnostics(this.#fetch ?? coworkFetch, this.#diagnosticDirectory,
          () => this.auth.oauth.identity("anthropic", sessionId)?.accountId)
      : this.#fetch;
    const context: Context = {
      ...request.context,
      systemPrompt: request.context.systemPrompt?.map(compactPiDocumentation),
    };
    const onResponse: SimpleStreamOptions["onResponse"] = async (response, responseModel, responseSignal) => {
      // Keep the display usage snapshot current from normal traffic so the
      // throttled /usage endpoint is only a fallback. Omit baseUrl to share the
      // cache key used by usage(); ingestion is throttled and never throws here.
      try {
        this.auth.usage.ingestHeaders("anthropic", response.headers, { sessionId, responseStatus: response.status });
      } catch {}
      await callbacks.onResponse?.(response, responseModel, responseSignal);
    };
    return streamSimple(model, context, {
      ...request.options, ...callbacks, onResponse, apiKey, signal, sessionId, metadata,
      providerSessionState: state, ...(transport ? { fetch: transport } : {}),
    });
  }

  close(): void {
    for (const states of this.#sessions.values()) for (const state of states.values()) state.close();
    this.#sessions.clear();
    this.auth.close();
    this.#poll?.close();
  }
}
