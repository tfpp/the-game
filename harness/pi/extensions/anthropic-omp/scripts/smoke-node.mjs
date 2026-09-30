// Intentionally runs under Node: catches jiti/import/runtime-boundary regressions
// that Bun-only tests cannot detect. All state is isolated and routing is blocked.
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { createEventBus, discoverAndLoadExtensions } from "@earendil-works/pi-coding-agent";
import { normalizeContext } from "@earendil-works/pi-ai";

const root = fileURLToPath(new URL("../", import.meta.url));
const dir = await fs.mkdtemp(path.join(os.tmpdir(), "pi-omp-node-"));
process.env.PI_OMP_STATE_DIR = dir;
process.env.ANTHROPIC_BASE_URL = "https://example.invalid";
process.env.CLAUDE_CODE_USE_FOUNDRY = "0";
let loaded;
try {
  const events = createEventBus();
  loaded = await discoverAndLoadExtensions([path.join(root, "index.ts"), path.join(root, "../statusbar.ts")], dir, dir, events);
  assert.deepEqual(loaded.errors, []);
  const provider = loaded.runtime.pendingNativeProviderRegistrations.find(entry => entry.provider.id === "anthropic-omp")?.provider;
  assert.ok(provider, "Provider must be registered through Pi's real extension loader");
  const model = provider.getModels().find(entry => entry.id === "claude-sonnet-4-6");
  assert.ok(model);
  const result = await provider.streamSimple(model, normalizeContext({ messages: [] }), { apiKey: "omp-managed-oauth-v1", timeoutMs: 300_000, maxRetries: 0 }).result();
  assert.equal(result.stopReason, "error");
  assert.match(result.errorMessage, /environment-overridden endpoint/);
  const usage = await new Promise((resolve, reject) => {
    const signal = AbortSignal.timeout(10_000);
    signal.addEventListener("abort", () => reject(new Error("Usage bridge timed out")), { once: true });
    events.emit("anthropic-omp:usage", { sessionId: "offline-smoke", signal, resolve, reject });
  });
  assert.equal(usage, null, "An empty credential store must return no usage, not fake quota");
  console.log("Node → Pi/jiti → extension → Bun/fork → Pi error mapping and usage bridge: passed (offline)");
} finally {
  for (const extension of loaded?.extensions ?? []) {
    for (const handler of extension.handlers.get("session_shutdown") ?? []) await handler({ type: "session_shutdown" }, {});
  }
  await fs.rm(dir, { recursive: true, force: true });
}
