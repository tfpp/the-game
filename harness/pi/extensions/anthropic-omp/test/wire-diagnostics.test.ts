import { expect, test } from "bun:test";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { wrapFetchForCch } from "@oh-my-pi/pi-ai/providers/anthropic";
import { claudeCodeSystemInstruction } from "@oh-my-pi/pi-ai/providers/claude-code-fingerprint";
import { summarizeWireRequest, withWireDiagnostics } from "../runtime/wire-diagnostics";

const account = "cfe32708-4099-463f-abab-8b78a5c44cf6";
const session = "ac9a0c73-1cc5-455a-a484-0ff98a1f5b11";
const token = "sk-ant-oat01-private-fixture-token";
const prompt = "private-conversation-fixture";
const endpoint = "https://api.anthropic.com/v1/messages?beta=true";
function payload() {
  return {
    model: "claude-opus-5-5", messages: [{ role: "user", content: prompt }],
    system: [
      { type: "text", text: "x-anthropic-billing-header: cc_version=2.1.280.d7b; cc_entrypoint=cli; cch=00000;" },
      { type: "text", text: claudeCodeSystemInstruction },
    ],
    tools: [{ name: "_private_tool_name", input_schema: { description: "private-schema-text" } }, { name: "web_search" }],
    metadata: { user_id: JSON.stringify({ account_uuid: account, session_id: session, device_id: "a".repeat(64) }) },
    max_tokens: 64000, thinking: { type: "adaptive", display: "summarized" }, output_config: { effort: "low" },
  };
}
const headers = {
  Authorization: `Bearer ${token}`, "User-Agent": "claude-cli/2.1.280 (external, cli)",
  "anthropic-beta": "claude-code-20250219,oauth-2025-04-20", "x-app": "cli",
  "x-claude-code-session-id": session,
};

test("failed-request diagnostics see signed wire bytes and omit credentials, identities and conversation", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "omp-wire-"));
  try {
    const response = new Response("private-error-response", { status: 400 });
    let outgoing: string | undefined;
    const fetch = withWireDiagnostics(async (_input, init) => {
      outgoing = new TextDecoder().decode(init?.body as Uint8Array);
      return response;
    }, directory, () => account);
    const signAndSend = wrapFetchForCch(fetch);
    const returned = await signAndSend(endpoint, { method: "POST", body: JSON.stringify(payload()), headers });
    expect(await returned.text()).toBe("private-error-response");
    expect(outgoing).not.toContain("cch=00000");
    const contents = await Bun.file(path.join(directory, "last-wire-error.json")).text();
    const report = JSON.parse(contents);
    expect(report.identity).toMatchObject({ checksumMatches: true, billingVersion: "2.1.280.d7b", claudeCodeSystemIdentity: true, matchesSelectedAccount: true });
    expect(report.auth).toEqual({ bearer: true, oauthToken: true, hasApiKeyHeader: false });
    expect(report.body.unprefixedCustomTools).toBe(0);
    for (const secret of [token, account, session, prompt, "private-schema-text", "_private_tool_name", "private-error-response"]) {
      expect(contents).not.toContain(secret);
    }
    expect((await fs.stat(path.join(directory, "last-wire-error.json"))).mode & 0o777).toBe(0o600);
  } finally { await fs.rm(directory, { recursive: true, force: true }); }
});

test("diagnostics distinguish an invalid checksum, missing identity, and mismatched account", async () => {
  const body = payload();
  body.system[1].text = "not the Claude Code identity";
  const report = await summarizeWireRequest(endpoint, { method: "POST", body: JSON.stringify(body), headers }, 400, "different-account");
  expect(report.identity).toMatchObject({ checksumMatches: false, claudeCodeSystemIdentity: false, matchesSelectedAccount: false });
});

test("diagnostic write failure does not hide the original HTTP error", async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "omp-wire-failure-"));
  try {
    const notDirectory = path.join(directory, "file");
    await Bun.write(notDirectory, "fixture");
    const response = new Response("original response", { status: 403 });
    const fetch = withWireDiagnostics(async () => response, notDirectory, () => account);
    const returned = await fetch(endpoint, { method: "POST", body: JSON.stringify(payload()), headers });
    expect(returned.status).toBe(403);
    expect(await returned.text()).toBe("original response");
  } finally { await fs.rm(directory, { recursive: true, force: true }); }
});
