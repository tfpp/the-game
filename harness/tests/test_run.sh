#!/usr/bin/env bash
# Tests for harness/run.sh and lib.sh. Each case runs run.sh in a throwaway repo (with a
# bare "origin") using a scripted fake agent and a fake verify, so no LLM or Godot is used.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
src="$(cd "$here/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
failures=0 n=0

fail() {
  echo "  FAIL: $*"
  failures=$((failures + 1))
}
expect_eq() { [[ "$1" == "$2" ]] || fail "$3: expected '$2', got '$1'"; }

# new_repo: a repo at $repo with harness/, CODEOWNERS and a game file, pushed to origin.
new_repo() {
  n=$((n + 1))
  repo="$work/repo$n" out="$work/out$n"
  git init -q --bare -b main "$work/origin$n.git"
  git init -q -b main "$repo"
  mkdir -p "$repo/.github" "$repo/game"
  cp -R "$src/harness" "$repo/harness"
  cp "$src/.github/CODEOWNERS" "$repo/.github/"
  echo "hello" >"$repo/game/greeting.txt"
  # Fake agent: runs $repo/agent-script with the adapter's arguments.
  mkdir -p "$work/adapters$n"
  printf '#!/usr/bin/env bash\nexec bash "%s/agent-script" "$@"\n' "$work" >"$work/adapters$n/fake.sh"
  chmod +x "$work/adapters$n/fake.sh"
  (cd "$repo" && git add -A && git commit -qm init && git remote add origin "$work/origin$n.git" &&
    git push -q origin main)
  export HARNESS_ADAPTERS="$work/adapters$n"
  export HARNESS_VERIFY="$work/verify"
  printf 'Add a thing\n' >"$work/task.md"
}

agent() {
  cat >"$work/agent-script"
  echo 'source harness/tests/fixtures/complete-summary.sh' >>"$work/agent-script"
}
verify() { printf '#!/usr/bin/env bash\ncd "$(git rev-parse --show-toplevel)"\n%s\n' "$1" >"$work/verify" && chmod +x "$work/verify"; }
run() {
  code=0
  "$repo/harness/run.sh" --agent fake --task "$work/task.md" --out "$out" "$@" >"$work/run.log" 2>&1 || code=$?
}
field() { jq -r ".$1" "$out/result.json"; }

case_() { printf '%s\n' "- $*"; }

case_ "lib: slugify, branch names and protected paths"
(
  source "$src/harness/lib.sh"
  expect_eq "$(slugify 'Add a Jump Pad!! & more')" "add-a-jump-pad-more" slugify
  expect_eq "$(branch_for_issue 7 '???')" "agent/7-feature" "empty slug"
  expect_eq "$(issue_from_branch agent/42-x)" "42" issue_from_branch
  issue_from_branch main >/dev/null && fail "main is not an agent branch"
  got="$(printf 'game/features/a.gd\ngame/core/net/n.gd\ngame/project.godot\n.github/x\n' | filter_protected | tr '\n' ' ')"
  expect_eq "$got" "game/core/net/n.gd game/project.godot .github/x " filter_protected
  valid_title "feat(game): add jump pads" || fail "valid title rejected"
  valid_title "Add jump pads" && fail "invalid title accepted"
  exit "$failures"
) || failures=$((failures + $?))

case_ "implement: agent commits, verify passes, bundle holds the commits"
new_repo
verify 'exit 0'
agent <<'EOF'
echo "jump" >game/jump.txt && git add -A && git commit -qm "feat(game): add jump"
printf 'feat(game): add jump pads\n\n## Summary\nJumps.\n' >"$HARNESS_OUT/summary.md"
EOF
run --mode implement --branch agent/1-add-a-thing
expect_eq "$code" 0 "exit code"
expect_eq "$(field status)" success status
expect_eq "$(field title)" "feat(game): add jump pads" title
expect_eq "$(field attempts)" 1 attempts
expect_eq "$(git -C "$repo" branch --show-current)" "agent/1-add-a-thing" branch
git -C "$repo" bundle list-heads "$out/changes.bundle" | grep -q refs/heads/agent/1-add-a-thing ||
  fail "bundle is missing the branch"

