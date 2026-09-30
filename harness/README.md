# harness

Runs a coding agent against this repo and turns its work into a PR. `verify.sh` is the
definition of done for agents and humans alike.

| File | What |
|---|---|
| `verify.sh` | Harness tests, then `game/scripts/check.sh`, then Go checks |
| `run.sh` | Sets up the branch, runs the agent, re-runs `verify.sh` and sends failures back (up to `--attempts`), commits, and bundles the new commits. Never pushes |
| `adapters/<agent>.sh` | One per CLI (`claude`, `codex`, `pi`): `PROMPT_FILE LOG_FILE CONTINUE`. Each writes its call's token usage to `usage.json` |
| `prompts/` | `rules.md` (every run), one file per mode, `fix.md` (retries) |
| `gate.sh` | Turns a GitHub event into run inputs, or refuses it |
| `context.sh` | Writes the task, current PR, sibling PRs and paths, recent merges, and feedback from GitHub |
| `check-summary.sh` | Requires integration review notes before agent-written work can be bundled |
| `publish.sh` | Pushes the bundle, opens the PR or comments, reports failures |
| `pi-setup.sh` | Builds a temporary pi agent directory (auth, extensions, `pi-web-access`) on Actions |
| `pi/extensions/` | Vendored pi extensions: `anthropic-omp` (Claude subscription provider) and `image-generation` |
| `claude-app-token.sh` | Fallback push token from the Claude GitHub App |
| `tests/` | Offline tests with a fake agent, `gh` and remote |

## Triggers (`.github/workflows/agent.yml`)

Only people with write access (or bots in `AGENT_TRUSTED_BOTS`) can start a run.

| Action | Mode |
|---|---|
| Add the `agent` label to an issue | `implement`: new branch `agent/<issue>-<slug>`, opens a PR |
| Comment `/agent [notes]` on an issue | `implement`, with the notes as extra instructions |
| Add the `agent` label to an agent PR | `revise`, using all review feedback |
| Comment `/agent <feedback>` on an agent PR | `revise`, with the comment as the newest instructions |
| Comment `/agent resolve-conflicts` on an agent PR | Merge `main` in, and resolve conflicts if there are any |
| Run the workflow by hand (`workflow_dispatch`) | Any mode, by issue or PR number (the bot will use this) |

The label is removed when the run ends, so adding it again starts another run.
**pi is the default harness**: labels, `/agent` comments, dispatches without `agent`, and
`/feature` without `harness` all use it. To use Claude or Codex, select `claude` or `codex`
in the workflow's `agent` input (or dispatch with `-f agent=claude` / `-f agent=codex`);
all three modes are supported.
Discord's `/feature request:<text> [harness:<pi|claude|codex>] [model:<pi model>]
[reasoning:<level>]` saves the harness (pi when omitted), pi's optional model and the
optional reasoning level for that feature's later revisions and conflict resolution; the
bot sends `pi_model` and `reasoning` only when chosen. The workflow's `reasoning` input
(`low` to `max`) overrides `AGENT_REASONING_EFFORT` and each agent's default. `BOT_AGENT`
is only a fallback for legacy features with no saved selection.

## Keeping PRs aligned

Every GitHub run receives an integration snapshot before the agent starts:

- Other open PRs targeting the same base, including human-authored PRs: title, URL,
  branch, head SHA, draft status, description and changed paths (including renames).
  Details cover the 20 most recently updated PRs; the rest remain listed by title and
  link. Descriptions stop at 4,000 characters and file lists at 200 paths, with explicit
  truncation notices. API pages are collected before these limits are applied.
- Up to 10 recent merges from the 100 most recently updated closed PRs on that base.
- For revisions, the current PR description as well as its issue and review feedback.

Context API failures stop the run instead of presenting an incomplete snapshot as an
empty backlog. The prompts ask the agent to inspect existing systems and callers, reuse
shared interfaces, check sibling PR overlap, and document integration and validation in
the summary. An open PR is reference material, not an available dependency: agents must
not merge sibling branches or recreate their systems to unblock a dependent request.

Before coding, agents must inspect the relevant implementation, interfaces, callers and
tests and record their decision in the summary. **Extend a suitable existing system;
create a new one when nothing fits.** New gameplay can own its distinct behavior while
using shared services where applicable. Separate feature directories are not a reason
to duplicate shared state, persistence or networking authority, and reuse is not a reason
to force unrelated systems together.

After code verification passes, the runner requires three nonempty subsections under
`## Integration`: `### Systems inspected`, `### Reuse decision`, and
`### Compatibility checks`. Missing notes trigger the normal retry loop and prevent a
success bundle when attempts run out. A declined request and an automatic clean base
merge do not need an agent design review. This is a structural reporting check: it cannot
prove that the agent searched thoroughly or that its design is correct. Reviewers still
need to assess the concrete paths, rationale and compatibility tests in those notes.

