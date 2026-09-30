#!/usr/bin/env bash
# Turns an agent CLI's JSON event stream into a readable trace on stdout (the Actions log)
# and, when configured, streams its reasoning and tool calls to the Discord bot, which
# keeps one live message per run in the feature's thread.
#
# Usage: <agent cli> | tee LOG | harness/progress.sh claude|codex|pi
#
# Env (optional; streaming is off unless the first three are set):
#   AGENT_PROGRESS_URL         the bot's endpoint (https://…/bot/progress)
#   AGENT_PROGRESS_ID          the run's request_id (bot-<run>)
#   AGENT_PROGRESS_TOKEN_FILE  the run's token: hex HMAC-SHA256 of "agent-progress:<id>"
#                              keyed with the AGENT_PROGRESS_SECRET the bot also holds
#   AGENT_PROGRESS_INTERVAL    seconds between posts (default 4)
#   HARNESS_MODEL, HARNESS_ATTEMPT, HARNESS_ATTEMPTS  shown in Discord
#
# Only reasoning, tool calls, notes and errors are sent, never the agent's replies.
# Environment secrets, login files and common token shapes are redacted first. This
# never fails and always reads its input to the end, so it can't stop the agent; a bot
# that refuses updates or fails three times in a row turns streaming off for the call.
set -uo pipefail

agent="${1:-}"
interval="${AGENT_PROGRESS_INTERVAL:-4}"
[[ "$interval" =~ ^[0-9]+$ ]] || interval=4
warn() { printf '[harness] progress: %s\n' "$*" >&2; }

# Shared definitions, then one filter per CLI. Each emits {k, t} events:
#   reasoning, tool, note, error (streamed) and text, result (trace only).
common='
def clip($n): if length > $n then .[0:$n] + "…" else . end;
def detail: if type == "object"
  then (.command // .cmd // .file_path // .path // .pattern // .query // .url // .description // .prompt // .code // "")
  else . end | if type == "string" then . else tojson end;
def tool($name; $args): ($args | detail | gsub("\\s+"; " ") | ltrimstr(" ") | clip(200)) as $d |
  if $d == "" then $name else "\($name) \($d)" end;
def redact($secrets): reduce $secrets[] as $s (.; split($s) | join("[redacted]")) |
  gsub("sk-[A-Za-z0-9_-]{16,}"; "[redacted]") |
  gsub("gh[pousr]_[A-Za-z0-9]{20,}"; "[redacted]") |
  gsub("eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]+"; "[redacted]");
'
case "$agent" in
  pi) filter='
    if .type == "message_update" then .assistantMessageEvent |
      if .type == "thinking_end" then {k: "reasoning", t: .content}
      elif .type == "text_end" then {k: "text", t: .content}
      else empty end
    elif .type == "tool_execution_start" then {k: "tool", t: tool(.toolName; .args)}
    elif .type == "auto_retry_start" then {k: "note", t: "retrying after: \(.errorMessage)"}
    elif .type == "compaction_start" then {k: "note", t: "compacting the context"}
    elif .type == "message_end" and .message.role == "assistant" and .message.stopReason == "error"
      then {k: "error", t: (.message.errorMessage // "model error")}
    else empty end' ;;
  claude) filter='
    if .type == "assistant" then .message.content[]? |
      if .type == "thinking" then {k: "reasoning", t: .thinking}
      elif .type == "text" then {k: "text", t: .text}
      elif .type == "tool_use" then {k: "tool", t: tool(.name; .input)}
      else empty end
    elif .type == "result" then {k: "result", t: "\(.subtype) turns=\(.num_turns) cost=$\(.total_cost_usd // 0)"}
    else empty end' ;;
  codex) filter='
    if .type == "item.started" then .item |
      if .type == "command_execution" then {k: "tool", t: tool("bash"; .command)}
      elif .type == "mcp_tool_call" then {k: "tool", t: tool("\(.server)/\(.tool)"; .arguments)}
      elif .type == "web_search" then {k: "tool", t: tool("web_search"; .query)}
      else empty end
    elif .type == "item.completed" then .item |
      if .type == "reasoning" then {k: "reasoning", t: .text}
      elif .type == "agent_message" then {k: "text", t: .text}
      elif .type == "file_change" then {k: "tool", t: tool("edit"; [.changes[]?.path] | join(", "))}
      elif .type == "error" then {k: "error", t: .message}
      else empty end
    elif .type == "turn.failed" then {k: "error", t: .error.message}
    elif .type == "error" then {k: "error", t: .message}
    else empty end' ;;
  *)
    warn "unknown agent '$agent'"
    cat >/dev/null
    exit 0
    ;;
esac
program="$common"'
([$ENV | to_entries[] | select(.key | test("TOKEN|SECRET|KEY|PASSWORD|AUTH|CREDENTIAL")) | .value] + $extra
  | map(select(type == "string" and length >= 8)) | unique) as $secrets |
