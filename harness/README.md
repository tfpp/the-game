# harness

Runs a coding agent against this repo and turns its work into a PR. `verify.sh` is the
definition of done for agents and humans alike.

| File | What |
|---|---|
| `verify.sh` | Harness tests, then `game/scripts/check.sh`, then Go checks |
| `run.sh` | Sets up the branch, runs the agent, re-runs `verify.sh` and sends failures back (up to `--attempts`), commits, and bundles the new commits. Never pushes |
| `adapters/<agent>.sh` | One per CLI (`claude`, `codex`, `pi`): `PROMPT_FILE LOG_FILE CONTINUE` |
| `prompts/` | `rules.md` (every run), one file per mode, `fix.md` (retries) |
| `gate.sh` | Turns a GitHub event into run inputs, or refuses it |
| `context.sh` | Writes the task, current PR, sibling PRs and paths, recent merges, and feedback from GitHub |
| `check-summary.sh` | Requires integration review notes before agent-written work can be bundled |
| `publish.sh` | Pushes the bundle, opens the PR or comments, reports failures |
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

## Setup

1. **Label:** `gh label create agent --color 5319e7 --description "Run the coding agent"`.
2. **Model credential:** run `claude setup-token` locally, then
   `gh secret set CLAUDE_CODE_OAUTH_TOKEN`.
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
4. **Optional variables:** `AGENT_MODEL`, `AGENT_MAX_TURNS`, `AGENT_ATTEMPTS` (default 3),
   `AGENT_TRUSTED_BOTS` (comma-separated logins, such as the bot App's `<slug>[bot]`).

## Local runs

```bash
echo "Add a jump pad that launches players upward" > /tmp/task.md
harness/run.sh --agent claude --mode implement --branch agent/0-jump-pad --task /tmp/task.md --out /tmp/run
```

This needs a clean tree. It leaves you on the new branch, and `/tmp/run` holds the logs
and `summary.md`. Nothing is pushed.
