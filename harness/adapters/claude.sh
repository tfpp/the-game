#!/usr/bin/env bash
# Claude Code adapter. Usage: claude.sh PROMPT_FILE LOG_FILE CONTINUE(0|1)
# Env: HARNESS_OUT (required), HARNESS_MODEL (claude-opus-5-5),
# HARNESS_REASONING_EFFORT (low), HARNESS_MAX_TURNS.
# Writes the call's token usage to $HARNESS_OUT/usage.json (see run.sh).
# Auth comes from CLAUDE_CODE_OAUTH_TOKEN (claude setup-token) or ANTHROPIC_API_KEY.
# harness/progress.sh prints the trace and streams progress to Discord when configured.
set -euo pipefail
prompt="$1" log="$2" cont="$3"
progress="$(cd "$(dirname "$0")/.." && pwd)/progress.sh"
session_file="$HARNESS_OUT/claude-session"

args=(-p --output-format stream-json --verbose --dangerously-skip-permissions)
args+=(--model "${HARNESS_MODEL:-claude-opus-5-5}" --effort "${HARNESS_REASONING_EFFORT:-low}")
[[ -n "${HARNESS_MAX_TURNS:-}" ]] && args+=(--max-turns "$HARNESS_MAX_TURNS")
if [[ "$cont" == 1 && -s "$session_file" ]]; then
  args+=(--resume "$(cat "$session_file")")
else
  uuidgen | tr '[:upper:]' '[:lower:]' >"$session_file"
  args+=(--session-id "$(cat "$session_file")")
fi

# Full event stream goes to the log; a readable trace goes to stdout (the Actions log).
set +e
claude "${args[@]}" <"$prompt" | tee "$log" | "$progress" claude
status="${PIPESTATUS[0]}"
set -e

jq -rs 'map(select(.type == "result")) | last | .result // empty' "$log" >"$HARNESS_OUT/last-message.md" 2>/dev/null || true
# Usage of this call. total_cost_usd is at API prices, also on a subscription.
jq -cs --arg model "${HARNESS_MODEL:-claude-opus-5-5}" '
  (([.[] | select(.type == "assistant") | .message.model? | select(type == "string" and length > 0)] +
    [.[] | select(.type == "result") | .modelUsage? | select(type == "object") | keys[]]) | unique) as $reported |
  map(select(.type == "result")) | select(length > 0) | {
  models: (if ($reported | length) > 0 then $reported else [$model] end),
  cost_basis: "adapter-reported",
  input_tokens: (map(.usage.input_tokens // 0) | add),
  output_tokens: (map(.usage.output_tokens // 0) | add),
  cache_read_tokens: (map(.usage.cache_read_input_tokens // 0) | add),
  cache_write_tokens: (map(.usage.cache_creation_input_tokens // 0) | add),
  cost_usd: (map(.total_cost_usd // 0) | add)}' "$log" >"$HARNESS_OUT/usage.json" 2>/dev/null || true
exit "$status"
