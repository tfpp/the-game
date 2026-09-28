#!/usr/bin/env bash
# Codex CLI adapter. Usage: codex.sh PROMPT_FILE LOG_FILE CONTINUE(0|1)
# Env: HARNESS_OUT (required), HARNESS_MODEL. Auth: a persisted ~/.codex/auth.json login.
# Writes the call's token usage to $HARNESS_OUT/usage.json (see run.sh).
set -euo pipefail
prompt="$1" log="$2" cont="$3"
session_file="$HARNESS_OUT/codex-session"

opts=(--json --dangerously-bypass-approvals-and-sandbox -o "$HARNESS_OUT/last-message.md")
[[ -n "${HARNESS_MODEL:-}" ]] && opts+=(-m "$HARNESS_MODEL")

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
# Usage of this call. input_tokens includes the cached ones; there is no cost.
jq -cs 'map(select(.type == "turn.completed") | .usage) | select(length > 0) | {
  input_tokens: (map((.input_tokens // 0) - (.cached_input_tokens // 0)) | add),
  output_tokens: (map(.output_tokens // 0) | add),
  cache_read_tokens: (map(.cached_input_tokens // 0) | add),
  cache_write_tokens: (map(.cache_write_input_tokens // 0) | add),
  cost_usd: null}' "$log" >"$HARNESS_OUT/usage.json" 2>/dev/null || true
cat "$HARNESS_OUT/last-message.md" 2>/dev/null || true
exit "$status"
