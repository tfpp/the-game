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
fake() { # fake NAME: the script on stdin becomes the CLI NAME
  { echo '#!/usr/bin/env bash'; cat; } >"$work/bin/$1"
  chmod +x "$work/bin/$1"
}
call() { # call AGENT CONTINUE: runs the adapter, prints its usage.json
  rm -f "$HARNESS_OUT/usage.json"
  echo prompt >"$work/prompt.md"
  "$adapters/$1.sh" "$work/prompt.md" "$work/agent.log" "$2" >/dev/null 2>&1 || true
  if [[ -s "$HARNESS_OUT/usage.json" ]]; then jq -c . "$HARNESS_OUT/usage.json"; else echo missing; fi
}

echo "- claude: the result event's usage and cost"
mkdir -p "$HARNESS_OUT"
fake claude <<'EOF'
cat >/dev/null
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}'
echo '{"type":"result","subtype":"success","num_turns":1,"result":"hi","total_cost_usd":0.0721836,"usage":{"input_tokens":2,"cache_creation_input_tokens":8759,"cache_read_input_tokens":10118,"output_tokens":4}}'
EOF
expect_eq "$(call claude 0)" \
  '{"input_tokens":2,"output_tokens":4,"cache_read_tokens":10118,"cache_write_tokens":8759,"cost_usd":0.0721836}' claude

echo "- claude: no result event, no usage"
fake claude <<<'cat >/dev/null; exit 1'
expect_eq "$(call claude 0)" missing "claude crash"

echo "- codex: cached input tokens are split out, no cost"
fake codex <<'EOF'
cat >/dev/null
echo '{"type":"thread.started","thread_id":"t1"}'
echo '{"type":"turn.completed","usage":{"input_tokens":15747,"cached_input_tokens":13056,"cache_write_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0}}'
EOF
expect_eq "$(call codex 0)" \
  '{"input_tokens":2691,"output_tokens":5,"cache_read_tokens":13056,"cache_write_tokens":0,"cost_usd":null}' codex

echo "- pi: only the messages this call added to the session"
fake pi <<'EOF'
dir=""
while [[ $# -gt 0 ]]; do [[ "$1" == --session-dir ]] && dir="$2"; shift; done
mkdir -p "$dir"
echo '{"type":"message","message":{"role":"user"}}' >>"$dir/s.jsonl"
echo '{"type":"message","message":{"role":"assistant","usage":{"input":4,"output":4,"cacheRead":0,"cacheWrite":21902,"cost":{"total":0.175312}}}}' >>"$dir/s.jsonl"
echo hi
EOF
expect_eq "$(call pi 0)" \
  '{"input_tokens":4,"output_tokens":4,"cache_read_tokens":0,"cache_write_tokens":21902,"cost_usd":0.175312}' "pi first call"
expect_eq "$(call pi 1)" \
  '{"input_tokens":4,"output_tokens":4,"cache_read_tokens":0,"cache_write_tokens":21902,"cost_usd":0.175312}' "pi continued"

if [[ "$failures" -gt 0 ]]; then
  echo "adapter tests: $failures failure(s)"
  exit 1
fi
echo "adapter tests passed"