fromjson? // empty | select(type == "object") | ('"$filter"') |
select(.t | type == "string") | .k as $k |
.t |= (gsub("\r"; "") | redact($secrets) | clip(if $k == "text" then 4000 elif $k == "reasoning" then 2000 else 300 end)) |
select(.t | test("\\S"))'

# Login files the agent can read; every long string in them is a secret.
extra='[]'
for f in "${CODEX_HOME:-}/auth.json" "${PI_CODING_AGENT_DIR:-}/auth.json"; do
  [[ -f "$f" ]] || continue
  more="$(jq -c '[.. | strings | select(length >= 16)]' "$f" 2>/dev/null)" || continue
  extra="$(jq -cn --argjson a "$extra" --argjson b "$more" '$a + $b')" || extra='[]'
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
batch="$tmp/batch.jsonl"
: >"$batch"

stream=0
if [[ -n "${AGENT_PROGRESS_URL:-}" && -n "${AGENT_PROGRESS_ID:-}" && -s "${AGENT_PROGRESS_TOKEN_FILE:-}" ]]; then
  token="$(tr -d '[:space:]' <"$AGENT_PROGRESS_TOKEN_FILE")"
  # The token is a secret too, and goes to curl through a file rather than argv.
  extra="$(jq -cn --argjson a "$extra" --arg t "$token" '$a + [$t]')"
  printf 'Authorization: Bearer %s\n' "$token" >"$tmp/headers"
  unset token
  stream=1
fi

seq=0 failures=0
# post: sends the batched events (an empty batch still updates the live message) and
# empties the batch.
post() {
  local code
  if [[ "$stream" != 1 ]]; then
    : >"$batch"
    return 0
  fi
  seq=$((seq + 1))
  if ! jq -cs --arg id "$AGENT_PROGRESS_ID" --arg agent "$agent" --arg model "${HARNESS_MODEL:-}" \
    --arg attempt "${HARNESS_ATTEMPT:-1}" --arg attempts "${HARNESS_ATTEMPTS:-1}" --argjson seq "$seq" '
    {request_id: $id, agent: $agent, model: $model, seq: $seq,
     attempt: ($attempt | tonumber? // 1), attempts: ($attempts | tonumber? // 1),
     events: map(select(.k == "reasoning" or .k == "tool" or .k == "note" or .k == "error") | {kind: .k, text: .t})}' \
    "$batch" >"$tmp/body.json" 2>/dev/null; then
    : >"$batch"
    return 0
  fi
  : >"$batch"
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 -X POST -H @"$tmp/headers" \
    -H 'Content-Type: application/json' --data-binary @"$tmp/body.json" "$AGENT_PROGRESS_URL" 2>/dev/null)" || true
  case "$code" in
    2??) failures=0 ;;
    401 | 403 | 404 | 410)
      stream=0
      warn "the bot refused updates (HTTP $code); not streaming"
      ;;
    *)
      failures=$((failures + 1))
      if [[ "$failures" -ge 3 ]]; then
        stream=0
        warn "the bot is unreachable (HTTP ${code:-000}); not streaming"
      fi
      ;;
  esac
}

# handle LINE: prints one event to the trace and batches it for the bot.
handle() {
  jq -rj '
    if .k == "reasoning" then "💭 " + .t + "\n"
    elif .k == "text" then .t + "\n"
    elif .k == "tool" then "  > " + .t + "\n"
    elif .k == "result" then "\n[result] " + .t + "\n"
    else "[" + .k + "] " + .t + "\n" end' <<<"$1" 2>/dev/null || true
  [[ "$stream" == 1 ]] || return 0
  case "$1" in
    '{"k":"text"'* | '{"k":"result"'*) ;; # the agent's replies stay out of Discord
    *) printf '%s\n' "$1" >>"$batch" ;;
  esac
}

forward() {
  local line partial="" last=$SECONDS rc wait=""
  # Bash 4+ reports a read timeout as >128, so a quiet agent still gets its last events
  # sent. Bash 3.2 (macOS) can't tell a timeout from EOF: there, send as events arrive.
  [[ "${BASH_VERSINFO[0]}" -ge 4 ]] && wait=1
  post # opens the live message before the first event
  while :; do
    if IFS= read -r ${wait:+-t "$wait"} line; then
      handle "$partial$line"
      partial=""
    else
      rc=$?
      if [[ -n "$wait" && "$rc" -gt 128 ]]; then
        partial="$partial$line" # timed out, possibly mid-line
      else
        [[ -n "$partial$line" ]] && handle "$partial$line"
        break
      fi
    fi
    if [[ -s "$batch" && $((SECONDS - last)) -ge "$interval" ]]; then
      post
      last=$SECONDS
    fi
  done
  [[ -s "$batch" ]] && post
  return 0
}

{
  jq -R -c --unbuffered --argjson extra "$extra" "$program" 2>/dev/null || warn "could not parse the event stream"
  cat >/dev/null
} | {
  forward
  cat >/dev/null
}
exit 0
