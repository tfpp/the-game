#!/usr/bin/env bash
# Keeps harness/prompts/ in step with the scripts that use them: run.sh must render every
# placeholder a prompt uses, and the summary template must show the sections that
# check-summary.sh requires.
set -euo pipefail
harness="$(cd "$(dirname "$0")/.." && pwd)"
prompts="$harness/prompts"
failures=0
fail() { echo "  FAIL: $*"; failures=$((failures + 1)); }

echo '- prompts use only the placeholders run.sh renders'
rendered="$(grep -oE '\\\{\\\{[A-Z_]+\\\}\\\}' "$harness/run.sh" | tr -d '\\{}' | sort -u)"
[[ -n "$rendered" ]] || fail 'found no placeholders in run.sh'
for f in "$prompts"/*.md; do
  while IFS= read -r name; do
    grep -qx "$name" <<<"$rendered" || fail "$(basename "$f") uses {{$name}}, which run.sh doesn't render"
  done < <(grep -oE '\{\{[A-Z_]+\}\}' "$f" | tr -d '{}' | sort -u)
done

echo '- each mode prompt includes the task, and fix.md the problem'
for mode in implement revise resolve-conflicts; do
  grep -qF '{{TASK}}' "$prompts/$mode.md" || fail "$mode.md does not include {{TASK}}"
done
grep -qF '{{PROBLEM}}' "$prompts/fix.md" || fail 'fix.md does not include {{PROBLEM}}'

echo '- the summary template has the sections check-summary.sh requires'
sections="$(sed -nE 's/^[[:space:]]*required\[[0-9]+\] = "(.*)"$/\1/p' "$harness/check-summary.sh")"
[[ -n "$sections" ]] || fail 'found no required sections in check-summary.sh'
grep -qx '## Integration' "$prompts/rules.md" || fail 'rules.md template has no ## Integration'
while IFS= read -r section; do
  grep -qx "### $section" "$prompts/rules.md" || fail "rules.md template has no ### $section"
done <<<"$sections"

[[ "$failures" == 0 ]] || exit 1
echo 'prompt tests passed'
