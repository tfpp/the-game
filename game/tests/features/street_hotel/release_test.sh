#!/usr/bin/env bash
# Use the Godot linux_release template, not the editor/debug binary.
set -euo pipefail
cd "$(dirname "$0")/../../.."
release_godot="${GODOT_RELEASE:?Set GODOT_RELEASE to the Godot linux_release.x86_64 template}"
editor="${GODOT:-godot}"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cp -a . "$scratch/project"
sed -i 's@run/main_scene="res://main.tscn"@run/main_scene="res://tests/features/street_hotel/release_probe.tscn"@' "$scratch/project/project.godot"
sed -i 's@tests/\*, @@g' "$scratch/project/export_presets.cfg"
"$editor" --headless --path "$scratch/project" --export-pack Web "$scratch/probe.pck" >"$scratch/export.log" 2>&1
# Official release templates prohibit --path/--main-pack overrides. Use a sibling PCK.
cp "$release_godot" "$scratch/probe.x86_64"
chmod +x "$scratch/probe.x86_64"
log="$scratch/run.log"
timeout 60 "$scratch/probe.x86_64" --headless --fixed-fps 64 >"$log" 2>&1
cat "$log"
if grep -Eq 'SCRIPT ERROR|ERROR:|HOTEL_RELEASE_FAIL' "$log"; then exit 1; fi
grep -q HOTEL_RELEASE_PASS "$log"
