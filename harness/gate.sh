#!/usr/bin/env bash
# Decides whether a GitHub event should start an agent run, and with what inputs.
# Runs in agent.yml's gate job. Reads GITHUB_EVENT_NAME / GITHUB_EVENT_PATH and writes
# ok, mode, agent, issue, pr, branch, target and instructions to GITHUB_OUTPUT.
#
# Triggers (the sender needs write access, or must be listed in AGENT_TRUSTED_BOTS):
#   issues labeled AGENT_LABEL                 -> implement
#   pull_request_target labeled AGENT_LABEL    -> revise
#   comment "/agent [text]" on an issue        -> implement, text as extra instructions
#   comment "/agent [text]" on an agent PR     -> revise with text
#   comment "/agent resolve-conflicts" on a PR -> resolve-conflicts
#   workflow_dispatch(number, mode, agent, instructions)
# Env: GH_TOKEN, GITHUB_REPOSITORY, AGENT_LABEL (agent), AGENT_TRUSTED_BOTS (comma list
# of bot logins such as "tfpp-agent[bot]"), RUN_URL (for the "started" comment).
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$(dirname "$0")/lib.sh"

event="$GITHUB_EVENT_NAME"
payload="$GITHUB_EVENT_PATH"
repo="$GITHUB_REPOSITORY"
label="${AGENT_LABEL:-agent}"
output="${GITHUB_OUTPUT:-/dev/stdout}"
ev() { jq -r "$1 // empty" "$payload"; }

emit() { printf '%s=%s\n' "$1" "$2" >>"$output"; }
reject() {
  log "not starting: $1"
  emit ok false
  if [[ -n "${2:-}" ]]; then
    gh api "repos/$repo/issues/$2/comments" -f body="🤖 Not starting the agent: $1" >/dev/null || true
  fi
  exit 0
}

# --- who ------------------------------------------------------------------------------
sender="$(ev .sender.login)"
sender_type="$(ev .sender.type)"
if [[ "$sender_type" == Bot ]]; then
  [[ ",${AGENT_TRUSTED_BOTS:-}," == *",$sender,"* ]] || reject "bot $sender is not trusted"
else
  perm="$(gh api "repos/$repo/collaborators/$sender/permission" --jq .permission 2>/dev/null || true)"
  case "$perm" in admin | maintain | write) ;; *) reject "$sender lacks write access" ;; esac
fi

# --- what -----------------------------------------------------------------------------
agent="pi" mode="" number="" instructions=""
case "$event" in
  issues)
    [[ "$(ev .label.name)" == "$label" ]] || reject "label is not $label"
    mode="implement" number="$(ev .issue.number)"
    ;;
  pull_request_target)
    [[ "$(ev .label.name)" == "$label" ]] || reject "label is not $label"
    mode="revise" number="$(ev .pull_request.number)"
    ;;
  issue_comment)
    body="$(ev .comment.body | tr -d '\r')"
    [[ "$body" =~ ^/agent([[:space:]]|$) ]] || reject "comment is not an /agent command"
    instructions="$(printf '%s' "${body#/agent}" | sed -E '1s/^[[:space:]]+//')"
    number="$(ev .issue.number)"
    if [[ -n "$(ev .issue.pull_request.url)" ]]; then
      mode="revise"
      if [[ "$(head -n 1 <<<"$instructions" | tr -d '[:space:]')" == resolve-conflicts ]]; then
        mode="resolve-conflicts" instructions="$(tail -n +2 <<<"$instructions")"
      fi
    else
      mode="implement"
    fi
    ;;
  workflow_dispatch)
    mode="$(ev .inputs.mode)" number="$(ev .inputs.number)"
    agent="$(ev .inputs.agent)" instructions="$(ev .inputs.instructions)"
    agent="${agent:-pi}"
    ;;
  *) reject "unsupported event $event" ;;
esac
[[ "$number" =~ ^[0-9]+$ ]] || reject "no issue or PR number"
case "$agent" in claude | codex | pi) ;; *) reject "unknown agent $agent" "$number" ;; esac

# --- where ----------------------------------------------------------------------------
pr=""
if [[ "$mode" == implement ]]; then
  info="$(gh api "repos/$repo/issues/$number")"
  [[ "$(jq -r '.pull_request.url // empty' <<<"$info")" == "" ]] ||
    reject "#$number is a pull request; implement needs an issue" "$number"
  [[ "$(jq -r .state <<<"$info")" == open ]] || reject "issue #$number is closed" "$number"
  issue="$number"
  existing="$(gh api "repos/$repo/git/matching-refs/heads/agent/$issue-" --jq '.[].ref' | head -n 1)"
  [[ -z "$existing" ]] ||
    reject "branch \`${existing#refs/heads/}\` already exists for this issue. Comment \`/agent <feedback>\` on its PR to revise it." "$number"
  branch="$(branch_for_issue "$issue" "$(jq -r .title <<<"$info")")"
  target="$issue"
else
  info="$(gh api "repos/$repo/pulls/$number")"
  pr="$number"
  [[ "$(jq -r .state <<<"$info")" == open ]] || reject "PR #$pr is not open" "$pr"
  [[ "$(jq -r .head.repo.full_name <<<"$info")" == "$repo" ]] ||
    reject "PR #$pr comes from a fork" "$pr"
  branch="$(jq -r .head.ref <<<"$info")"
  issue="$(issue_from_branch "$branch")" || reject "PR #$pr is not an agent branch (agent/<issue>-…)" "$pr"
  target="$pr"
fi

emit ok true
emit mode "$mode"
emit agent "$agent"
emit issue "$issue"
emit pr "$pr"
emit branch "$branch"
emit target "$target"
delim="EOF_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
printf 'instructions<<%s\n%s\n%s\n' "$delim" "$instructions" "$delim" >>"$output"
log "starting: mode=$mode agent=$agent issue=$issue pr=${pr:-none} branch=$branch"

gh api "repos/$repo/issues/$target/comments" \
  -f body="🤖 Starting \`$agent\` (\`$mode\`) on \`$branch\`. [Follow the run](${RUN_URL:-})." >/dev/null || true
