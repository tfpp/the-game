#!/usr/bin/env bash
# Tests for harness/publish.sh: produces real run.sh output with a fake agent, then
# publishes it from a separate clone to a local bare "origin" with a fake `gh`.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
failures=0 n=0

mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "pr create" ]]; then
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) printf '%s\n' "$2" >"$FAKE_DIR/pr-title" ;;
      --body-file) cp "$2" "$FAKE_DIR/pr-body" ;;
      --head) printf '%s\n' "$2" >"$FAKE_DIR/pr-head" ;;
    esac
    shift 2
  done
  echo "https://github.com/o/r/pull/99"
  exit 0
fi
[[ "$1" == api ]] || exit 1
shift
case "$*" in
  "-X DELETE "*labels*) echo unlabeled >>"$FAKE_DIR/labels" ;;
  *"/comments -F body=@"*)
    last="${*: -1}"
    { cat "${last#body=@}"; echo "----"; } >>"$FAKE_DIR/comments"
    ;;
  "repos/o/r/issues/5")
    [[ -n "${FAKE_ISSUE:-}" ]] && echo "$FAKE_ISSUE" && exit 0
    echo '{"title":"Jump pads","body":"Make\r\npads","user":{"login":"alice","type":"User"}}'
    ;;
  *) echo "unexpected gh api $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" FAKE_DIR="$work" GITHUB_REPOSITORY=o/r RUN_URL=https://run GH_TOKEN=t

fail() {
  echo "  FAIL: $*"
  failures=$((failures + 1))
}

# scenario AGENT_SCRIPT: fresh origin, an agent run in one clone, a publisher clone.
scenario() {
  n=$((n + 1))
  local seed="$work/seed$n"
  origin="$work/origin$n.git" agent_repo="$work/agent$n" pub="$work/pub$n" out="$work/out$n"
  git init -q --bare -b main "$origin"
  git init -q -b main "$seed"
  mkdir -p "$seed/.github/workflows" "$seed/game"
  cp -R "$src/harness" "$seed/harness"
  cp "$src/.github/CODEOWNERS" "$seed/.github/"
  echo "on: push" >"$seed/.github/workflows/ci.yml"
  echo "hello" >"$seed/game/greeting.txt"
  (cd "$seed" && git add -A && git commit -qm init && git remote add origin "$origin" && git push -q origin main)
  git clone -q "$origin" "$agent_repo"
  git clone -q "$origin" "$pub"
  mkdir -p "$work/adapters"
  printf '#!/usr/bin/env bash\nexec bash "%s/agent-script" "$@"\n' "$work" >"$work/adapters/fake.sh"
  chmod +x "$work/adapters/fake.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$work/verify" && chmod +x "$work/verify"
  cat >"$work/agent-script"
  echo 'source harness/tests/fixtures/complete-summary.sh' >>"$work/agent-script"
  echo task >"$work/task.md"
  HARNESS_ADAPTERS="$work/adapters" HARNESS_VERIFY="$work/verify" "$agent_repo/harness/run.sh" \
    --agent fake --mode implement --task "$work/task.md" --branch agent/5-jump-pads --out "$out" \
    >"$work/run.log" 2>&1 || true
  rm -f "$work"/{comments,labels,pr-title,pr-body,pr-head}
}

publish() {
  code=0
  OUT="$out" MODE="${PUBLISH_MODE:-implement}" AGENT=fake ISSUE=5 PR="${PUBLISH_PR:-}" BRANCH=agent/5-jump-pads TARGET=5 \
    AGENT_JOB_RESULT="${PUBLISH_JOB_RESULT:-success}" HARNESS_PUSH_URL="$origin" "$pub/harness/publish.sh" >"$work/publish.log" 2>&1 || code=$?
}

echo "- success: pushes the branch and opens a PR with the request quoted"
scenario <<'EOF'
echo '{"input_tokens":1200,"output_tokens":34000,"cache_read_tokens":1200000,"cache_write_tokens":0,"cost_usd":3.456}' >"$HARNESS_OUT/usage.json"
mkdir -p game/core/net && echo x >game/core/net/n.gd && echo pad >game/pad.txt
printf 'feat(game): add jump pads\n\n## Summary\nBoing.\n\n## Changes\n- **Pads**: new\n' >"$HARNESS_OUT/summary.md"
EOF
jq '.models = ["openai/gpt-5.4", "claude-sonnet-4-6"] | .reasoning_effort = "high"' "$out/result.json" >"$out/result.tmp"
mv "$out/result.tmp" "$out/result.json"
publish
[[ "$code" == 0 ]] || fail "exit $code: $(cat "$work/publish.log")"
[[ "$(git -C "$origin" rev-parse agent/5-jump-pads 2>/dev/null)" == "$(jq -r .head_sha "$out/result.json")" ]] ||
  fail "branch not pushed at the agent's head"
