#!/usr/bin/env bash
# Collect notes using Godot, which is already required to build the game.
set -euo pipefail
collector="$(cd "$(dirname "$0")/release_notes" && pwd)"
output="$(mktemp)"
trap 'rm -f "$output"' EXIT
"${GODOT:-godot}" --headless --quiet --path "$collector" -s "$collector/collect.gd" -- "$PWD" "$output" "$@"
cat "$output"
