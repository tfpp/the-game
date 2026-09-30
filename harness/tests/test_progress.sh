#!/usr/bin/env bash
# Tests for harness/progress.sh: the trace, what reaches the bot, redaction and failure
# handling. curl is a fake that records each request body and answers with $FAKE_CODE.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
progress="$(cd "$here/.." && pwd)/progress.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  echo "  FAIL: $*"
  failures=$((failures + 1))
}
expect_eq() { [[ "$1" == "$2" ]] || fail "$3: expected '$2', got '$1'"; }

mkdir -p "$work/bin"
cat >"$work/bin/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    @*body.json) cat "\${a#@}" >>"$work/posts" ;;
    @*headers) cat "\${a#@}" >>"$work/headers" ;;
  esac
done
printf '%s' "\${FAKE_CODE:-204}"
EOF
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH"
unset AGENT_PROGRESS_URL AGENT_PROGRESS_ID AGENT_PROGRESS_TOKEN_FILE HARNESS_ATTEMPT HARNESS_ATTEMPTS FAKE_CODE
unset CODEX_HOME PI_CODING_AGENT_DIR
printf 'run-token-0123456789\n' >"$work/token"

run() { # run AGENT < events: streams to the fake bot, prints the trace
  rm -f "$work/posts" "$work/headers"
  AGENT_PROGRESS_URL=https://bot.example/bot/progress AGENT_PROGRESS_ID=bot-7 \
    AGENT_PROGRESS_TOKEN_FILE="$work/token" AGENT_PROGRESS_INTERVAL=0 \
    HARNESS_MODEL=openai-codex/gpt-6.1-sol HARNESS_ATTEMPT=2 HARNESS_ATTEMPTS=3 "$progress" "$1"
}
events() { jq -c '.events[]' "$work/posts" 2>/dev/null; } # every streamed event

echo "- pi: reasoning and tool calls are streamed, replies only traced"
trace="$(run pi <<'EOF'
{"type":"session","version":3}
not json at all
{"type":"message_update","assistantMessageEvent":{"type":"thinking_delta","delta":"partial"}}
{"type":"message_update","assistantMessageEvent":{"type":"thinking_end","content":"**Planning**\n\nLook at the movement feature."}}
{"type":"tool_execution_start","toolCallId":"c1","toolName":"bash","args":{"command":"rg --files\n  game/features"}}
{"type":"message_update","assistantMessageEvent":{"type":"text_end","content":"Done."}}
{"type":"message_end","message":{"role":"assistant","stopReason":"error","errorMessage":"429 overloaded"}}
EOF
)"
expect_eq "$trace" "💭 **Planning**

Look at the movement feature.
  > bash rg --files game/features
Done.
[error] 429 overloaded" "pi trace"
expect_eq "$(head -1 "$work/posts" | jq -c .)" \
  '{"request_id":"bot-7","agent":"pi","model":"openai-codex/gpt-6.1-sol","seq":1,"attempt":2,"attempts":3,"events":[]}' \
  "first post opens the live message"
expect_eq "$(events | jq -r .kind | tr '\n' ' ')" "reasoning tool error " "pi streamed kinds"
expect_eq "$(sort -u "$work/headers")" "Authorization: Bearer run-token-0123456789" "bearer token from the file"

echo "- claude: thinking blocks and tool_use"
run claude >/dev/null <<'EOF'
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"Check the tests first."},{"type":"thinking","thinking":""},{"type":"tool_use","name":"Read","input":{"file_path":"game/project.godot"}},{"type":"text","text":"hi"}]}}
{"type":"result","subtype":"success","num_turns":1,"total_cost_usd":0.5}
EOF
expect_eq "$(events | jq -c . | tr '\n' ' ')" \
  '{"kind":"reasoning","text":"Check the tests first."} {"kind":"tool","text":"Read game/project.godot"} ' "claude events"

echo "- codex: reasoning items, commands, file changes, MCP calls"
run codex >/dev/null <<'EOF'
{"type":"thread.started","thread_id":"t1"}
{"type":"item.completed","item":{"id":"0","type":"reasoning","text":"**Reading the harness**"}}
{"type":"item.started","item":{"id":"1","type":"command_execution","command":"/bin/bash -lc 'ls -la'","status":"in_progress"}}
{"type":"item.completed","item":{"id":"1","type":"command_execution","command":"/bin/bash -lc 'ls -la'","status":"completed"}}
{"type":"item.completed","item":{"id":"2","type":"file_change","changes":[{"path":"a.gd","kind":"add"},{"path":"b.gd","kind":"update"}],"status":"completed"}}
{"type":"item.started","item":{"id":"3","type":"mcp_tool_call","server":"godot","tool":"run_project","arguments":{},"status":"in_progress"}}
{"type":"item.completed","item":{"id":"4","type":"agent_message","text":"All done"}}
{"type":"turn.failed","error":{"message":"stream disconnected"}}
EOF
expect_eq "$(events | jq -c . | tr '\n' ' ')" \
  '{"kind":"reasoning","text":"**Reading the harness**"} {"kind":"tool","text":"bash /bin/bash -lc '"'ls -la'"'"} {"kind":"tool","text":"edit a.gd, b.gd"} {"kind":"tool","text":"godot/run_project"} {"kind":"error","text":"stream disconnected"} ' \
  "codex events"

