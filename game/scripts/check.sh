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

step "Rust checks and native GDExtension"
scripts/build_rust.sh check
scripts/build_rust.sh native

step "gdformat --check"
${GDTOOLKIT}gdformat --check "${SRC[@]}"

step "gdlint"
${GDTOOLKIT}gdlint "${SRC[@]}"

step "import (parse all scripts/scenes)"
out=$("$GODOT" --headless --import 2>&1 || true)
if grep -E "SCRIPT ERROR|Parse Error|ERROR:" <<<"$out"; then
  echo "import reported errors" >&2; exit 1
fi

step "unit tests (GUT)"
"$GODOT" --headless -s addons/gut/gut_cmdln.gd

step "offline smoke (run main scene)"
out=$(timeout 20 "$GODOT" --headless --quit-after 240 2>&1 || true)
if grep -E "SCRIPT ERROR|ERROR:" <<<"$out"; then
  echo "offline run reported errors" >&2; exit 1
fi

step "multiplayer smoke"
scripts/net_smoke.sh

printf '\nAll game checks passed.\n'