case_ "implement: verify failure goes back to the agent, leftovers get committed"
new_repo
verify '[[ ! -f game/broken ]]'
agent <<'EOF'
if [[ "$3" == 0 ]]; then touch game/broken; else rm game/broken; grep -q 'verify.sh` failed' "$1" || exit 9; fi
echo "new" >game/new.txt
printf 'feat: add new file\n\n## Summary\nNew.\n' >"$HARNESS_OUT/summary.md"
EOF
run --mode implement --branch agent/2-x
expect_eq "$(field status)" success status
expect_eq "$(field attempts)" 2 attempts
expect_eq "$(git -C "$repo" log -1 --format=%s)" "feat: add new file" "leftover commit subject"
expect_eq "$(git -C "$repo" status --porcelain)" "" "clean tree"

case_ "usage: summed over attempts; one unknown cost makes the total's unknown"
new_repo
verify '[[ -f game/fixed ]]'
agent <<'EOF'
if [[ "$3" == 0 ]]; then
  echo '{"input_tokens":10,"output_tokens":5,"cache_read_tokens":100,"cache_write_tokens":20,"cost_usd":0.5,"models":["model-a"],"cost_basis":"adapter-reported"}' >"$HARNESS_OUT/usage.json"
  echo x >game/x.txt
else
  echo '{"input_tokens":1,"output_tokens":2,"cache_read_tokens":3,"cache_write_tokens":4,"cost_usd":0.25,"models":["model-a","model-b"],"cost_basis":"adapter-reported","junk":"x"}' >"$HARNESS_OUT/usage.json"
  touch game/fixed
fi
printf 'feat: x\n' >"$HARNESS_OUT/summary.md"
EOF
run --mode implement --branch agent/20-x
expect_eq "$(jq -c .usage "$out/result.json")" \
  '{"input_tokens":11,"output_tokens":7,"cache_read_tokens":103,"cache_write_tokens":24,"cost_usd":0.75}' "summed usage"
expect_eq "$(jq -c .models "$out/result.json")" '["model-a","model-b"]' "actual models across retries"
expect_eq "$(jq -c .cost_basis "$out/result.json")" '["adapter-reported"]' "cost basis across retries"
new_repo
verify 'exit 0'
agent <<<'echo "{\"input_tokens\":1,\"output_tokens\":2,\"cost_usd\":null}" >"$HARNESS_OUT/usage.json"; echo x >game/x.txt'
run --mode implement --branch agent/21-x
expect_eq "$(jq -c .usage.cost_usd "$out/result.json")" null "unknown cost"
new_repo
agent <<<'echo x >game/x.txt'
HARNESS_MODEL=configured-model run --mode implement --branch agent/22-x
expect_eq "$(jq -c .usage "$out/result.json")" null "no usage"
expect_eq "$(jq -c .models "$out/result.json")" '["configured-model"]' "configured model without usage"

case_ "implement: gives up after --attempts"
new_repo
verify 'exit 1'
agent <<<'echo x >game/x.txt'
run --mode implement --branch agent/3-x --attempts 2
expect_eq "$code" 2 "exit code"
expect_eq "$(field status)" failed status
[[ -e "$out/changes.bundle" ]] && fail "failed run left a bundle"

case_ "implement: passing code without integration notes is returned for revision"
new_repo
verify 'exit 0'
agent <<'EOF'
echo new >game/new.txt
printf 'feat: add new behavior\n\n## Summary\nNew behavior.\n' >"$HARNESS_OUT/summary.md"
if [[ "$3" == 0 ]]; then exit 0; fi # deliberately skip the reporting fixture once
grep -q 'Integration review missing' "$1" || exit 9
EOF
run --mode implement --branch agent/14-x
expect_eq "$code" 0 "missing review repaired"
expect_eq "$(field attempts)" 2 "reporting retry"

