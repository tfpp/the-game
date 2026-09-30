#!/usr/bin/env bash
# Tests for harness/gate.sh against canned GitHub events and a fake `gh`.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
gate="$here/../gate.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

# Fake gh: answers the API calls gate.sh makes from files in $work/api, logs comments.
mkdir -p "$work/bin" "$work/api"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == api ]] || exit 1
shift
path="" jq_filter="" body=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jq) jq_filter="$2"; shift ;;
    -f) body="$2"; shift ;;
    -X) shift ;;
    *) path="$1" ;;
  esac
  shift
done
if [[ -n "$body" ]]; then printf '%s\n' "${body#body=}" >>"$FAKE_DIR/comments"; exit 0; fi
file="$FAKE_DIR/api/$(printf '%s' "$path" | tr '/' '_')"
[[ -f "$file" ]] || { echo '{"message":"Not Found"}'; exit 1; }
if [[ -n "$jq_filter" ]]; then jq -r "$jq_filter" "$file"; else cat "$file"; fi
EOF
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" FAKE_DIR="$work" GITHUB_REPOSITORY=o/r RUN_URL=https://run

api() { printf '%s' "$2" >"$work/api/$(printf '%s' "$1" | tr '/' '_')"; }
api repos/o/r/collaborators/alice/permission '{"permission":"write"}'
api repos/o/r/collaborators/mallory/permission '{"permission":"triage"}'
api repos/o/r/issues/5 '{"number":5,"title":"Add Jump Pads!","state":"open"}'
api repos/o/r/git/matching-refs/heads/agent/5- '[]'
api repos/o/r/issues/6 '{"number":6,"title":"Old","state":"open"}'
api repos/o/r/git/matching-refs/heads/agent/6- '[{"ref":"refs/heads/agent/6-old"}]'
api repos/o/r/pulls/9 '{"state":"open","head":{"ref":"agent/5-add-jump-pads","repo":{"full_name":"o/r"}}}'
api repos/o/r/pulls/10 '{"state":"open","head":{"ref":"feature/x","repo":{"full_name":"o/r"}}}'

# gate EVENT_NAME PAYLOAD_JSON -> runs gate.sh, leaves outputs in $work/out
gate() {
  printf '%s' "$2" >"$work/event.json"
  : >"$work/out"
  : >"$work/comments"
  GITHUB_EVENT_NAME="$1" GITHUB_EVENT_PATH="$work/event.json" GITHUB_OUTPUT="$work/out" \
    "$gate" 2>"$work/gate.log" || { echo "  FAIL: gate.sh exited $?"; failures=$((failures + 1)); }
}
out() { sed -n "s/^$1=//p" "$work/out"; }
instructions() { sed -n '/^instructions<</,/^EOF_/p' "$work/out" | sed '1d;$d'; }
expect() {
  local got="$1" want="$2" what="$3"
  [[ "$got" == "$want" ]] || {
    echo "  FAIL: $what: expected '$want', got '$got'"
    failures=$((failures + 1))
  }
}
alice='"sender":{"login":"alice","type":"User"}'

echo "- label on an issue starts implement"
gate issues "{$alice,\"label\":{\"name\":\"agent\"},\"issue\":{\"number\":5}}"
expect "$(out ok)" true ok
expect "$(out mode)" implement mode
expect "$(out branch)" agent/5-add-jump-pads branch
expect "$(out target)" 5 target
expect "$(out agent)" pi "labels use the default harness"
grep -q "Starting" "$work/comments" || expect "no comment" "started comment" comment

echo "- other labels and untrusted senders are ignored"
gate issues "{$alice,\"label\":{\"name\":\"bug\"},\"issue\":{\"number\":5}}"
expect "$(out ok)" false "other label"
gate issues '{"sender":{"login":"mallory","type":"User"},"label":{"name":"agent"},"issue":{"number":5}}'
expect "$(out ok)" false "triage user"
gate issues '{"sender":{"login":"evil[bot]","type":"Bot"},"label":{"name":"agent"},"issue":{"number":5}}'
expect "$(out ok)" false "untrusted bot"
AGENT_TRUSTED_BOTS="x[bot],evil[bot]" gate issues '{"sender":{"login":"evil[bot]","type":"Bot"},"label":{"name":"agent"},"issue":{"number":5}}'
expect "$(out ok)" true "trusted bot"

echo "- an issue that already has an agent branch is refused with a comment"
gate issues "{$alice,\"label\":{\"name\":\"agent\"},\"issue\":{\"number\":6}}"
expect "$(out ok)" false ok
grep -q "agent/6-old" "$work/comments" || expect "no comment" "refusal comment" comment

echo "- /agent comments on PRs revise, with instructions"
gate issue_comment "{$alice,\"issue\":{\"number\":9,\"pull_request\":{\"url\":\"u\"}},\"comment\":{\"body\":\"/agent make it\\r\\nbouncier\"}}"
expect "$(out mode)" revise mode
expect "$(out issue)" 5 issue
expect "$(out pr)" 9 pr
expect "$(out branch)" agent/5-add-jump-pads branch
expect "$(instructions | tr '\n' '|')" "make it|bouncier|" instructions

echo "- /agent resolve-conflicts"
gate issue_comment "{$alice,\"issue\":{\"number\":9,\"pull_request\":{\"url\":\"u\"}},\"comment\":{\"body\":\"/agent resolve-conflicts\"}}"
expect "$(out mode)" resolve-conflicts mode

echo "- /agent on an issue implements; other comments and non-agent PRs are refused"
gate issue_comment "{$alice,\"issue\":{\"number\":5},\"comment\":{\"body\":\"/agent use red\"}}"
expect "$(out mode)" implement mode
expect "$(instructions)" "use red" instructions
gate issue_comment "{$alice,\"issue\":{\"number\":9,\"pull_request\":{\"url\":\"u\"}},\"comment\":{\"body\":\"/agentx\"}}"
expect "$(out ok)" false "not a command"
gate pull_request_target "{$alice,\"label\":{\"name\":\"agent\"},\"pull_request\":{\"number\":10}}"
expect "$(out ok)" false "non-agent branch"

echo "- workflow_dispatch"
gate workflow_dispatch "{$alice,\"inputs\":{\"number\":\"9\",\"mode\":\"revise\",\"agent\":\"claude\",\"instructions\":\"hi\"}}"
expect "$(out mode)" revise mode
expect "$(instructions)" hi instructions
expect "$(out agent)" claude agent
gate workflow_dispatch "{$alice,\"inputs\":{\"number\":\"9\",\"mode\":\"revise\"}}"
expect "$(out agent)" pi "dispatch without an agent"

echo "- Codex dispatch supports each mode"
for mode in implement revise resolve-conflicts; do
  number=9
  [[ "$mode" == implement ]] && number=5
  gate workflow_dispatch "{$alice,\"inputs\":{\"number\":\"$number\",\"mode\":\"$mode\",\"agent\":\"codex\"}}"
  expect "$(out ok)" true ok
  expect "$(out agent)" codex agent
  expect "$(out mode)" "$mode" mode
done

if [[ "$failures" -gt 0 ]]; then
  echo "gate tests: $failures failure(s)"
  exit 1
fi
echo "gate tests passed"
