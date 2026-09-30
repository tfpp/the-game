import { expect, test } from "bun:test";
import { compactPiDocumentation } from "../runtime/system-prompt";
import fixture from "./fixtures/pi-docs-context.md" with { type: "text" };

const start = fixture.indexOf("<docs>\nPi documentation");
const end = fixture.indexOf("</docs>", start) + "</docs>".length;
const generated = fixture.slice(start, end);

test("CRLF documentation guidance becomes a pointer without damaging surrounding instructions", () => {
  const input = fixture.replaceAll("\n", "\r\n");
  const output = compactPiDocumentation(input);
  expect(output).toContain("`/tmp/Pi reference & examples/README.md`");
  expect(output).not.toContain("SDK integrations (docs/sdk.md)");
  expect(output.endsWith(fixture.slice(end).replaceAll("\n", "\r\n"))).toBe(true);
});

for (const [name, input] of [
  ["unknown heading", generated.replace("Pi documentation (", "Application documentation (")],
  ["missing README location", generated.replace("- Main documentation:", "- Unknown documentation:")],
  ["unclosed block", generated.replace("</docs>", "")],
  ["nested block", generated.replace("- Main documentation:", "<docs>\n- Main documentation:")],
  ["project-owned copy", fixture.slice(fixture.indexOf("<project_context>"))],
] as const) {
  test(`does not erase documentation when the block is an ${name}`, () => {
    expect(compactPiDocumentation(input)).toBe(input);
  });
}
