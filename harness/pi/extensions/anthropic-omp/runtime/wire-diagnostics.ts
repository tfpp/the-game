import * as fs from "node:fs/promises";
import * as path from "node:path";
import type { FetchImpl } from "@oh-my-pi/pi-ai/types";
import { wrapFetchForCch } from "@oh-my-pi/pi-ai/providers/anthropic";
import { applyClaudeToolPrefix } from "@oh-my-pi/pi-ai/providers/anthropic-identity";
import { claudeCodeSystemInstruction, claudeToolPrefix } from "@oh-my-pi/pi-ai/providers/claude-code-fingerprint";
import { isAnthropicOAuthToken } from "@oh-my-pi/pi-catalog/utils";
import { getBundledModels } from "@oh-my-pi/pi-catalog/models";

const modelIds = new Set(getBundledModels("anthropic").map(model => model.id));
function safeHeader(value: string | null): string | null {
  if (value === null) return null;
  return /^[A-Za-z0-9_.-]{1,40}$/.test(value) && !value.startsWith("sk-") ? value : "[custom]";
}
function knownValue(value: string | undefined, allowed: string[]): string | null {
  return value === undefined ? null : allowed.includes(value) ? value : "[custom]";
}

interface Body {
  model?: string;
  system?: { type?: string; text?: string; cache_control?: { type?: string; ttl?: string } }[];
  messages?: unknown[];
  tools?: { name?: string }[];
  metadata?: { user_id?: string };
  max_tokens?: number;
  thinking?: { type?: string; display?: string };
  output_config?: { effort?: string };
  speed?: string;
  service_tier?: string;
}

function bodyText(body: unknown): string | undefined {
  if (typeof body === "string") return body;
  if (body instanceof Uint8Array) return new TextDecoder().decode(body);
  return undefined;
}

