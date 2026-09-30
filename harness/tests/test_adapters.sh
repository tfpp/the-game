#!/usr/bin/env bash
# Tests for the adapters' usage.json: each CLI is a fake that prints output captured from
# the real one.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
adapters="$(cd "$here/../adapters" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

fail() {
  echo "  FAIL: $*"
  failures=$((failures + 1))
}
expect_eq() { [[ "$1" == "$2" ]] || fail "$3: expected '$2', got '$1'"; }

mkdir -p "$work/bin"
export PATH="$work/bin:$PATH" HARNESS_OUT="$work/out"
unset HARNESS_MODEL HARNESS_REASONING_EFFORT HARNESS_MAX_TURNS
fake() { # fake NAME: the script on stdin becomes the CLI NAME
  { echo '#!/usr/bin/env bash'; cat; } >"$work/bin/$1"
  chmod +x "$work/bin/$1"
}
call() { # call AGENT CONTINUE: runs the adapter, prints its usage.json
  rm -f "$HARNESS_OUT/usage.json"
  echo prompt >"$work/prompt.md"
  "$adapters/$1.sh" "$work/prompt.md" "$work/agent.log" "$2" >/dev/null 2>&1 || true
  if [[ -s "$HARNESS_OUT/usage.json" ]]; then jq -c 'del(.models, .cost_basis)' "$HARNESS_OUT/usage.json"; else echo missing; fi
}

echo "- claude: the result event's usage and cost"
mkdir -p "$HARNESS_OUT"
fake claude <<'EOF'
printf '%s\n' "$@" >"$HARNESS_OUT/args"
cat >/dev/null
echo '{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"hi"}]}}'
echo '{"type":"result","subtype":"success","num_turns":1,"result":"hi","total_cost_usd":0.0721836,"modelUsage":{"claude-opus-5-5":{},"claude-haiku-4-5":{}},"usage":{"input_tokens":2,"cache_creation_input_tokens":8759,"cache_read_input_tokens":10118,"output_tokens":4}}'
EOF
expect_eq "$(call claude 0)" \
  '{"input_tokens":2,"output_tokens":4,"cache_read_tokens":10118,"cache_write_tokens":8759,"cost_usd":0.0721836}' claude

expect_eq "$(jq -c .models "$HARNESS_OUT/usage.json")" '["claude-haiku-4-5","claude-opus-5-5"]' "Claude actual models including subagent"
expect_eq "$(grep -A1 '^--model$' "$HARNESS_OUT/args" | tail -1)" claude-opus-5-5 "claude default model"
expect_eq "$(grep -A1 '^--effort$' "$HARNESS_OUT/args" | tail -1)" low "claude default effort"
call claude 1 >/dev/null
expect_eq "$(grep -A1 '^--model$' "$HARNESS_OUT/args" | tail -1)" claude-opus-5-5 "claude resumed model"
expect_eq "$(grep -A1 '^--effort$' "$HARNESS_OUT/args" | tail -1)" low "claude resumed effort"
HARNESS_MODEL=claude-override HARNESS_REASONING_EFFORT=high call claude 1 >/dev/null
expect_eq "$(grep -A1 '^--model$' "$HARNESS_OUT/args" | tail -1)" claude-override "claude model override"
expect_eq "$(grep -A1 '^--effort$' "$HARNESS_OUT/args" | tail -1)" high "claude effort override"

echo "- claude: no result event, no usage"
fake claude <<<'cat >/dev/null; exit 1'
expect_eq "$(call claude 0)" missing "claude crash"

echo "- codex: cached input tokens are split out, estimated API-equivalent cost"
fake codex <<'EOF'
printf '%s\n' "$@" >"$HARNESS_OUT/args"
cat >/dev/null
echo '{"type":"thread.started","thread_id":"t1"}'
echo '{"type":"turn.completed","usage":{"input_tokens":15747,"cached_input_tokens":13056,"cache_write_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0}}'
EOF
expect_eq "$(call codex 0)" \
  '{"input_tokens":2691,"output_tokens":5,"cache_read_tokens":13056,"cache_write_tokens":0,"cost_usd":0.0067376}' codex

expect_eq "$(grep -A1 '^-m$' "$HARNESS_OUT/args" | tail -1)" gpt-6.1-sol "codex default model"
expect_eq "$(grep '^model_reasoning_effort=' "$HARNESS_OUT/args")" 'model_reasoning_effort="medium"' "codex default effort"
call codex 1 >/dev/null
expect_eq "$(head -2 "$HARNESS_OUT/args" | tr '\n' ' ')" 'exec resume ' "codex resume"
expect_eq "$(grep -A1 '^-m$' "$HARNESS_OUT/args" | tail -1)" gpt-6.1-sol "codex resumed model"
expect_eq "$(grep '^model_reasoning_effort=' "$HARNESS_OUT/args")" 'model_reasoning_effort="medium"' "codex resumed effort"
HARNESS_MODEL=codex-override HARNESS_REASONING_EFFORT=high call codex 1 >/dev/null
expect_eq "$(grep -A1 '^-m$' "$HARNESS_OUT/args" | tail -1)" codex-override "codex model override"
expect_eq "$(grep '^model_reasoning_effort=' "$HARNESS_OUT/args")" 'model_reasoning_effort="high"' "codex effort override"

