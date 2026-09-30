#!/usr/bin/env bash
# The agent's definition of done. Every change must pass this before a PR is opened.
# On success it records the verified tree (see verified_stamp in lib.sh), so run.sh can
# skip re-running it on an identical tree.
#
# The harness and release-script self-tests only cover their own directories, so on a
# branch that doesn't touch those paths (compared with VERIFY_BASE, default origin/main)
# they are skipped. Set VERIFY_ALL=1 to always run everything.
set -euo pipefail
# shellcheck source=lib.sh source-path=SCRIPTDIR
source "$(dirname "$0")/lib.sh"
root="$REPO_ROOT"
cd "$root"
tree="$(worktree_id 2>/dev/null || true)"
stamp="$(verified_stamp 2>/dev/null || true)"
[[ -n "$stamp" ]] && rm -f "$stamp"

changed="" run_all=1
if [[ -z "${VERIFY_ALL:-}" ]] && changed="$(changed_paths)"; then run_all=0; fi
# touches REGEX -> whether this branch changes a path matching REGEX (always, with no base).
touches() { [[ "$run_all" == 1 ]] || grep -qE "$1" <<<"$changed"; }

printf '==> harness checks\n'
for f in "$root"/harness/*.sh "$root"/harness/adapters/*.sh "$root"/harness/tests/*.sh; do
  bash -n "$f"
done
if command -v shellcheck >/dev/null; then
  shellcheck -x -S warning "$root"/harness/*.sh "$root"/harness/adapters/*.sh
fi
if touches '^(harness/|\.github/CODEOWNERS$)'; then
  for t in "$root"/harness/tests/test_*.sh; do "$t"; done
else
  printf 'skipped harness tests: no changes under harness/ or .github/CODEOWNERS\n'
fi

if ! touches '^scripts/'; then
  export CHECK_SKIP_RELEASE_TESTS=1
fi
"$root/game/scripts/check.sh"

for mod in bot api; do
  if [[ -f "$root/$mod/go.mod" ]]; then
    printf '\n==> go checks: %s\n' "$mod"
    (cd "$root/$mod" && gofmt -l . | (! grep .) && go vet ./... && go test ./...)
  fi
done

# Record the tree only if the checks left it unchanged (e.g. no new .uid files).
if [[ -n "$tree" && -n "$stamp" && "$(worktree_id 2>/dev/null || true)" == "$tree" ]]; then
  printf '%s\n' "$tree" >"$stamp"
fi