case_ "implement: missing integration notes cannot be bundled after attempts run out"
new_repo
verify 'exit 0'
agent <<'EOF'
echo new >game/new.txt
exit 0 # intentionally leave no summary
EOF
run --mode implement --branch agent/15-x --attempts 1
expect_eq "$code" 2 "missing review refused"
[[ ! -e "$out/changes.bundle" ]] || fail 'unreviewed work bundled'
grep -q 'Integration review missing' "$out/verify-1.log" || fail 'missing review not in published failure log'

case_ "implement: agent declines"
new_repo
verify 'exit 1' # must not even run
agent <<<'printf "no changes\n\nToo vague.\n" >"$HARNESS_OUT/summary.md"'
run --mode implement --branch agent/4-x
expect_eq "$code" 0 "exit code"
expect_eq "$(field status)" no_changes status

case_ "implement: agent crash is reported, invalid titles fall back"
new_repo
verify 'exit 0'
agent <<<'echo x >game/x.txt; printf "Did stuff\n" >"$HARNESS_OUT/summary.md"; exit 3'
run --mode implement --branch agent/5-x
expect_eq "$(field status)" agent_error status
expect_eq "$(field title)" "chore: apply agent changes" "fallback title"

case_ "implement: human-review paths are listed"
new_repo
verify 'exit 0'
agent <<<'mkdir -p game/core/net && echo x >game/core/net/n.gd && echo y >game/features.txt'
run --mode implement --branch agent/6-x
expect_eq "$(cat "$out/protected.txt")" "game/core/net/n.gd" protected.txt

case_ "revise: adds commits on top of the existing remote branch"
new_repo
(cd "$repo" && git switch -qc agent/7-x && echo a >game/a.txt && git add -A &&
  git commit -qm "feat: a" && git push -q origin agent/7-x && git switch -q main && git branch -qD agent/7-x)
verify '[[ -f game/a.txt ]]'
agent <<<'echo b >game/b.txt; printf "fix: b\n" >"$HARNESS_OUT/summary.md"'
run --mode revise --branch agent/7-x
expect_eq "$(field status)" success status
expect_eq "$(git -C "$repo" log --format=%s -2 | tr '\n' ,)" "fix: b,feat: a," history

case_ "resolve-conflicts: a clean merge needs no agent"
new_repo
(cd "$repo" && git switch -qc agent/8-x && echo a >game/a.txt && git add -A && git commit -qm "feat: a" &&
  git push -q origin agent/8-x && git switch -q main && echo m >game/m.txt && git add -A &&
  git commit -qm "feat: m" && git push -q origin main)
verify 'exit 0'
agent <<<'exit 7'
run --mode resolve-conflicts --branch agent/8-x
expect_eq "$(field status)" success status
expect_eq "$(field attempts)" 0 attempts
expect_eq "$(git -C "$repo" rev-list --parents -1 HEAD | wc -w | tr -d ' ')" 3 "merge commit"

case_ "revise: includes newer base changes even when local main is stale"
new_repo
(cd "$repo" && git switch -qc agent/11-x && echo a >game/a.txt && git add -A && git commit -qm "feat: a" &&
  git push -q origin agent/11-x && git switch -q main && echo m >game/m.txt && git add -A &&
  git commit -qm "feat: m" && git push -q origin main && git reset -q --hard HEAD~1)
base_sha="$(git -C "$repo" rev-parse origin/main)"
verify '[[ -f game/a.txt && -f game/m.txt && -f game/revised.txt && -f "$(git rev-parse --git-path MERGE_HEAD)" ]]'
agent <<'EOF'
[[ -f game/m.txt ]] || exit 8
grep -q "$(git rev-parse origin/main)" "$1" || exit 9
grep -q 'do not commit or abort' "$1" || exit 10
echo revised >game/revised.txt
printf 'fix: revise feature\n' >"$HARNESS_OUT/summary.md"
EOF
run --mode revise --branch agent/11-x
expect_eq "$code" 0 "revision exit"
expect_eq "$(field base_sha)" "$base_sha" "recorded base snapshot"
git -C "$repo" merge-base --is-ancestor "$base_sha" HEAD || fail 'revision omitted base'
expect_eq "$(git -C "$repo" rev-list --parents -1 HEAD | wc -w | tr -d ' ')" 3 "verified merge commit"