`revise` and `resolve-conflicts` both merge the checked-out base snapshot before doing
their work. Clean and conflicting merges stay uncommitted until verification passes.
A revision still runs the agent to address feedback after a clean merge. A clean
`resolve-conflicts` run can skip the agent if verification passes. The exact base SHA is
recorded in `result.json` and the published summary; if the publisher sees a newer base,
it says that another update and CI run are needed before merging.

These are snapshots, not a lock on other work. The caller must fetch the base and target
branch before `run.sh` (Actions checks out full history). The existing merge coordinator
still serializes merges and updates stale branches. Context helps avoid semantic overlap;
it cannot prove that independently developed features work together without tests.

The context-before-execution approach is also supported by
[Pi's extension lifecycle](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md).
Here it lives in the shared shell harness, so all three adapters receive the same context
and verification behavior without requiring a Pi extension.

Runs are named `agent #<number> <mode> [<request_id>]`, so the Discord bot can match
`workflow_run` events to the dispatch that caused them. Issues the bot opens end with a
`Requested-by: <name> <discord:<id>>` trailer. `context.sh` and `publish.sh` credit that
person instead of the bot, and only when the issue's author is a bot account.

## How a run is isolated

- **gate** (GITHUB_TOKEN) checks the sender and the target, then comments "started".
- **agent** has the model credential but no write token (`persist-credentials: false`,
  read-only GITHUB_TOKEN). It uploads `result.json`, `summary.md`, logs, and a git bundle.
- **publish** runs the default branch's `publish.sh` on a fresh checkout. It treats the
  artifact as data, takes the branch name from the gate, and pushes without force, so a
  revise can only add commits. The token has no Workflows permission, so pushes that edit
  `.github/workflows/` are refused and reported. Changes under `CODEOWNERS` paths are
  flagged in the PR.

## Token usage

`run.sh` sums the adapters' per-call `usage.json` over all attempts into `result.json`
(`usage`: input, output, cache read and cache write tokens, and `cost_usd`). It also
collects `models` and `cost_basis` across attempts. Claude reports observed model IDs
(including subagents); otherwise the explicitly configured model is recorded.

`publish.sh` adds an **Agent Usage** section to generated PRs and puts model, token
usage and estimated cost on the **first line of both Opened and Pushed comments**, so
Discord keeps the metadata even when a long summary is truncated. The bot renders PR
URLs as `[PR #123](<https://github.com/tfpp/the-game/pull/123>)`. Each report covers
**that run, including retries**, not lifetime PR totals. Missing telemetry or unknown
pricing is shown as unavailable, never silently replaced with zero. An automatic clean
merge that does not invoke an agent reports no model, zero tokens and zero cost.

Costs are **API-equivalent estimates, not subscription charges**. Claude and pi supply
API-price estimates. Codex estimates use standard short-context rates per million tokens
([OpenAI pricing](https://developers.openai.com/api/docs/pricing), checked 2026-09-30):
`gpt-6.1-sol` (the default) $2 uncached input, $0.10 cached input, $2.50 cache writes and
$10 output; `gpt-6-astra` $10, $1, $12.50 and $50. They exclude separate tool fees,
fast-mode pricing and long-context premiums.
Turn-level telemetry aggregates multiple requests, so the adapter cannot determine
which requests crossed the 272K-input long-context threshold. Unsupported model
overrides report unavailable cost rather than borrowing another model's rates.

These fields come from the untrusted agent job and are informational: the publisher
bounds numeric values and validates model IDs before rendering them. The human PR
[template](../.github/pull_request_template.md) includes the same usage fields.

## Setup

1. **Label:** `gh label create agent --color 5319e7 --description "Run the coding agent"`.
2. **Model credential:** configure the agents you want to use:
   - **Claude:** run `claude setup-token` locally, then
     `gh secret set CLAUDE_CODE_OAUTH_TOKEN`.
   - **Codex (ChatGPT subscription):** run `codex login` locally. If your login is
     stored in the OS keyring, use `codex -c cli_auth_credentials_store='"file"' login`
     to create `~/.codex/auth.json`, then upload it without printing its contents:
     ```bash
     gh secret set CODEX_AUTH_JSON < "${CODEX_HOME:-$HOME/.codex}/auth.json"
     ```
     Both agents run on GitHub-hosted runners. Codex restores the secret into a private
     temporary `CODEX_HOME` outside the checkout and artifacts, forces file-backed
     ChatGPT authentication, and deletes that directory after execution. No OpenAI API
     key is needed. The secret is a reusable login credential: protect it like a password.
     Refreshed tokens are **not** written back to GitHub Secrets; if login expires or
     refresh fails, log in locally again and replace `CODEX_AUTH_JSON`. Concurrent runs
     sharing one login may also require reauthentication. Discord `/usage` needs a
     separate mount of that account's `auth.json` on the bot via `BOT_CODEX_AUTH_FILE`;
     GitHub Secrets are not available to the bot. See [bot setup](../bot/README.md).
   - **pi:** reuses both logins above and adds OpenRouter. `CODEX_AUTH_JSON` becomes
     pi's `openai-codex` login for the default model, `imagegen` and Codex-backed web
     search; `CLAUDE_CODE_OAUTH_TOKEN` enables the vendored `anthropic-omp` provider; and
     `OPENROUTER_API_KEY` (`gh secret set OPENROUTER_API_KEY`) enables the `openrouter/*`
     models. Any one credential is enough to start, but the selected model needs its own:
     the default needs the Codex login. Pick a model with the dispatch's `pi_model` input
     (`-f pi_model=openrouter/z-ai/glm-5.3`) or the `PI_MODEL` variable. The input offers
     `openai-codex/gpt-6.1-sol`, `gpt-6-astra` and `gpt-6-luna`;
     `anthropic-omp/claude-opus-5-5` and `claude-fable-5-1`; and on OpenRouter
     `deepseek/deepseek-v4.1-flash`, `z-ai/glm-5.3`, `z-ai/glm-5.3-flash`,
     `qwen/qwen3.8-max-0902`, `qwen/qwen3.8-flash` and `moonshotai/kimi-k3`. pi reads the
     OpenRouter key from the job environment; it is never written to disk.
     `harness/pi-setup.sh` builds a private `PI_CODING_AGENT_DIR` in `$RUNNER_TEMP`,
     copies `pi/extensions/` there, installs the extension's Bun runtime (and its Linux
     native addon) plus `pi-web-access`, and writes `auth.json`. The Claude token is
     **not** written there: the job exports it as `ANTHROPIC_OAUTH_TOKEN`, which the
     extension's backend reads while its own credential store is empty. The directory is
     deleted after the run. As with Codex, pi may refresh the ChatGPT token in its
     temporary copy; that refresh is not persisted, and a rotated refresh token can
     invalidate `CODEX_AUTH_JSON` for later runs. The `anthropic-omp` provider is an
     unofficial Claude subscription client (see its README's policy caveat).
3. **Push identity:** pick one. Pushes made with either identity trigger CI, which
   `GITHUB_TOKEN` pushes don't.
   - **Own GitHub App (preferred; the v0.5 bot needs it anyway).** Create an App with
     repository permissions Contents, Issues and Pull requests set to read and write,
     Metadata read, and **no** Workflows permission. Install it on this repo, then:
     ```bash
     gh variable set AGENT_APP_CLIENT_ID --body <client id>
     gh secret set AGENT_APP_PRIVATE_KEY < app.private-key.pem
     gh variable set AGENT_GIT_NAME --body '<app-slug>[bot]'
     gh variable set AGENT_GIT_EMAIL --body '<bot user id>+<app-slug>[bot]@users.noreply.github.com'
     ```
     Get the bot user id with `gh api '/users/<app-slug>[bot]' --jq .id`.
   - **Claude GitHub App (fallback when `AGENT_APP_CLIENT_ID` is unset).** Uses the
     installed [Claude app](https://github.com/apps/claude) through the same OIDC exchange
     as `anthropics/claude-code-action`. That endpoint is internal to the action and
     could change. Commits and PRs appear as `claude[bot]`.
4. **Optional variables:** `AGENT_MODEL` (Claude; defaults to `claude-opus-5-5`, Opus
   5.5), `CODEX_MODEL` (Codex; defaults to `gpt-6.1-sol`, GPT-6.1 Sol), `PI_MODEL` (pi,
   as `provider/id`; defaults to `openai-codex/gpt-6.1-sol`; the `pi_model` input wins),
   `PI_VERSION` (defaults to `0.99.1`), `AGENT_REASONING_EFFORT` (overrides every agent
   unless the dispatch's `reasoning` input is set; unset, Claude uses `low`, Codex
   `medium`, and pi the level for its model in `pi/thinking-levels.json`, else `medium`),
   `AGENT_MAX_TURNS`, `AGENT_ATTEMPTS` (default 3), `AGENT_TRUSTED_BOTS`
   (comma-separated logins, such as the bot App's `<slug>[bot]`). Existing model
   variables override these defaults; remove or update old overrides to use the new
   defaults.

For example, after the workflow change is merged:

```bash
gh workflow run agent.yml -f number=123 -f mode=implement -f agent=codex
gh workflow run agent.yml -f number=123 -f mode=implement -f agent=pi
gh workflow run agent.yml -f number=123 -f mode=implement -f agent=pi -f pi_model=openrouter/moonshotai/kimi-k3
```

The same gate, verification/retry loop, and isolated App-token publisher apply to every
agent. Codex and pi still need one of the push identities above; their model logins do not
provide GitHub permissions.

## Local runs

```bash
echo "Add a jump pad that launches players upward" > /tmp/task.md
harness/run.sh --agent claude --mode implement --branch agent/0-jump-pad --task /tmp/task.md --out /tmp/run
```

All three adapters use the same model and reasoning defaults locally and on
retries/resumes: Claude `claude-opus-5-5` with low effort, Codex `gpt-6.1-sol` with
medium effort, and pi `openai-codex/gpt-6.1-sol` with its per-model thinking level from
`pi/thinking-levels.json` (for example `max` for the OpenRouter models, `low` for Claude;
`medium` for unlisted models). `pi-setup.sh` also writes that map to the runner's pi
`settings.json` as `modelThinkingLevels`. Override with `HARNESS_MODEL` and
`HARNESS_REASONING_EFFORT` (pi's `--thinking` level). `result.json` records the effort as
`reasoning_effort`, and publish shows it in the PR's Agent Usage section and the 🤖
comments. Locally, pi uses your own `~/.pi/agent` login and extensions unless
`PI_CODING_AGENT_DIR` points elsewhere.

This needs a clean tree. It leaves you on the new branch, and `/tmp/run` holds the logs
and `summary.md`. Nothing is pushed.
