# pi extensions for Actions

Copies of the maintainer's personal pi extensions (`~/.pi/agent/extensions`), installed
into a temporary agent directory by `harness/pi-setup.sh`. `pi-web-access` is installed
from npm at a pinned version instead of being vendored.

| Extension | Purpose |
|---|---|
| `anthropic-omp/` | Claude subscription provider backed by a pinned oh-my-pi snapshot, run in Bun. See its README |
| `image-generation/` | `imagegen` tool through pi's `openai-codex` login, or `OPENAI_API_KEY` |

`thinking-levels.json` maps each pi model to its default thinking level. `run.sh` passes it
with `--thinking` (and records it in the PR) unless `AGENT_REASONING_EFFORT` is set;
`pi-setup.sh` writes it to the runner's `settings.json` as `modelThinkingLevels`.

Changes from the personal copies, needed on Linux runners:

- `anthropic-omp/runtime/package.json` lists `@oh-my-pi/pi-utils` (the worker imports it
  directly; the personal install linked it by hand) and both native addons as optional
  dependencies (`darwin-arm64`, `linux-x64`), so `bun install --frozen-lockfile` works on
  either platform.
- `anthropic-omp/scripts/link-native.ts` links every addon variant the platform package
  ships (Linux x64 has `-modern` and `-baseline` builds).

On Actions, the extension's own credential store stays empty and its backend authenticates
with `ANTHROPIC_OAUTH_TOKEN` (the `claude setup-token` secret). pi's `auth.json` only holds the
extension's non-secret marker. Update these copies deliberately, then rerun
`harness/tests/test_pi_setup.sh` and a dispatch with `-f agent=pi`.