/** Inspect only whitelisted protocol fields. Never return credentials or transcript data. */
export async function summarizeWireRequest(
  input: string | URL | Request,
  init: RequestInit | undefined,
  status: number,
  expectedAccountId?: string,
) {
  const url = new URL(input instanceof Request ? input.url : input.toString());
  const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
  const bearer = headers.get("authorization");
  const raw = bodyText(init?.body);
  const body = raw ? JSON.parse(raw) as Body : undefined;
  const billing = body?.system?.[0]?.text;
  let checksumMatches: boolean | null = null;
  if (raw && billing?.startsWith("x-anthropic-billing-header:") && /cch=[0-9a-f]{5};/.test(billing)) {
    // Re-sign through the fork's own implementation. Parse/stringify matches
    // its JSON encoder; never replace a lookalike string in user/tool content.
    const unsigned = JSON.parse(raw) as Body;
    unsigned.system![0].text = billing.replace(/cch=[0-9a-f]{5};/, "cch=00000;");
    let resigned: string | undefined;
    const sign = wrapFetchForCch(async (_input, next) => {
      resigned = bodyText(next?.body);
      return new Response(null, { status: 204 });
    });
    await sign(url, { method: "POST", body: JSON.stringify(unsigned) });
    checksumMatches = resigned === raw;
  }
  let metadata: Record<string, unknown> = {};
  try {
    const parsed: unknown = JSON.parse(body?.metadata?.user_id ?? "");
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) metadata = parsed as Record<string, unknown>;
  } catch { /* Record an invalid shape without retaining the opaque user id. */ }
  const tools = body?.tools ?? [];
  const betas = (headers.get("anthropic-beta") ?? "").split(",").map(value => value.trim()).filter(Boolean)
    .map(value => /^[a-z][a-z0-9-]{0,80}-(?:[0-9]{8}|[0-9]{4}-[0-9]{2}-[0-9]{2})$/.test(value) && !value.startsWith("sk-") ? value : "[custom]");
  const userAgent = headers.get("user-agent");
  const sdkHeaders = Object.fromEntries([
    "x-stainless-lang", "x-stainless-package-version", "x-stainless-os", "x-stainless-arch", "x-stainless-runtime", "x-stainless-runtime-version",
  ].map(name => [name, safeHeader(headers.get(name))]));
  return {
    timestamp: new Date().toISOString(), status,
    endpoint: `${url.origin}${url.pathname}`, betaQuery: url.searchParams.get("beta") === "true",
    auth: { bearer: bearer?.startsWith("Bearer ") === true,
      oauthToken: bearer ? isAnthropicOAuthToken(bearer.slice(7)) : false, hasApiKeyHeader: headers.has("x-api-key") },
    headers: {
      userAgent: userAgent === null ? null : /^claude-cli\/[0-9]+\.[0-9]+\.[0-9]+(?: \(external, cli\))?$/.test(userAgent) ? userAgent : "[custom]",
      app: knownValue(headers.get("x-app") ?? undefined, ["cli"]),
      anthropicVersion: safeHeader(headers.get("anthropic-version")), betas,
      hasClaudeCodeSessionId: headers.has("x-claude-code-session-id"),
      hasLongContextBeta: betas.includes("context-1m-2025-08-07"), ...sdkHeaders,
    },
    body: {
      model: body?.model && modelIds.has(body.model) ? body.model : "[unknown]", utf8Bytes: raw ? Buffer.byteLength(raw) : null,
      messages: body?.messages?.length, tools: tools.length,
      unprefixedCustomTools: tools.filter(tool => typeof tool.name === "string" &&
        !tool.name.startsWith(claudeToolPrefix) && applyClaudeToolPrefix(tool.name) !== tool.name).length,
      maxTokens: typeof body?.max_tokens === "number" ? body.max_tokens : null,
      thinkingType: knownValue(body?.thinking?.type, ["adaptive", "enabled", "disabled"]),
      thinkingDisplay: knownValue(body?.thinking?.display, ["summarized", "omitted"]),
      effort: knownValue(body?.output_config?.effort, ["low", "medium", "high", "xhigh", "max"]),
      speed: knownValue(body?.speed, ["fast", "standard"]), serviceTier: knownValue(body?.service_tier, ["auto", "standard_only"]),
    },
    identity: {
      billingFirst: billing?.startsWith("x-anthropic-billing-header:") === true,
      billingVersion: billing?.match(/cc_version=([0-9]+\.[0-9]+\.[0-9]+\.[0-9a-f]{3});/)?.[1] ?? null,
      billingEntrypointCli: billing?.includes("cc_entrypoint=cli;") === true,
      checksumMatches,
      claudeCodeSystemIdentity: body?.system?.[1]?.text === claudeCodeSystemInstruction,
      sessionIdPresent: typeof metadata.session_id === "string" && metadata.session_id.length > 0,
      accountIdPresent: typeof metadata.account_uuid === "string" && metadata.account_uuid.length > 0,
      matchesSelectedAccount: expectedAccountId ? metadata.account_uuid === expectedAccountId : null,
      deviceHex64: typeof metadata.device_id === "string" && /^[a-f0-9]{64}$/.test(metadata.device_id),
    },
  };
}

/** Runs underneath the fork's CCH rewriter, so it sees final body bytes and headers. */
export function withWireDiagnostics(fetchImpl: FetchImpl, directory: string, accountId: () => string | undefined): FetchImpl {
  return async (input, init) => {
    const response = await fetchImpl(input, init);
    const url = new URL(input instanceof Request ? input.url : input.toString());
    if (!response.ok && url.origin === "https://api.anthropic.com" && url.pathname === "/v1/messages") {
      try {
        const summary = await summarizeWireRequest(input, init, response.status, accountId());
        await fs.mkdir(directory, { recursive: true, mode: 0o700 });
        // Contains no body text, tool arguments, tokens, email, account/session IDs,
        // or response body. Failure to record diagnostics must not alter inference.
        const destination = path.join(directory, "last-wire-error.json");
        const temporary = `${destination}.${crypto.randomUUID()}.tmp`;
        try {
          const file = await fs.open(temporary, "wx", 0o600);
          try { await file.writeFile(JSON.stringify(summary, null, 2) + "\n", "utf8"); }
          finally { await file.close(); }
          await fs.rename(temporary, destination);
        } finally { await fs.rm(temporary, { force: true }); }
      } catch { /* Preserve the original upstream response. */ }
    }
    return response;
  };
}
