#!/usr/bin/env bash
# Codex CLI adapter. Usage: codex.sh PROMPT_FILE LOG_FILE CONTINUE(0|1)
# Env: HARNESS_OUT (required), HARNESS_MODEL (gpt-6-astra), HARNESS_REASONING_EFFORT (low).
# Auth: a persisted auth.json login in CODEX_HOME (defaults to ~/.codex).
# Writes the call's token usage to $HARNESS_OUT/usage.json (see run.sh).
set -euo pipefail
prompt="$1" log="$2" cont="$3"
session_file="$HARNESS_OUT/codex-session"

opts=(--json --dangerously-bypass-approvals-and-sandbox -o "$HARNESS_OUT/last-message.md")
model="${HARNESS_MODEL:-gpt-6-astra}"
opts+=(-m "$model")
opts+=(-c "model_reasoning_effort=$(jq -cn --arg effort "${HARNESS_REASONING_EFFORT:-low}" '$effort')")

set +e
if [[ "$cont" == 1 && -s "$session_file" ]]; then
  codex exec resume "${opts[@]}" "$(cat "$session_file")" - <"$prompt" >"$log" 2>&1
else
  codex exec "${opts[@]}" - <"$prompt" >"$log" 2>&1
fi
status=$?
set -e

jq -r 'select(.type == "thread.started") | .thread_id' "$log" 2>/dev/null | head -1 >"$session_file.new" || true
[[ -s "$session_file.new" ]] && mv "$session_file.new" "$session_file"
rm -f "$session_file.new"
# Usage of this call. input_tokens includes the cached ones; preserve the split.
# API-equivalent estimate, not billed CLI cost. Standard short-context rates per
# 1M tokens: $10 input, $1 cached input, $12.50 cache writes, $50 output.
# Sources: https://developers.openai.com/api/docs/pricing
#          https://developers.openai.com/api/docs/models/gpt-6-astra
# Long-context pricing applies above 272K tokens per request, but turn.completed
# aggregates requests: totals cannot establish that threshold. Use the explicit
# short-context baseline only, excluding tool fees. Do not price other models.
# Events do not report the actual model; models records the effective CLI model.
jq -cs --arg model "$model" 'map(select(.type == "turn.completed") | .usage) | select(length > 0) | {
  input_tokens: (map((.input_tokens // 0) - (.cached_input_tokens // 0)) | add),
  output_tokens: (map(.output_tokens // 0) | add),
  cache_read_tokens: (map(.cached_input_tokens // 0) | add),
  cache_write_tokens: (map(.cache_write_input_tokens // 0) | add),
  cost_usd: null,
  models: [$model],
  cost_basis: (if $model == "gpt-6-astra" then
    "standard short-context token estimate; excludes tool fees"
    else "unavailable: unsupported model" end)
} | if $model == "gpt-6-astra" then
  .cost_usd = ((.input_tokens * 10 + .cache_read_tokens +
    .cache_write_tokens * 12.5 + .output_tokens * 50) / 1000000)
else . end' "$log" >"$HARNESS_OUT/usage.json" 2>/dev/null || true
cat "$HARNESS_OUT/last-message.md" 2>/dev/null || true
exit "$status"
