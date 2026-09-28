#!/usr/bin/env bash
# pi adapter. Usage: pi.sh PROMPT_FILE LOG_FILE CONTINUE(0|1)
# Env: HARNESS_OUT (required), HARNESS_MODEL. Auth: a persisted pi auth.json login.
# Writes the call's token usage to $HARNESS_OUT/usage.json (see run.sh).
set -euo pipefail
prompt="$1" log="$2" cont="$3"

sessions="$HARNESS_OUT/pi-sessions"
# session_usage: the summed usage of every assistant message in the session files.
session_usage() {
  { find "$sessions" -name '*.jsonl' -exec cat {} + 2>/dev/null || true; } |
    jq -cs 'map(select(.type == "message" and .message.role == "assistant") | .message.usage // empty) | {
      input_tokens: (map(.input // 0) | add // 0), output_tokens: (map(.output // 0) | add // 0),
      cache_read_tokens: (map(.cacheRead // 0) | add // 0), cache_write_tokens: (map(.cacheWrite // 0) | add // 0),
      cost_usd: (map(.cost.total // 0) | add // 0)}' 2>/dev/null || echo '{}'
}
before="$(session_usage)"

args=(-p --session-dir "$sessions")
[[ -n "${HARNESS_MODEL:-}" ]] && args+=(--model "$HARNESS_MODEL")
[[ "$cont" == 1 ]] && args+=(--continue)

set +e
pi "${args[@]}" -- "$(cat "$prompt")" </dev/null 2>&1 | tee "$log"
status="${PIPESTATUS[0]}"
set -e

cp "$log" "$HARNESS_OUT/last-message.md"
# --continue appends to the same session, so this call's usage is the difference.
jq -cn --argjson a "$before" --argjson b "$(session_usage)" \
  '$b | with_entries(.value -= ($a[.key] // 0))' >"$HARNESS_OUT/usage.json" 2>/dev/null || true
exit "$status"
