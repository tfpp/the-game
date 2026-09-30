import { StringDecoder } from "node:string_decoder";
import type { Readable } from "node:stream";

/**
 * Serialize one JSONL frame. JSON.stringify leaves U+2028/U+2029 raw, and some
 * line readers (notably node:readline) treat them as line breaks, splitting a frame.
 */
export function encodeLine(value: unknown): string {
  return JSON.stringify(value).replace(/\u2028/g, "\\u2028").replace(/\u2029/g, "\\u2029") + "\n";
}

/** Split a byte stream into lines on "\n" only (no Unicode line separators). Returns a detach function. */
export function onLines(input: Readable, handler: (line: string) => void): () => void {
  const decoder = new StringDecoder("utf8");
  let buffer = "";
  const emit = (text: string) => {
    buffer += text;
    let index: number;
    while ((index = buffer.indexOf("\n")) !== -1) {
      let line = buffer.slice(0, index);
      buffer = buffer.slice(index + 1);
      if (line.endsWith("\r")) line = line.slice(0, -1);
      if (line) handler(line);
    }
  };
  const onData = (chunk: Buffer | string) => emit(typeof chunk === "string" ? chunk : decoder.write(chunk));
  const onEnd = () => {
    emit(decoder.end());
    if (buffer) { const line = buffer; buffer = ""; handler(line); }
  };
  input.on("data", onData);
  input.once("end", onEnd);
  return () => { input.off("data", onData); input.off("end", onEnd); };
}
