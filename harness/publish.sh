#!/usr/bin/env bash
# Publishes an agent run: pushes the bundled commits, opens the PR (implement) or comments
# on it (revise, resolve-conflicts), and reports failures on the issue or PR.
#
# Runs in agent.yml's publish job, on a fresh checkout of the default branch, with the
# GitHub App token. Everything in OUT was produced by the agent job and is untrusted: it is
# only read as data (never sourced or executed), and the branch name comes from the gate.
#
# Env: GH_TOKEN, GITHUB_REPOSITORY, OUT (downloaded artifact dir, may be missing), MODE,
#      AGENT, ISSUE, PR, BRANCH, TARGET, BASE (main), RUN_URL, AGENT_JOB_RESULT,
#      AGENT_LABEL (agent), HARNESS_PUSH_URL (tests only; defaults to the GitHub repo).
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$(dirname "$0")/lib.sh"

repo="$GITHUB_REPOSITORY"
base="${BASE:-main}"
label="${AGENT_LABEL:-agent}"
run_link="[run](${RUN_URL:-})"
tmp="$(mktemp -d)"
cd "$REPO_ROOT"

comment() { # comment NUMBER BODY_FILE
  gh api "repos/$repo/issues/$1/comments" -F "body=@$2" >/dev/null
}
unlabel() {
  gh api -X DELETE "repos/$repo/issues/$TARGET/labels/$label" >/dev/null 2>&1 || true
}
trap unlabel EXIT

# fence FILE LINES: the end of an untrusted file inside a collapsed code block.
fence() {
  [[ -s "$1" ]] || return 0
  printf '\n<details><summary>%s</summary>\n\n````\n%s\n````\n</details>\n' \
    "$(basename "$1")" "$(tail -n "$2" "$1" | cut -c1-300 | sed 's/````/```/g')"
}

report_failure() { # report_failure MESSAGE [nologs]
  {
    printf '🤖 `%s` (`%s`) did not produce a change: %s (%s)\n' "$AGENT" "$MODE" "$1" "$run_link"
    if [[ -d "${OUT:-}" && -z "${2:-}" ]]; then
      last_verify="$(find "$OUT" -name 'verify-*.log' | sort -V | tail -n 1)"
      [[ -z "$last_verify" ]] || fence "$last_verify" 60
      fence "$OUT/last-message.md" 40
    fi
  } >"$tmp/body.md"
  comment "$TARGET" "$tmp/body.md"
}

result="${OUT:-/nonexistent}/result.json"
if [[ ! -s "$result" ]]; then
  report_failure "the agent job ended without a result (job status: ${AGENT_JOB_RESULT:-unknown})"
  exit 1
fi

status="$(jq -r '.status // empty' "$result")"
attempts="$(jq -r '.attempts // 0 | tonumber? // 0' "$result")"
title="$(jq -r '.title // empty' "$result" | head -n 1)"

case "$status" in
  success) ;;
  no_changes)
    {
      printf '🤖 `%s` (`%s`) made no changes (%s).\n\n' "$AGENT" "$MODE" "$run_link"
      if [[ -s "$OUT/summary.md" ]]; then
        tail -n +2 "$OUT/summary.md" | head -c 20000
      else
        tail -n 40 "$OUT/last-message.md" 2>/dev/null || true
      fi
    } >"$tmp/body.md"
    comment "$TARGET" "$tmp/body.md"
    exit 0
    ;;
  failed) report_failure "the work did not pass harness checks after $attempts attempt(s)" && exit 1 ;;
  agent_error) report_failure "the agent exited with an error" && exit 1 ;;
  *) report_failure "unknown status \`$status\`" && exit 1 ;;
esac

# --- push -----------------------------------------------------------------------------
bundle="$OUT/changes.bundle"
[[ -s "$bundle" ]] || {
  report_failure "the result has no commits bundle"
  exit 1
}
git bundle verify -q "$bundle" >/dev/null 2>&1 || {
  report_failure "the commits bundle is invalid"
  exit 1
}
git fetch -q "$bundle" "refs/heads/$BRANCH:refs/harness/result"
base_ref="origin/$base"
changed="$(git diff --name-only "$base_ref...refs/harness/result")"