[[ "$(cat "$work/pr-title" 2>/dev/null)" == "feat(game): add jump pads" ]] || fail "PR title"
body="$(cat "$work/pr-body" 2>/dev/null)"
for want in "## Summary" "Boing." "Closes #5" "## Discord Request" "> **Jump pads**" "> pads" \
  "requested by @alice" "game/core/net/n.gd" "verify passed after 1 attempt(s)" \
  "## Agent Usage (this run)" "Model(s): claude-sonnet-4-6, openai/gpt-5.4" "Reasoning effort: high" \
  "Tokens used: 1235200" "Estimated cost (USD API-equivalent): \$3.46" "not subscription billing" \
  "Verified with base commit" "$(jq -r .base_sha "$out/result.json")"; do
  [[ "$body" == *"$want"* ]] || fail "PR body lacks '$want'"
done
grep -qFx "🤖 Opened https://github.com/o/r/pull/99 · Model(s): claude-sonnet-4-6, openai/gpt-5.4 · Reasoning: high · Tokens used: 1235200 · Estimated cost (USD API-equivalent): \$3.46" "$work/comments" ||
  fail "no PR link comment with usage on the issue: $(cat "$work/comments")"
grep -q unlabeled "$work/labels" || fail "label not removed"

echo "- revise first line includes PR URL and this run metadata"
rm -f "$work/comments"
PUBLISH_MODE=revise PUBLISH_PR=99 publish
[[ "$code" == 0 ]] || fail "revise exit $code: $(cat "$work/publish.log")"
expected="🤖 Pushed $(jq -r .head_sha "$out/result.json") https://github.com/o/r/pull/99 · Model(s): claude-sonnet-4-6, openai/gpt-5.4 · Reasoning: high · Tokens used: 1235200 · Estimated cost (USD API-equivalent): \$3.46"
[[ "$(head -n 1 "$work/comments")" == "$expected" ]] || fail "revise first line metadata"

echo "- missing, invalid, and zero-attempt telemetry are explicit"
for mutation in \
  'del(.models, .usage, .attempts, .reasoning_effort)' \
  '.attempts=1 | .models=["bad\nmodel", "trailing\n", "[injected](url)", 7, ("x" * 121)] | .usage={input_tokens:-1,output_tokens:1e16,cache_read_tokens:0,cache_write_tokens:0,cost_usd:-1} | .reasoning_effort="[x](y)"' \
  '.attempts=1 | .models="not-an-array" | .usage={cost_usd:"$9"} | .reasoning_effort=7' \
  '.attempts=1 | .models=[] | .usage={cost_usd:1e6} | .reasoning_effort="HIGH"' \
  '.attempts=0 | del(.models, .usage)'; do
  jq "$mutation | .cost_basis=[\"INJECTED_MARKDOWN\"]" "$out/result.json" >"$out/result.tmp"
  mv "$out/result.tmp" "$out/result.json"
  rm -f "$work/comments"
  publish
  [[ "$code" == 0 ]] || fail "telemetry case exit $code"
  expected='Model(s): unavailable · Reasoning: unavailable · Tokens used: unavailable · Estimated cost (USD API-equivalent): unavailable'
  if [[ "$mutation" == '.attempts=0'* ]]; then
    expected='Model(s): none (no agent run) · Reasoning: none · Tokens used: 0 · Estimated cost (USD API-equivalent): $0.00'
  fi
  [[ "$(head -n 1 "$work/comments")" == "🤖 Opened https://github.com/o/r/pull/99 · $expected" ]] || fail "telemetry first line: $(head -n 1 "$work/comments")"
  grep -qF '## Agent Usage (this run)' "$work/pr-body" || fail "missing usage section"
  grep -qF 'INJECTED_MARKDOWN' "$work/pr-body" && fail "untrusted cost basis rendered"
  grep -qF '[injected]' "$work/pr-body" && fail "untrusted model rendered"
  grep -qF '[x](y)' "$work/pr-body" && fail "untrusted reasoning effort rendered"
done

echo "- model output is bounded to eight safe IDs"
jq '.attempts=1 | .models=([range(0; 12) | "model-\(.)"] + ["unsafe!"])' "$out/result.json" >"$out/result.tmp"
mv "$out/result.tmp" "$out/result.json"
publish
[[ "$code" == 0 ]] || fail "bounded model case exit $code"
grep -qF 'Model(s): model-0, model-1, model-2, model-3, model-4, model-5, model-6, model-7' "$work/pr-body" || fail "safe bounded models missing"
grep -qF 'model-8' "$work/pr-body" && fail "too many models rendered"

