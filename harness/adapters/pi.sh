#!/usr/bin/env bash
# pi adapter. Usage: pi.sh PROMPT_FILE LOG_FILE CONTINUE(0|1)
# Env: HARNESS_OUT (required), HARNESS_MODEL (openai-codex/gpt-6.1-sol),
# HARNESS_REASONING_EFFORT (pi's --thinking level; run.sh picks it per model).
# Auth and extensions come from PI_CODING_AGENT_DIR (~/.pi/agent); on Actions,
# harness/pi-setup.sh prepares it.
# Writes the call's token usage to $HARNESS_OUT/usage.json (see run.sh).
# pi runs in JSON mode: its event stream goes to LOG_FILE (stderr to agent-N.stderr.log),
# and harness/progress.sh prints the trace and streams progress to Discord when configured.
set -euo pipefail
prompt="$1" log="$2" cont="$3"
progress="$(cd "$(dirname "$0")/.." && pwd)/progress.sh"
errlog="${log%.log}.stderr.log"
model="${HARNESS_MODEL:-openai-codex/gpt-6.1-sol}"

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

# --no-approve: never load project-local .pi resources, which the agent itself could write.
args=(--mode json --no-approve --session-dir "$sessions" --model "$model")
args+=(--thinking "${HARNESS_REASONING_EFFORT:-medium}")
[[ "$cont" == 1 ]] && args+=(--continue)

set +e
pi "${args[@]}" -- "$(cat "$prompt")" </dev/null 2>"$errlog" | tee "$log" | "$progress" pi
status="${PIPESTATUS[0]}"
set -e
cat "$errlog" >&2 2>/dev/null || true

# JSON mode exits 0 even when the model call failed (-p exits 1), so judge the last
# assistant message: it must exist and must not have ended in an error or abort.
final="$(jq -cs '[.[] | select(.type? == "message_end" and .message.role? == "assistant") | .message] | last // null' \
  "$log" 2>/dev/null)" || final=null
[[ -n "$final" ]] || final=null
if [[ "$status" == 0 ]] && ! jq -e '. != null and (.stopReason | IN("error", "aborted") | not)' <<<"$final" >/dev/null; then
  status=1
fi
{
  jq -r 'if . == null then empty else
    ([.content[]? | select(.type == "text") | .text] | join("")) as $t |
    if $t != "" then $t else (.errorMessage // empty) end end' <<<"$final" 2>/dev/null || true
  [[ "$status" == 0 ]] || tail -n 20 "$errlog" 2>/dev/null || true
} >"$HARNESS_OUT/last-message.md"
# --continue appends to the same session, so this call's usage is the difference.
jq -cn --argjson a "$before" --argjson b "$(session_usage)" --arg model "$model" \
  '$b | with_entries(.value -= ($a[.key] // 0)) + {models: [$model], cost_basis: "adapter-reported"}' \
  >"$HARNESS_OUT/usage.json" 2>/dev/null || true
exit "$status"
