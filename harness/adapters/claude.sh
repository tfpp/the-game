#!/usr/bin/env bash
# Claude Code adapter. Usage: claude.sh PROMPT_FILE LOG_FILE CONTINUE(0|1)
# Env: HARNESS_OUT (required), HARNESS_MODEL, HARNESS_MAX_TURNS.
# Writes the call's token usage to $HARNESS_OUT/usage.json (see run.sh).
# Auth comes from CLAUDE_CODE_OAUTH_TOKEN (claude setup-token) or ANTHROPIC_API_KEY.
set -euo pipefail
prompt="$1" log="$2" cont="$3"
session_file="$HARNESS_OUT/claude-session"

args=(-p --output-format stream-json --verbose --dangerously-skip-permissions)
[[ -n "${HARNESS_MODEL:-}" ]] && args+=(--model "$HARNESS_MODEL")
[[ -n "${HARNESS_MAX_TURNS:-}" ]] && args+=(--max-turns "$HARNESS_MAX_TURNS")
if [[ "$cont" == 1 && -s "$session_file" ]]; then
  args+=(--resume "$(cat "$session_file")")
else
  uuidgen | tr '[:upper:]' '[:lower:]' >"$session_file"
  args+=(--session-id "$(cat "$session_file")")
fi

# Full event stream goes to the log; a readable trace goes to stdout (the Actions log).
set +e
claude "${args[@]}" <"$prompt" | tee "$log" | jq -rj --unbuffered '
  if .type == "assistant" then
    (.message.content[]? |
      if .type == "text" then .text + "\n"
      elif .type == "tool_use" then "  > \(.name) \(.input.command // .input.file_path // .input.pattern // "" | tostring | .[0:160])\n"
      else empty end)
  elif .type == "result" then "\n[result] \(.subtype) turns=\(.num_turns) cost=$\(.total_cost_usd // 0)\n"
  else empty end' 2>/dev/null
status="${PIPESTATUS[0]}"
set -e

jq -rs 'map(select(.type == "result")) | last | .result // empty' "$log" >"$HARNESS_OUT/last-message.md" 2>/dev/null || true
# Usage of this call. total_cost_usd is at API prices, also on a subscription.
jq -cs 'map(select(.type == "result")) | select(length > 0) | {
  input_tokens: (map(.usage.input_tokens // 0) | add),
  output_tokens: (map(.usage.output_tokens // 0) | add),
  cache_read_tokens: (map(.usage.cache_read_input_tokens // 0) | add),
  cache_write_tokens: (map(.usage.cache_creation_input_tokens // 0) | add),
  cost_usd: (map(.total_cost_usd // 0) | add)}' "$log" >"$HARNESS_OUT/usage.json" 2>/dev/null || true
exit "$status"
