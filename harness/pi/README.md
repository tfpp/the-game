# pi extensions for Actions

Copies of the maintainer's personal pi extensions (`~/.pi/agent/extensions`), installed
into a temporary agent directory by `harness/pi-setup.sh`. `pi-web-access` is installed
from npm at a pinned version instead of being vendored.

| Extension | Purpose |
|---|---|
| `anthropic-omp/` | Claude subscription provider backed by a pinned oh-my-pi snapshot, run in Bun. Installed, with its Bun runtime, only when the run's model is `anthropic-omp/*`. See its README |
| `image-generation/` | `imagegen` tool through pi's `openai-codex` login, or `OPENAI_API_KEY` |

`thinking-levels.json` maps each pi model to its default thinking level. `run.sh` passes it
with `--thinking` (and records it in the PR) unless `AGENT_REASONING_EFFORT` is set;
`pi-setup.sh` writes it to the runner's `settings.json` as `modelThinkingLevels`.

`mcp.json` lists the MCP servers pi gets on the runner, with pinned versions: chrome-devtools
and Playwright (headless, isolated profiles, using the runner's Chrome) and Godot.
`pi-setup.sh` fills in the Godot server's `GODOT_PATH` from `godot` on `PATH` (Actions
installs it at `~/.local/bin/godot` via `setup-toolchain`; `GODOT_PATH` overrides it) and
drops that server when there is no binary. It then runs `pi mcp list` once, which warms the
`npx` cache and logs startup errors without failing the run. pi exposes the tools through
`codemode` as `mcp__<server>__<tool>`. Claude and Codex runs don't get these servers.

Changes from the personal copies, needed on Linux runners:

- `anthropic-omp/runtime/package.json` lists `@oh-my-pi/pi-utils` (the worker imports it
  directly; the personal install linked it by hand) and both native addons as optional
  dependencies (`darwin-arm64`, `linux-x64`), so `bun install --frozen-lockfile` works on
  either platform.
- `anthropic-omp/scripts/link-native.ts` links every addon variant the platform package
  ships (Linux x64 has `-modern` and `-baseline` builds).
- The vendored catalog's Google Gemini CLI and Antigravity logins have empty OAuth client
  credentials (`rules/auth/google-*.kdl` and the compiled `rules.json`), because GitHub push
  protection rejects them. Only the Anthropic provider runs here. `runtime/snapshot.json`
  records the edited files' hashes, so `bun run verify:snapshot` still passes.

On Actions, the extension's own credential store stays empty and its backend authenticates
with `ANTHROPIC_OAUTH_TOKEN` (the `claude setup-token` secret). pi's `auth.json` only holds the
extension's non-secret marker. Update these copies deliberately, then rerun
`harness/tests/test_pi_setup.sh` and a dispatch with `-f agent=pi`
(`-f pi_model=anthropic-omp/claude-opus-5-5` to exercise `anthropic-omp`).
