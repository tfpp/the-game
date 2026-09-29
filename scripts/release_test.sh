#!/usr/bin/env bash
# Tests for scripts/release.sh in a throwaway directory. Run: scripts/release_test.sh
set -euo pipefail
release="$(cd "$(dirname "$0")" && pwd)/release.sh"
failures=0
check() { # check NAME WANT GOT
  if [[ "$2" != "$3" ]]; then
    printf 'FAIL: %s\n--- want\n%s\n--- got\n%s\n' "$1" "$2" "$3" >&2
    failures=$((failures + 1))
  fi
}
setup() { # setup VERSION EDGE_LINES
  cd "$(mktemp -d)"
  git init -q -b main
  mkdir game
  printf '[application]\n\nconfig/name="The Game"\nconfig/version="%s"\n' "$1" > game/project.godot
  printf '# Changelog\n\nIntro.\n\n## [edge]\n%s\n## [0.6.0](https://x) - 2026-01-01\n\n- Seed.\n' "$2" > CHANGELOG.md
}
today="$(date -u +%F)"

setup 0.6.0 $'\n- Add hats.\n  With feathers.\n- Fix frogs.\n\n'
check "patch prints the version" 0.6.1 "$("$release" patch notes.md)"
check "notes" $'- Add hats.\n  With feathers.\n- Fix frogs.' "$(cat notes.md)"
check "project version" 'config/version="0.6.1"' "$(grep config/version game/project.godot)"
check "changelog" "# Changelog

Intro.

## [edge]

## [0.6.1](https://github.com/tfpp/the-game/releases/tag/v0.6.1) - $today

- Add hats.
  With feathers.
- Fix frogs.

## [0.6.0](https://x) - 2026-01-01

- Seed." "$(cat CHANGELOG.md)"
check "the next release starts from an empty edge" 0.7.0 "$("$release" minor notes.md)"
check "empty edge notes" "- No notable changes." "$(cat notes.md)"
check "sections" "## [edge]
## [0.7.0](https://github.com/tfpp/the-game/releases/tag/v0.7.0) - $today
## [0.6.1](https://github.com/tfpp/the-game/releases/tag/v0.6.1) - $today
## [0.6.0](https://x) - 2026-01-01" "$(grep '^## ' CHANGELOG.md)"

setup 1.4.2 $'\n- Break things.\n'
check "major" 2.0.0 "$("$release" major notes.md)"

setup 0.6.0 ''
git -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
git tag v0.6.1
check "refuses an existing tag" "" "$("$release" patch notes.md 2>/dev/null || true)"
check "bad bump" "" "$("$release" huge notes.md 2>/dev/null || true)"
check "nothing changed after a refusal" 'config/version="0.6.0"' "$(grep config/version game/project.godot)"

# Release collation keeps feature files unchanged and tags prevent replay.
setup 0.6.0 $'\n- Legacy note.\n'
mkdir -p game/features/hats/release_notes
cat > game/features/hats/release_notes/201-hats.json <<'JSON'
{"title":"Hats","summary":"Wear hats.","notes":["Add hats.","Fix hat colors."]}
JSON
check "collated release version" 0.6.1 "$("$release" patch notes.md)"
check "collated notes" $'- Legacy note.\n- Add hats.\n- Fix hat colors.' "$(cat notes.md)"
git -c user.email=t@e -c user.name=t add game CHANGELOG.md
git -c user.email=t@e -c user.name=t commit -q -m release
git tag v0.6.1
check "following release version" 0.6.2 "$("$release" patch notes.md)"
check "released files are not replayed" '- No notable changes.' "$(cat notes.md)"
check "released feature file is retained" true "$([[ -f game/features/hats/release_notes/201-hats.json ]] && echo true)"

if ((failures)); then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "release.sh: all tests passed"