case_ "revise: conflicts retain feedback and preserve both behaviors"
new_repo
(cd "$repo" && git switch -qc agent/12-x && echo branch >game/greeting.txt && git commit -qam "feat: b" &&
  git push -q origin agent/12-x && git switch -q main && echo main >game/greeting.txt &&
  git commit -qam "feat: m" && git push -q origin main)
printf 'Keep both greetings and add feedback\n' >"$work/task.md"
verify 'grep -q branch game/greeting.txt && grep -q main game/greeting.txt && grep -q feedback game/greeting.txt'
agent <<'EOF'
grep -q 'Keep both greetings and add feedback' "$1" || exit 9
printf 'branch\nmain\nfeedback\n' >game/greeting.txt
git add game/greeting.txt
printf 'fix: reconcile greetings\n' >"$HARNESS_OUT/summary.md"
EOF
run --mode revise --branch agent/12-x
expect_eq "$code" 0 "conflicting revision exit"
expect_eq "$(git -C "$repo" show HEAD:game/greeting.txt | tr '\n' ,)" "branch,main,feedback," resolution

case_ "revise: failed combined verification leaves the merge uncommitted"
new_repo
(cd "$repo" && git switch -qc agent/13-x && echo a >game/a.txt && git add -A && git commit -qm "feat: a" &&
  git push -q origin agent/13-x && git switch -q main && echo m >game/m.txt && git add -A &&
  git commit -qm "feat: m" && git push -q origin main)
original="$(git -C "$repo" rev-parse agent/13-x)"
verify 'exit 1'
agent <<<'printf "no changes\n" >"$HARNESS_OUT/summary.md"'
run --mode revise --branch agent/13-x --attempts 1
expect_eq "$code" 2 "failed merge verification"
expect_eq "$(git -C "$repo" rev-parse HEAD)" "$original" "failed merge must not commit"
[[ ! -e "$out/changes.bundle" ]] || fail 'failed merge bundled'

case_ "resolve-conflicts: the agent resolves, the harness concludes the merge"
new_repo
(cd "$repo" && git switch -qc agent/9-x && echo branch >game/greeting.txt && git commit -qam "feat: b" &&
  git push -q origin agent/9-x && git switch -q main && echo main >game/greeting.txt &&
  git commit -qam "feat: m" && git push -q origin main)
verify 'exit 0'
agent <<'EOF'
if [[ "$3" == 0 ]]; then git add game/greeting.txt; exit 0; fi # leaves markers in
printf 'branch\nmain\n' >game/greeting.txt && git add game/greeting.txt
printf 'chore: merge main\n' >"$HARNESS_OUT/summary.md"
EOF
run --mode resolve-conflicts --branch agent/9-x
expect_eq "$(field status)" success status
expect_eq "$(field attempts)" 2 attempts
expect_eq "$(git -C "$repo" show HEAD:game/greeting.txt | tr '\n' ,)" "branch,main," resolution
expect_eq "$(git -C "$repo" rev-list --parents -1 HEAD | wc -w | tr -d ' ')" 3 "merge commit"

case_ "refuses a dirty tree and an --out inside the repo"
new_repo
touch "$repo/dirty"
run --mode implement --branch agent/10-x
expect_eq "$code" 1 "dirty tree exit code"
rm "$repo/dirty"
out="$repo/out" run --mode implement --branch agent/10-x
expect_eq "$code" 1 "out inside repo exit code"

if [[ "$failures" -gt 0 ]]; then
  echo "harness tests: $failures failure(s)"
  exit 1
fi
echo "harness tests passed"