echo "- pi: only the messages this call added to the session"
fake pi <<'EOF'
printf '%s\n' "$@" >"$HARNESS_OUT/args"
dir=""
while [[ $# -gt 0 ]]; do [[ "$1" == --session-dir ]] && dir="$2"; shift; done
mkdir -p "$dir"
echo '{"type":"message","message":{"role":"user"}}' >>"$dir/s.jsonl"
echo '{"type":"message","message":{"role":"assistant","usage":{"input":4,"output":4,"cacheRead":0,"cacheWrite":21902,"cost":{"total":0.175312}}}}' >>"$dir/s.jsonl"
echo 'Warning: an extension warning' >&2
echo '{"type":"session","version":3}'
echo '{"type":"tool_execution_start","toolName":"bash","args":{"command":"ls"}}'
echo '{"type":"message_end","message":{"role":"assistant","stopReason":"toolUse","content":[{"type":"text","text":"looking"}]}}'
echo '{"type":"message_end","message":{"role":"assistant","stopReason":"stop","content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"Summary "},{"type":"text","text":"written."}]}}'
echo '{"type":"agent_settled"}'
EOF
expect_eq "$(call pi 0)" \
  '{"input_tokens":4,"output_tokens":4,"cache_read_tokens":0,"cache_write_tokens":21902,"cost_usd":0.175312}' "pi first call"
expect_eq "$(call pi 1)" \
  '{"input_tokens":4,"output_tokens":4,"cache_read_tokens":0,"cache_write_tokens":21902,"cost_usd":0.175312}' "pi continued"
expect_eq "$(jq -c .models "$HARNESS_OUT/usage.json")" '["openai-codex/gpt-6.1-sol"]' "pi reported model"
expect_eq "$(grep -c '^--continue$' "$HARNESS_OUT/args")" 1 "pi continue"
expect_eq "$(grep -c '^--no-approve$' "$HARNESS_OUT/args")" 1 "pi ignores project-local resources"
expect_eq "$(grep -A1 '^--model$' "$HARNESS_OUT/args" | tail -1)" openai-codex/gpt-6.1-sol "pi default model"
expect_eq "$(grep -A1 '^--thinking$' "$HARNESS_OUT/args" | tail -1)" medium "pi default thinking"
HARNESS_MODEL=anthropic-omp/claude-opus-5-5 HARNESS_REASONING_EFFORT=high call pi 0 >/dev/null
expect_eq "$(grep -A1 '^--model$' "$HARNESS_OUT/args" | tail -1)" anthropic-omp/claude-opus-5-5 "pi model override"
expect_eq "$(grep -A1 '^--thinking$' "$HARNESS_OUT/args" | tail -1)" high "pi thinking override"

echo "- pi: JSON mode; the last reply becomes last-message.md, stderr its own log"
expect_eq "$(grep -c '^--mode$' "$HARNESS_OUT/args")" 1 "pi JSON mode"
expect_eq "$(grep -c '^-p$' "$HARNESS_OUT/args")" 0 "pi print mode is off"
set +e
"$adapters/pi.sh" "$work/prompt.md" "$work/agent-1.log" 0 >"$work/trace" 2>/dev/null
expect_eq "$?" 0 "pi success"
set -e
expect_eq "$(cat "$HARNESS_OUT/last-message.md")" "Summary written." "pi last message"
expect_eq "$(cat "$work/agent-1.stderr.log")" "Warning: an extension warning" "pi stderr log"
expect_eq "$(jq -r .type "$work/agent-1.log" | tr '\n' ' ')" "session tool_execution_start message_end message_end agent_settled " "pi event log"
grep -qx '  > bash ls' "$work/trace" || fail "pi trace"

echo "- pi: a failed model call fails the adapter, although pi exits 0"
fake pi <<'EOF'
echo '{"type":"message_end","message":{"role":"assistant","stopReason":"error","content":[],"errorMessage":"400 out of extra usage"}}'
EOF
set +e
"$adapters/pi.sh" "$work/prompt.md" "$work/agent-1.log" 0 >/dev/null 2>&1
expect_eq "$?" 1 "pi model error"
set -e
expect_eq "$(cat "$HARNESS_OUT/last-message.md")" "400 out of extra usage" "pi error message"
fake pi <<<'echo "fatal: unknown model" >&2'
set +e
"$adapters/pi.sh" "$work/prompt.md" "$work/agent-1.log" 0 >/dev/null 2>&1
expect_eq "$?" 1 "pi without any reply"
set -e
expect_eq "$(cat "$HARNESS_OUT/last-message.md")" "fatal: unknown model" "pi stderr when there is no reply"

echo "- every adapter streams through progress.sh"
cat >"$work/bin/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ "\$a" == @*body.json ]] && cat "\${a#@}" >>"$work/posts"; done
printf 204
EOF
chmod +x "$work/bin/curl"
echo token-0123456789 >"$work/token"
fake pi <<<'echo "{\"type\":\"tool_execution_start\",\"toolName\":\"read\",\"args\":{\"path\":\"a.gd\"}}"'
fake claude <<<'cat >/dev/null; echo "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"Read\",\"input\":{\"file_path\":\"a.gd\"}}]}}"'
fake codex <<<'cat >/dev/null; echo "{\"type\":\"item.started\",\"item\":{\"type\":\"command_execution\",\"command\":\"cat a.gd\"}}"'
for a in pi claude codex; do
  rm -f "$work/posts"
  AGENT_PROGRESS_URL=https://bot.example/bot/progress AGENT_PROGRESS_ID=bot-1 AGENT_PROGRESS_TOKEN_FILE="$work/token" \
    HARNESS_ATTEMPT=2 "$adapters/$a.sh" "$work/prompt.md" "$work/agent-1.log" 0 >/dev/null 2>&1 || true
  expect_eq "$(jq -sc '[.[] | .events[]] | length' "$work/posts" 2>/dev/null)" 1 "$a streamed tool call"
  expect_eq "$(jq -s '.[0].attempt' "$work/posts" 2>/dev/null)" 2 "$a attempt"
done

if [[ "$failures" -gt 0 ]]; then
  echo "adapter tests: $failures failure(s)"
  exit 1
fi
echo "adapter tests passed"
