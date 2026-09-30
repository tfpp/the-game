import {
  getCurrentSystemPrompt, getCurrentTools, getDeclaredTools,
  type AssistantMessage, type AssistantMessageEvent, type Model, type Api,
  type SimpleStreamOptions, type TranscriptContext, type TextContent, type JsonObject, type Tool,
} from "@earendil-works/pi-ai";
import type {
  AssistantMessage as OmpAssistant, AssistantMessageEvent as OmpEvent,
  Context as OmpContext, Message as OmpMessage, Tool as OmpTool,
  SimpleStreamOptions as OmpOptions,
} from "@oh-my-pi/pi-ai/types";

export const PROVIDER = "anthropic-omp";
export const MANAGED_AUTH = "omp-managed-oauth-v1";

type OmpBlock = OmpAssistant["content"][number];
type PiBlock = AssistantMessage["content"][number];
interface OpaqueBlock extends TextContent { ompBlock: OmpBlock }

function fromBlock(block: OmpBlock): PiBlock {
  if (block.type === "redactedThinking") {
    return { type: "thinking", thinking: "", redacted: true, thinkingSignature: block.data };
  }
  if (block.type === "text" || block.type === "thinking") return { ...block };
  if (block.type === "toolCall") return { ...block, arguments: block.arguments as JsonObject };
  // Pi cannot represent server-tool/fallback/image blocks in assistant content.
  // Keep the original block alongside a visible marker so session replay is lossless.
  return { type: "text", text: `[Anthropic ${block.type}]`, ompBlock: block } as OpaqueBlock;
}
function toBlock(block: PiBlock): OmpBlock {
  if (block.type === "thinking" && block.redacted) {
    if (!block.thinkingSignature) throw new Error("Cannot replay redacted thinking without its signature");
    return { type: "redactedThinking", data: block.thinkingSignature };
  }
  if ("ompBlock" in block) {
    const opaque = block as OpaqueBlock;
    if (opaque.text !== `[Anthropic ${opaque.ompBlock.type}]`) throw new Error("Cannot replay a modified opaque Anthropic block");
    return opaque.ompBlock;
  }
  return { ...block };
}

export function fromOmpMessage(message: OmpAssistant, pending = false): AssistantMessage {
  return {
    ...message, provider: PROVIDER, content: message.content.map(fromBlock),
    stopReason: pending ? "pending" : message.stopReason,
    ...(message.upstreamModel ? { responseModel: message.upstreamModel } : {}),
  } as AssistantMessage;
}

export function fromOmpEvent(event: OmpEvent): AssistantMessageEvent {
  if (event.type === "done") return { ...event, message: fromOmpMessage(event.message) };
  if (event.type === "error") return { ...event, error: fromOmpMessage(event.error) };
  const partial = fromOmpMessage(event.partial, true);
  if (event.type === "image_end") throw new Error("Pi cannot represent assistant image events from this backend");
  if (event.type === "toolcall_end") {
    const toolCall = partial.content[event.contentIndex];
    if (toolCall.type !== "toolCall") throw new Error("OMP emitted an invalid tool-call completion");
    return { ...event, toolCall, partial };
  }
  return { ...event, partial };
}

function toOmpTool(tool: Tool): OmpTool {
  return {
    name: tool.name, description: tool.description,
    parameters: tool.parameters as unknown as Record<string, unknown>,
    ...(tool.constrainedSampling === false ? { strict: false } :
      tool.constrainedSampling?.type === "json_schema" ? { strict: true } : {}),
  };
}

export function toOmpContext(context: TranscriptContext): OmpContext {
  const messages: OmpMessage[] = [];
  for (const message of context.messages) {
    if (message.role === "system") continue;
    if (message.role === "assistant") {
      if (message.stopReason === "pending" || message.stopReason === "deferred") {
        throw new Error("Cannot send an unfinished or deferred response to Anthropic OMP");
      }
      messages.push({
        ...message,
        provider: message.provider === PROVIDER ? "anthropic" : message.provider,
        content: message.content.map(toBlock),
        stopReason: message.stopReason,
      });
    } else messages.push({ ...message });
  }
  // OMP's Context carries current prompt/tools separately. Its own request-control
  // records handle tool/effort changes across turns; retain them on assistant rows.
  const tools = getCurrentTools(context.messages);
  const activeNames = new Set(tools.map(tool => tool.name));
  return {
    systemPrompt: [getCurrentSystemPrompt(context.messages)], messages,
    tools: tools.map(toOmpTool),
    inactiveTools: getDeclaredTools(context.messages).filter(tool => !activeNames.has(tool.name)).map(toOmpTool),
  };
}

export function toOmpOptions(options: SimpleStreamOptions = {}): Omit<OmpOptions, "apiKey"> {
  if (options.fetch) throw new Error("Anthropic OMP cannot transfer a custom fetch function across its Bun process boundary");
  if (options.deferred) throw new Error("Anthropic OMP does not support deferred responses");
  // Pi's SDK populates timeoutMs (and may populate maxRetries) for ordinary
  // requests, not just explicit overrides. Accept but do not forward these
  // SDK-specific controls: the fork owns its first-event/idle watchdogs and
  // transport/auth retry policy. Mapping a single SDK timeout onto those
  // separate clocks, or injecting Pi's retry count, would change fork behavior.
  if (options.env && Object.keys(options.env).length) throw new Error("Set Anthropic OMP runtime environment before starting Pi; per-request env overrides are not supported");
  if (options.headers && Object.values(options.headers).some(value => value === null)) {
    throw new Error("OMP does not support null-valued header suppression; omit the header or use a string");
  }
  if (options.transport && options.transport !== "sse" && options.transport !== "auto") {
    throw new Error("Anthropic OMP supports SSE only");
  }
  return {
    temperature: options.temperature, maxTokens: options.maxTokens,
    cacheRetention: options.cacheRetention, sessionId: options.sessionId,
    metadata: options.metadata, headers: options.headers as Record<string, string> | undefined,
    maxRetryDelayMs: options.maxRetryDelayMs,
    reasoning: options.reasoning as OmpOptions["reasoning"],
    disableReasoning: options.reasoning === undefined,
    thinkingBudgets: options.thinkingBudgets,
    toolChoice: options.toolChoice,
  };
}

export function failure(model: Model<Api>, error: unknown, aborted = false): AssistantMessage {
  return {
    role: "assistant", content: [], api: model.api, provider: PROVIDER, model: model.id,
    timestamp: Date.now(), stopReason: aborted ? "aborted" : "error",
    errorMessage: error instanceof Error ? error.message : String(error),
    usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } },
  };
}
