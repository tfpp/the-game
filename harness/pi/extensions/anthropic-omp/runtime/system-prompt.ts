import { compile } from "@oh-my-pi/pi-utils/prompt";
import heading from "./prompts/pi-docs-heading.md" with { type: "text" };
import pointer from "./prompts/pi-docs-pointer.md" with { type: "text" };

const generatedHeading = heading.trim();
const renderPointer = compile(pointer.trimEnd());

/** Compact Pi's generated docs index, not project instructions or arbitrary <docs> blocks. */
export function compactPiDocumentation(prompt: string): string {
  const projectStart = prompt.search(/^<(?:project_context|project_instructions)(?:[ >])/m);
  let replaced = false;
  return prompt.replace(/^<docs>\r?\n([\s\S]*?)^<\/docs>(?=\r?$)/gm,
    (block: string, content: string, offset: number): string => {
      if (replaced || (projectStart !== -1 && offset >= projectStart)) return block;
      if (content.split(/\r?\n/, 1)[0] !== generatedHeading) return block;
      // A malformed/nested block must not swallow later user instructions.
      if (/^<(?:docs|project_context|project_instructions)(?:[ >])/m.test(content)) return block;
      const readme = /^- Main documentation: ([^\r\n]+)\r?$/m.exec(content)?.[1].trim();
      if (!readme) return block;
      replaced = true;
      return renderPointer({ readme });
    });
}
