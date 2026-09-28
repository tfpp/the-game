#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
check="$here/../check-summary.sh"
failures=0
fail() { echo "  FAIL: $*"; failures=$((failures + 1)); }
reject() { if "$check" "$work/summary.md" >"$work/problem"; then fail "$1"; fi; }

echo '- a missing summary or empty integration headings fail'
reject 'missing summary accepted'
cat >"$work/summary.md" <<'EOF'
## Integration
### Systems inspected
### Reuse decision
### Compatibility checks
EOF
reject 'empty sections accepted'
grep -q 'Systems inspected' "$work/problem" || fail 'missing diagnostic'

echo '- unrelated sections and quoted examples cannot satisfy the review'
cat >"$work/summary.md" <<'EOF'
## Integration
### Systems inspected
<Concrete paths>
### Reuse decision
-
### Compatibility checks

## Validation
This text belongs to another section.
```
## Integration
### Systems inspected
Quoted example
### Reuse decision
Quoted example
### Compatibility checks
Quoted example
```
EOF
reject 'empty notes accepted from unrelated content'

echo '- both extending a suitable system and justified new systems are valid'
HARNESS_OUT="$work" source "$here/fixtures/complete-summary.sh"
"$check" "$work/summary.md" || fail 'extension report rejected'
cat >"$work/summary.md" <<'EOF'
feat: add weather

## Integration
### Systems inspected
Searched game/features and inspected game/features/money/README.md. Existing systems
handle currency and interactions; none owns weather state or rendering.
### Reuse decision
Create a weather feature with its own server-owned state. Currency cannot represent
weather and does not need to be extended for this request.
### Compatibility checks
Weather tests cover its state and rendering. Multiplayer smoke covers existing players;
the new feature has no shared wallet or interaction state.
EOF
"$check" "$work/summary.md" || fail 'new independent system rejected'
[[ "$failures" == 0 ]] || exit 1
echo 'summary tests passed'
