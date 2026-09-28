#!/usr/bin/env bash
# Runs a coding agent on this repo until harness/verify.sh passes, then commits the result
# and bundles the new commits for harness/publish.sh. It never pushes or talks to GitHub.
#
# Usage:
#   harness/run.sh --agent claude|codex|pi --mode implement|revise|resolve-conflicts \
#     --task FILE --branch NAME [--base main] [--out DIR] [--attempts 3]
#
#   implement          creates --branch from the base
#   revise             merges the base into --branch, then addresses feedback
#   resolve-conflicts  checks out --branch and merges the base into it
#
# Outputs in --out: result.json, summary.md, changes.bundle (on success), protected.txt,
# prompt-N.md, agent-N.log and verify-N.log per attempt.
# Adapters may write the token usage of each call to $HARNESS_OUT/usage.json
# ({input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, cost_usd}, cost
# null when unknown); result.json's usage is the sum over calls, or null.
# Adapters may also report models (actual IDs) and cost_basis; these are collected
# across calls. Without reported models, the configured model is recorded, and
# reasoning_effort is the effort given to the adapter (null if it takes none).
# Env: HARNESS_MODEL, HARNESS_REASONING_EFFORT, HARNESS_MAX_TURNS (passed to adapters),
#      HARNESS_REMOTE (origin),
#      HARNESS_VERIFY and HARNESS_ADAPTERS (overrides, for tests).
# Exit: 0 for success or no_changes, 2 when the agent failed, 1 on harness errors.
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$(dirname "$0")/lib.sh"
shopt -u patsub_replacement 2>/dev/null || true # keep '&' literal in ${x//a/b}

agent="" mode="" task="" branch="" base="main" out="" attempts=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) agent="$2" ;;
    --mode) mode="$2" ;;
    --task) task="$2" ;;
    --branch) branch="$2" ;;
    --base) base="$2" ;;
    --out) out="$2" ;;
    --attempts) attempts="$2" ;;
    -h | --help)
      sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
  shift 2
done

adapters="${HARNESS_ADAPTERS:-$HARNESS_DIR/adapters}"
verify="${HARNESS_VERIFY:-$HARNESS_DIR/verify.sh}"
remote="${HARNESS_REMOTE:-origin}"

[[ -x "$adapters/$agent.sh" ]] || die "unknown agent '$agent' (see $adapters)"
case "$mode" in implement | revise | resolve-conflicts) ;; *) die "unknown mode '$mode'" ;; esac
[[ -f "$task" ]] || die "--task file not found: $task"
[[ -n "$branch" ]] || die "--branch is required"
[[ "$attempts" =~ ^[1-9][0-9]*$ ]] || die "--attempts must be a positive number"

