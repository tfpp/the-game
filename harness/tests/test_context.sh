#!/usr/bin/env bash
# Context collection must include sibling work without silently losing API failures.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_DIR/calls"
[[ "$*" != *"${FAIL_PATH:-never-match}"* ]] || exit 1
case "$*" in
  *'repos/o/r/pulls/9/files?per_page=100'*) echo '[]' ;;
  *'repos/o/r/pulls/'*'/files?per_page=100'*)
    echo '[{"filename":"game/features/money/wallet.gd","previous_filename":"game/features/money/old.gd"}]'
    echo '[{"filename":"game/tests/features/money/test_wallet.gd"}]' ;;
  *'repos/o/r/pulls/9/reviews'*) echo '[{"user":{"type":"User","login":"reviewer"},"state":"CHANGES_REQUESTED","body":"Keep wallet compatibility"}]' ;;
  *'/comments'*) echo '[]' ;;
  *'repos/o/r/pulls/9')
    echo '{"number":9,"title":"Current feature","body":"Original design","base":{"ref":"release/game"}}' ;;
  *'state=open'*) cat "$FAKE_DIR/open.json" ;;
  *'state=closed'*) echo '[{"number":8,"title":"Merged wallet","html_url":"https://pr/8","merged_at":"2026-09-20"},{"number":7,"title":"Closed without merge","merged_at":null}]' ;;
  *'repos/o/r/issues/5')
    echo '{"number":5,"title":"New feature","body":"Use the wallet\n\nRequested-by: Alice <discord:42>","user":{"type":"Bot","login":"request-bot"}}' ;;
  *'repos/o/r --jq .default_branch') echo main ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" FAKE_DIR="$work" GITHUB_REPOSITORY=o/r
cat >"$work/open.json" <<'EOF'
[{"number":10,"title":"Wallet purchases","body":"Reuse money","html_url":"https://pr/10","head":{"ref":"wallet","sha":"abc"},"draft":true}]
[{"number":9,"title":"Current feature","body":"Original design","html_url":"https://pr/9","head":{"ref":"current","sha":"def"},"draft":false}]
EOF
printf 'Make it blue\n' >"$work/instructions"
failures=0
fail() { echo "  FAIL: $*"; failures=$((failures + 1)); }
contains() { grep -Fq -- "$1" "$work/context" || fail "missing: $1"; }

echo '- context includes open PRs, paginated paths, recent merges and request attribution'
"$here/../context.sh" --issue 5 >"$work/context"
for want in 'base `main`' 'PR #10: Wallet purchases' 'Reuse money' 'draft: true' \
  'money/wallet.gd' 'money/old.gd' 'money/test_wallet.gd' '#8: Merged wallet' \
  'Requested by Alice on Discord' 'Use the wallet'; do contains "$want"; done
grep -q 'Closed without merge' "$work/context" && fail 'unmerged closed PR included'

echo '- revisions include their own description once and select peers on the PR base'
"$here/../context.sh" --issue 5 --pr 9 --instructions-file "$work/instructions" >"$work/context"
contains 'base `release/game`'
contains 'Current PR #9: Current feature'
contains 'Keep wallet compatibility'
[[ "$(grep -c 'Original design' "$work/context")" == 1 ]] || fail 'current PR duplicated as peer'
grep -Fq -- '-f base=release/game' "$work/calls" || fail 'PR base not used in API request'
[[ "$(tail -n 1 "$work/context")" == 'Make it blue' ]] || fail 'latest instructions are not last'

echo '- context bounds large descriptions and explicitly lists omitted PRs'
jq -n '[range(10;32) | {number:., title:"Peer", body:("x" * 4100), html_url:"https://pr/peer", head:{ref:"x",sha:"x"}, draft:false}]' >"$work/open.json"
"$here/../context.sh" --issue 5 >"$work/context"
contains '[description truncated]'
contains 'Additional open PRs (details omitted)'
contains '#31: Peer'
[[ "$(grep -c '^#### PR #' "$work/context")" == 20 ]] || fail 'peer detail limit'
if FAIL_PATH=pulls/10/files "$here/../context.sh" --issue 5 >"$work/context" 2>/dev/null; then
  fail 'file-list API failure silently accepted'
fi

echo '- empty backlog is distinct from a failed context request'
echo '[]' >"$work/open.json"
"$here/../context.sh" --issue 5 >"$work/context"
contains 'Open PRs (0 total'
if FAIL_PATH=state=open "$here/../context.sh" --issue 5 >"$work/context" 2>/dev/null; then
  fail 'API failure silently accepted'
fi
[[ "$failures" == 0 ]] || exit 1
echo 'context tests passed'
