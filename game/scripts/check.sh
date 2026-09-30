#!/usr/bin/env bash
# Full game verification: format, lint, import, unit tests, offline + multiplayer smoke.
# Usage: game/scripts/check.sh   (env GODOT=/path/to/godot to override)
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
GDTOOLKIT="${GDTOOLKIT:-uvx --from gdtoolkit==4.* }"
SRC=(core ui world tests)
[[ -d features ]] && SRC+=(features)

step() { printf '\n==> %s\n' "$*"; }

step "feature release notes"
(cd .. && scripts/feature_notes.sh validate WORKTREE)
# harness/verify.sh sets this when the branch doesn't touch scripts/.
if [[ -z "${CHECK_SKIP_RELEASE_TESTS:-}" ]]; then
  ../scripts/release_test.sh
  ../scripts/release_notes_test.sh
else
  echo "skipped release script tests: no changes under scripts/"
fi

step "gdformat --check"
${GDTOOLKIT}gdformat --check "${SRC[@]}"
${GDTOOLKIT}gdformat --check ../scripts/release_notes

step "gdlint"
${GDTOOLKIT}gdlint "${SRC[@]}"
${GDTOOLKIT}gdlint ../scripts/release_notes

step "import (parse all scripts/scenes)"
out=$("$GODOT" --headless --import 2>&1 || true)
if grep -E "SCRIPT ERROR|Parse Error|ERROR:" <<<"$out"; then
  echo "import reported errors" >&2; exit 1
fi

step "unit tests (GUT)"
# --fixed-fps steps frames as fast as the CPU allows instead of pacing them in real time,
# which cuts the suite from minutes to seconds. 64 matches physics_ticks_per_second, so
# every frame runs exactly one physics step. Tests that need the wall clock (cooldowns,
# ENet, audio playback) wait with tests/fixtures/real_time.gd.
"$GODOT" --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd

step "offline smoke (run main scene)"
out=$(timeout 20 "$GODOT" --headless --quit-after 240 2>&1 || true)
if grep -E "SCRIPT ERROR|ERROR:" <<<"$out"; then
  echo "offline run reported errors" >&2; exit 1
fi

step "multiplayer smoke"
scripts/net_smoke.sh

printf '\nAll game checks passed.\n'