# The App has no Workflows permission on purpose, so a PR can't smuggle in new CI.
if grep -q '^\.github/workflows/' <<<"$changed"; then
  report_failure "the change edits \`.github/workflows/\`, which agents can't push. A human needs to make that change"
  exit 1
fi

auth="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
if ! git -c "http.https://github.com/.extraheader=$auth" push -q \
  "${HARNESS_PUSH_URL:-https://github.com/$repo.git}" "refs/harness/result:refs/heads/$BRANCH" 2>"$tmp/push.log"; then
  cat "$tmp/push.log" >&2
  reason="$(grep -E '^ ! |^remote: |^error: ' "$tmp/push.log" | head -n 5 | cut -c1-300)"
  hint=""
  grep -q 'without `workflows` permission' "$tmp/push.log" &&
    hint=" Main changed a workflow during the run, so the branch looks like it reverts it. Start the run again."
  grep -q 'non-fast-forward\|fetch first' "$tmp/push.log" &&
    hint=" Someone pushed to the branch during the run. Start the run again."
  report_failure "pushing \`$BRANCH\` failed.$hint"$'\n\n```\n'"$reason"$'\n```' nologs
  exit 1
fi
head_sha="$(git rev-parse refs/harness/result)"
log "pushed $BRANCH at $head_sha"

# --- describe -------------------------------------------------------------------------
protected="$(filter_protected <<<"$changed" || true)"
summary_body() {
  local body=""
  [[ -s "$OUT/summary.md" ]] && body="$(tail -n +2 "$OUT/summary.md" | sed '/./,$!d' | head -c 20000)"
  [[ "$body" == *"## Summary"* ]] || body="$(printf '## Summary\n%s\n' "${body:-No summary was written.}")"
  printf '%s\n' "$body"
}
warning() {
  [[ -n "$protected" ]] || return 0
  printf '\n> [!WARNING]\n> This touches human-review paths (CODEOWNERS), so it needs a human approval:\n'
  sed 's/^/> - `/; s/$/`/' <<<"$protected"
}
footer() {
  printf '\n---\n🤖 `%s` · %s · verify passed after %s attempt(s)\n' "$AGENT" "$run_link" "$attempts"
  local checked_base
  checked_base="$(jq -r '.base_sha // empty' "$result")"
  if [[ "$checked_base" =~ ^[0-9a-f]{40}$ ]]; then
    printf '\nVerified with base commit `%s`.\n' "$checked_base"
    if [[ "$checked_base" != "$(git rev-parse "$base_ref")" ]]; then
      printf '\nThe base has moved since this run. The merge coordinator must update this branch and wait for CI before merging.\n'
    fi
  fi
}

if [[ "$MODE" == implement ]]; then
  issue_json="$(gh api "repos/$repo/issues/$ISSUE")"
  valid_title "$title" || title="feat: $(jq -r .title <<<"$issue_json" | cut -c1-60)"
  {
    summary_body
    printf '\nCloses #%s\n\n## Discord Request\n' "$ISSUE"
    jq -r "$ISSUE_JQ"'"**\(.title)**" + (request_body | if test("\\S") then "\n\n" + . else "" end)' <<<"$issue_json" | sed 's/^/> /'
    printf '\n– requested by %s\n' "$(jq -r "$ISSUE_JQ requester" <<<"$issue_json")"
    warning
    footer
  } >"$tmp/pr.md"
  url="$(gh pr create --repo "$repo" --base "$base" --head "$BRANCH" --title "$title" --body-file "$tmp/pr.md")"
  printf '🤖 Opened %s\n' "$url" >"$tmp/body.md"
  comment "$ISSUE" "$tmp/body.md"
  log "opened $url"
else
  {
    printf '🤖 Pushed %s: **%s**\n\n' "$head_sha" "${title:-update}"
    summary_body
    warning
    footer
  } >"$tmp/body.md"
  comment "$PR" "$tmp/body.md"
fi
