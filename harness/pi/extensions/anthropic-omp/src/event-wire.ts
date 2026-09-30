import type { AssistantMessage as OmpAssistant, AssistantMessageEvent as OmpEvent } from "@oh-my-pi/pi-ai/types";

type OmpBlock = OmpAssistant["content"][number];
export interface EventFrame {
  event: Omit<OmpEvent, "partial">;
  head?: Omit<OmpAssistant, "content">;
  block?: OmpBlock;
  textDelta?: "text" | "thinking";
}

/** Do not resend an ever-growing response for every text/thinking token over IPC. */
export function encodeEvent(event: OmpEvent): EventFrame {
  if (event.type === "done" || event.type === "error") return { event };
  const { partial, ...rest } = event;
  const { content, ...head } = partial;
  // Fork events share a mutable response object. When a consumer lags behind
  // the producer, a start block may already contain future deltas: never send
  // that accumulated text at start and append those deltas a second time.
  if (event.type === "text_start" || event.type === "text_end") {
    const block = content[event.contentIndex];
    if (block.type === "text") return { event: rest, head, block: { ...block, text: event.type === "text_start" ? "" : event.content } };
  }
  if (event.type === "thinking_start" || event.type === "thinking_end") {
    const block = content[event.contentIndex];
    if (block.type === "thinking") return { event: rest, head, block: { ...block, thinking: event.type === "thinking_start" ? "" : event.content } };
  }
  if (event.type === "text_delta" || event.type === "thinking_delta") {
    const block = content[event.contentIndex];
    if (block.type === "text") return { event: rest, head, block: { ...block, text: "" }, textDelta: "text" };
    if (block.type === "thinking") return { event: rest, head, block: { ...block, thinking: "" }, textDelta: "thinking" };
  }
  return { event: rest, head, ...(event.contentIndex !== undefined ? { block: content[event.contentIndex] } : {}) };
}

/** Each decoder belongs to one request, never shared between concurrent streams. */
export class EventDecoder {
  #partial?: OmpAssistant;
  decode(frame: EventFrame): OmpEvent {
    const event = frame.event as OmpEvent;
    if (event.type === "done" || event.type === "error") return event;
    if (!frame.head) throw new Error("Missing runtime event header");
    if (event.type === "start") this.#partial = { ...frame.head, content: [] };
    if (!this.#partial) throw new Error("Runtime emitted content before start");
    Object.assign(this.#partial, frame.head);
    if (event.contentIndex !== undefined && frame.block) {
      const previous = this.#partial.content[event.contentIndex];
      let block = frame.block;
      if (frame.textDelta === "text" && event.type === "text_delta" && block.type === "text") {
        if (previous?.type !== "text") throw new Error("Text delta without text block");
        block = { ...block, text: previous.text + event.delta };
      } else if (frame.textDelta === "thinking" && event.type === "thinking_delta" && block.type === "thinking") {
        if (previous?.type !== "thinking") throw new Error("Thinking delta without thinking block");
        block = { ...block, thinking: previous.thinking + event.delta };
      }
      this.#partial.content[event.contentIndex] = block;
    }
    return { ...event, partial: this.#partial };
  }
}