echo "- a moving base is disclosed instead of claiming validation against latest main"
scenario <<<'echo pad >game/pad.txt'
(cd "$work/seed$n" && echo newer >game/newer.txt && git add -A && git commit -qm 'feat: newer base' && git push -q origin main)
git -C "$pub" fetch -q origin
publish
[[ "$code" == 0 ]] || fail "moved base publish: $(cat "$work/publish.log")"
grep -q 'base has moved' "$work/pr-body" || fail 'missing moving-base notice'

echo "- a bot-opened issue credits the Discord requester from its trailer"
scenario <<<'echo pad >game/pad.txt'
FAKE_ISSUE='{"title":"Jump pads","body":"Make pads\n\nRequested-by: Alice <discord:42>","user":{"login":"tfpp-bot[bot]","type":"Bot"}}' publish
[[ "$code" == 0 ]] || fail "exit $code: $(cat "$work/publish.log")"
body="$(cat "$work/pr-body" 2>/dev/null)"
[[ "$body" == *"requested by Alice on Discord"* ]] || fail "PR body lacks the Discord requester: $body"
[[ "$body" != *"Requested-by:"* && "$body" != *"discord:42"* ]] || fail "trailer leaked into the PR body"

echo "- failure: comments with the verify log and pushes nothing"
scenario <<'EOF'
echo x >game/x.txt
EOF
printf '#!/usr/bin/env bash\necho "gdlint: bad indent"; exit 1\n' >"$work/verify"
rm -rf "$out" && HARNESS_ADAPTERS="$work/adapters" HARNESS_VERIFY="$work/verify" \
  "$agent_repo/harness/run.sh" --agent fake --mode implement --task "$work/task.md" \
  --branch agent/5-jump-pads-2 --out "$out" --attempts 1 >"$work/run.log" 2>&1 || true
git -C "$agent_repo" switch -q main
publish
[[ "$code" == 1 ]] || fail "expected exit 1, got $code"
grep -q "gdlint: bad indent" "$work/comments" || fail "verify log not in comment"
git -C "$origin" rev-parse -q --verify agent/5-jump-pads >/dev/null && fail "failed run was pushed"

echo "- refuses changes to .github/workflows"
scenario <<'EOF'
echo "on: pull_request" >.github/workflows/ci.yml
printf 'ci: sneaky\n' >"$HARNESS_OUT/summary.md"
EOF
publish
[[ "$code" == 1 ]] || fail "expected exit 1, got $code"
grep -q "workflows" "$work/comments" || fail "no refusal comment"
git -C "$origin" rev-parse -q --verify agent/5-jump-pads >/dev/null && fail "workflow change was pushed"

echo "- a rejected push is reported with the reason"
scenario <<<'echo pad >game/pad.txt'
(cd "$work/seed$n" && git switch -qc agent/5-jump-pads && echo other >game/other.txt && git add -A &&
  git commit -qm other && git push -q origin agent/5-jump-pads)
publish
[[ "$code" == 1 ]] || fail "expected exit 1, got $code"
grep -q "Someone pushed to the branch" "$work/comments" || fail "no rejection reason: $(cat "$work/comments")"

echo "- no changes: the comment explicitly reports an unavailable cost"
scenario <<'EOF'
echo '{"input_tokens":"lots","output_tokens":999,"cache_read_tokens":-5,"cost_usd":null}' >"$HARNESS_OUT/usage.json"
printf 'no changes\n\nToo vague.\n' >"$HARNESS_OUT/summary.md"
EOF
publish
[[ "$code" == 0 ]] || fail "exit $code: $(cat "$work/publish.log")"
grep -qF 'Estimated cost (USD API-equivalent): unavailable' "$work/comments" ||
  fail "no-changes comment: $(cat "$work/comments")"

echo "- a missing artifact is reported"
scenario <<<'true'
out="$work/nothing" publish
[[ "$code" == 1 ]] || fail "expected exit 1, got $code"
grep -q "without a result" "$work/comments" || fail "no crash comment"

echo "- a cancelled agent job is named and lists no unavailable usage"
rm -f "$work/comments"
out="$work/nothing" PUBLISH_JOB_RESULT=cancelled publish
[[ "$code" == 1 ]] || fail "expected exit 1, got $code"
[[ "$(head -n 1 "$work/comments")" == '🤖 `fake` (`implement`) did not produce a change: the agent job was cancelled before it finished (stopped by hand or it hit its time limit) ([run](https://run))' ]] ||
  fail "cancelled comment: $(head -n 1 "$work/comments")"

if [[ "$failures" -gt 0 ]]; then
  echo "publish tests: $failures failure(s)"
  exit 1
fi
echo "publish tests passed"