task="$(cd "$(dirname "$task")" && pwd)/$(basename "$task")"
out="${out:-$(mktemp -d)}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
case "$out/" in "$REPO_ROOT"/*) die "--out must be outside the repo" ;; esac
export HARNESS_OUT="$out"
rm -f "$out"/{result.json,summary.md,last-message.md,changes.bundle,protected.txt,usage.json}

cd "$REPO_ROOT"
[[ -z "$(git status --porcelain)" ]] || die "working tree is not clean"

base_ref="$base"
git rev-parse -q --verify "refs/remotes/$remote/$base" >/dev/null && base_ref="$remote/$base"
git rev-parse -q --verify "$base_ref^{commit}" >/dev/null || die "base '$base' not found"
base_sha="$(git rev-parse "$base_ref^{commit}")"

# --- branch setup ----------------------------------------------------------------------
merge_conflicts=0
case "$mode" in
  implement)
    git rev-parse -q --verify "refs/heads/$branch" >/dev/null && die "branch $branch already exists"
    git switch -q -c "$branch" "$base_sha"
    ;;
  revise | resolve-conflicts)
    if git rev-parse -q --verify "refs/remotes/$remote/$branch" >/dev/null; then
      git switch -q -C "$branch" "$remote/$branch"
    else
      git switch -q "$branch"
    fi
    ;;
esac
start_sha="$(git rev-parse HEAD)"
log "mode=$mode agent=$agent branch=$branch base=$base_ref start=${start_sha:0:12}"

if [[ "$mode" == revise || "$mode" == resolve-conflicts ]]; then
  # Leave even clean merges uncommitted until the combined tree passes verification.
  if git merge -q --no-commit --no-ff "$base_sha"; then
    log "merged $base_ref cleanly"
  elif [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
    merge_conflicts=1
    log "merge conflicts: $(git diff --name-only --diff-filter=U | tr '\n' ' ')"
  else
    die "merging $base_ref failed without conflicts"
  fi
fi

# --- prompt rendering ------------------------------------------------------------------
render() { # render FILE [PROBLEM] -> stdout
  local text
  text="$(cat "$1")"
  text="${text//\{\{BRANCH\}\}/$branch}"
  text="${text//\{\{BASE\}\}/$base}"
  text="${text//\{\{BASE_SHA\}\}/$base_sha}"
  text="${text//\{\{OUT\}\}/$out}"
  text="${text//\{\{PROBLEM\}\}/${2:-}}"
  text="${text//\{\{TASK\}\}/$(cat "$task")}"
  printf '%s\n' "$text"
}

# Prints what is still wrong, or nothing when the work is done.
check_work() {
  local n="$1" unmerged markers
  if [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]]; then
    unmerged="$(git diff --name-only --diff-filter=U)"
    if [[ -n "$unmerged" ]]; then
      printf 'These files still have merge conflicts:\n%s\n' "$unmerged"
      return
    fi
  fi
  markers="$(git diff "$start_sha" --name-only | while IFS= read -r f; do
    [[ -f "$f" ]] && grep -lE '^(<<<<<<<|>>>>>>>) ' -- "$f" || true
  done)"
  if [[ -n "$markers" ]]; then
    printf 'These files contain conflict markers:\n%s\n' "$markers"
    return
  fi
  log "verify (attempt $n)"
  if ! "$verify" >"$out/verify-$n.log" 2>&1; then
    printf '`harness/verify.sh` failed. The end of its output:\n\n```\n%s\n```\n' \
      "$(tail -n 150 "$out/verify-$n.log")"
    return
  fi
  # A clean base merge (attempt 0) has no agent design decision to report.
  if [[ "$n" -gt 0 ]] && ! "$HARNESS_DIR/check-summary.sh" "$out/summary.md" >"$out/summary-$n.log"; then
    cat "$out/summary-$n.log" | tee -a "$out/verify-$n.log"
    printf 'Inspect the existing systems, record whether you extended one or needed a new system, and update summary.md using the required Integration subsections.\n'
  fi
}

# --- agent loop ------------------------------------------------------------------------
usage=null
models='[]'
cost_basis='[]'
# Pin the default so reporting and the adapter use the same model. Adapters can
# report actual model IDs (e.g. Claude aliases/subagents) in their usage record.
model="${HARNESS_MODEL:-}"
case "$agent" in
  claude) model="${model:-claude-opus-5-5}" ;;
  codex) model="${model:-gpt-6-astra}" ;;
esac
export HARNESS_MODEL="$model"
# Record the reasoning effort the adapter is given; the pi adapter doesn't take one.
effort="${HARNESS_REASONING_EFFORT:-}"
case "$agent" in
  claude | codex) effort="${effort:-low}" ;;
esac
# add_usage: adds the last adapter call's usage.json to $usage. A missing cost makes the
# total's cost unknown.
add_usage() {
  local call reported basis
  reported="$(jq -c '[.models[]? | select(type == "string" and length > 0)]' "$out/usage.json" 2>/dev/null)" || reported='[]'
  [[ -n "$reported" ]] || reported='[]'
  if [[ "$reported" == '[]' ]]; then
    reported="$(jq -cn --arg model "$model" '[ $model | select(length > 0) ]')"
  fi
  models="$(jq -cn --argjson a "$models" --argjson b "$reported" '$a + $b | unique')"
  basis="$(jq -c '[.cost_basis | select(type == "string" and length > 0)]' "$out/usage.json" 2>/dev/null)" || basis='[]'
  [[ -n "$basis" ]] || basis='[]'
  cost_basis="$(jq -cn --argjson a "$cost_basis" --argjson b "$basis" '$a + $b | unique')"
  call="$(jq -c 'select(type == "object") | with_entries(select(.value | type == "number" or . == null))' \
    "$out/usage.json" 2>/dev/null)" || return 0
  rm -f "$out/usage.json"
  [[ -n "$call" && "$call" != "{}" ]] || return 0
  usage="$(jq -cn --argjson a "$usage" --argjson b "$call" '
    def n: if type == "number" then . else 0 end;
    ($a // {}) as $a | {
      input_tokens: (($a.input_tokens | n) + ($b.input_tokens | n)),
      output_tokens: (($a.output_tokens | n) + ($b.output_tokens | n)),
      cache_read_tokens: (($a.cache_read_tokens | n) + ($b.cache_read_tokens | n)),
      cache_write_tokens: (($a.cache_write_tokens | n) + ($b.cache_write_tokens | n)),
      cost_usd: (if ($a == {} or ($a.cost_usd | type) == "number") and ($b.cost_usd | type) == "number"
        then ($a.cost_usd | n) + $b.cost_usd else null end)}')"
}
status="failed"
attempt=0
problem=""
# A clean merge may need no agent at all.
if [[ "$mode" == resolve-conflicts && "$merge_conflicts" == 0 ]]; then
  problem="$(check_work 0)"
  if [[ -z "$problem" ]]; then
    status="success"
    printf 'chore: merge %s into this branch\n\n## Summary\nMerged `%s` cleanly; verify passed.\n\n## Integration\nIntegrated base commit `%s`.\n\n## Validation\n`harness/verify.sh` passed on the combined tree.\n' \
      "$base" "$base" "$base_sha" >"$out/summary.md"
  fi
fi

while [[ "$status" != success && "$attempt" -lt "$attempts" ]]; do
  attempt=$((attempt + 1))
  prompt="$out/prompt-$attempt.md"
  if [[ "$attempt" == 1 ]]; then
    {
      render "$HARNESS_DIR/prompts/rules.md"
      echo
      render "$HARNESS_DIR/prompts/$mode.md"
      if [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]]; then
        printf '\nA merge of base commit `%s` is in progress. Resolve any conflicts preserving both changes, then complete the task. Stage the resolution, but do not commit or abort the merge; the harness commits after verification.\n' "$base_sha"
      fi
      if [[ -n "$problem" ]]; then # clean merge that fails verify
        echo
        render "$HARNESS_DIR/prompts/fix.md" "$problem"
      fi
    } >"$prompt"
    cont=0
  else
    render "$HARNESS_DIR/prompts/fix.md" "$problem" >"$prompt"
    cont=1
  fi

  log "agent attempt $attempt/$attempts"
  rm -f "$out/usage.json"
  agent_ok=1
  "$adapters/$agent.sh" "$prompt" "$out/agent-$attempt.log" "$cont" || agent_ok=0
  add_usage
  if [[ "$agent_ok" == 0 ]]; then
    log "agent exited with an error"
    status="agent_error"
    break
  fi

  # The agent declined (unclear or unsafe request) and left the branch untouched.
  if [[ "$mode" != resolve-conflicts && "$(git rev-parse HEAD)" == "$start_sha" &&
    ! -f "$(git rev-parse --git-path MERGE_HEAD)" &&
    -z "$(git status --porcelain)" ]] && grep -qi '^no changes' "$out/summary.md" 2>/dev/null; then
    status="no_changes"
    break
  fi

  problem="$(check_work "$attempt")"
  if [[ -z "$problem" ]]; then
    status="success"
  else
    log "not done: $(head -n 1 <<<"$problem")"
  fi
done

# --- commit ----------------------------------------------------------------------------
title=""
[[ -f "$out/summary.md" ]] && title="$(head -n 1 "$out/summary.md" | sed -E 's/^[[:space:]#]+//; s/[[:space:]]+$//')"
valid_title "$title" || title="${HARNESS_FALLBACK_TITLE:-chore: apply agent changes}"

if [[ "$status" == success ]]; then
  git add -A
  if [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]]; then
    git commit -q -m "$title"
  elif ! git diff --cached --quiet; then
    git commit -q -m "$title"
  fi
  if [[ "$(git rev-parse HEAD)" == "$start_sha" ]]; then
    status="no_changes"
  else
    git bundle create -q "$out/changes.bundle" "refs/heads/$branch" "^$start_sha"
  fi
fi

git diff --name-only "$base_sha...HEAD" | filter_protected >"$out/protected.txt" || true
head_sha="$(git rev-parse HEAD)"

jq -n \
  --arg status "$status" --arg mode "$mode" --arg agent "$agent" \
  --arg branch "$branch" --arg base "$base" --arg title "$title" \
  --arg start_sha "$start_sha" --arg head_sha "$head_sha" --arg base_sha "$base_sha" --argjson attempts "$attempt" \
  --argjson usage "$usage" --argjson models "$models" --argjson cost_basis "$cost_basis" \
  --arg effort "$effort" \
  '{status: $status, mode: $mode, agent: $agent, branch: $branch, base: $base,
    title: $title, start_sha: $start_sha, head_sha: $head_sha, base_sha: $base_sha, attempts: $attempts, models: $models, cost_basis: $cost_basis, usage: $usage,
    reasoning_effort: ($effort | select(length > 0) // null)}' \
  >"$out/result.json"

log "status=$status attempts=$attempt head=${head_sha:0:12} usage=$usage out=$out"
[[ -s "$out/protected.txt" ]] && log "touched human-review paths: $(tr '\n' ' ' <"$out/protected.txt")"
case "$status" in success | no_changes) exit 0 ;; *) exit 2 ;; esac