echo "- secrets are redacted: environment, login files, the run token, token shapes"
mkdir -p "$work/codex-home"
echo '{"tokens":{"refresh_token":"rt_login-file-secret-value"}}' >"$work/codex-home/auth.json"
CODEX_HOME="$work/codex-home" OPENROUTER_API_KEY=sk-or-env-secret-value run pi >/dev/null <<'EOF'
{"type":"tool_execution_start","toolName":"bash","args":{"command":"echo sk-or-env-secret-value rt_login-file-secret-value run-token-0123456789"}}
{"type":"tool_execution_start","toolName":"bash","args":{"command":"echo sk-ant-oat01-abcdefghijklmnop ghp_abcdefghijklmnopqrstuvwxyz eyJhbGciOiJIUzI1.eyJzdWIiOiIxMjM0.c2lnbmF0dXJl"}}
EOF
expect_eq "$(events | jq -r .text | tr '\n' '|')" \
  "bash echo [redacted] [redacted] [redacted]|bash echo [redacted] [redacted] [redacted]|" "redaction"

echo "- long entries are clipped"
long="$(printf 'x%.0s' {1..3000})"
jq -cn --arg t "$long" '{type:"message_update",assistantMessageEvent:{type:"thinking_end",content:$t}}' |
  run pi >/dev/null
expect_eq "$(events | jq -r '.text | length')" 2001 "reasoning clipped to 2000 characters and an ellipsis"

echo "- without configuration: trace only, no requests"
rm -f "$work/posts"
trace="$("$progress" pi <<<'{"type":"tool_execution_start","toolName":"read","args":{"path":"a"}}')"
expect_eq "$trace" "  > read a" "trace without streaming"
[[ ! -e "$work/posts" ]] || fail "posted without configuration"

echo "- a refusing bot stops the stream at once; an unreachable one after three tries"
lines() { for i in 1 2 3 4 5 6; do echo "{\"type\":\"tool_execution_start\",\"toolName\":\"t$i\",\"args\":{}}"; done; }
lines | FAKE_CODE=410 run pi >/dev/null 2>"$work/err"
expect_eq "$(grep -c . "$work/posts")" 1 "posts after a 410"
grep -q 'refused updates (HTTP 410)' "$work/err" || fail "410 not reported"
lines | FAKE_CODE=502 run pi >/dev/null 2>"$work/err"
expect_eq "$(grep -c . "$work/posts")" 3 "posts to an unreachable bot"
grep -q 'unreachable (HTTP 502)' "$work/err" || fail "outage not reported"

# Bash 3.2 can't tell a read timeout from EOF, so progress.sh only sends on arrival there.
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
  echo "- a quiet agent's last events go out without waiting for more"
  rm -f "$work/posts" "$work/early"
  {
    echo '{"type":"tool_execution_start","toolName":"verify","args":{}}'
    sleep 4
    grep -q '"verify"' "$work/posts" 2>/dev/null && touch "$work/early"
  } | AGENT_PROGRESS_URL=https://bot.example/bot/progress AGENT_PROGRESS_ID=bot-7 \
    AGENT_PROGRESS_TOKEN_FILE="$work/token" AGENT_PROGRESS_INTERVAL=1 "$progress" pi >/dev/null
  [[ -e "$work/early" ]] || fail "events waited for the end of the stream"
fi

echo "- always drains its input and exits 0"
set +e
{ seq 1 20000 | sed 's/.*/{"type":"x"}/'; } | "$progress" pi >/dev/null
expect_eq "${PIPESTATUS[1]}" 0 "exit status on a long stream"
yes | head -c 200000 | "$progress" bogus 2>/dev/null
expect_eq "${PIPESTATUS[2]}" 0 "exit status for an unknown agent"
set -e

if [[ "$failures" -gt 0 ]]; then
  echo "progress tests: $failures failure(s)"
  exit 1
fi
echo "progress tests passed"
