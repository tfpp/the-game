#!/usr/bin/env bash
# Cuts a release in the working tree (release.yml runs it on the tip of main, then
# commits, tags and publishes): bumps the version in game/project.godot and rolls the
# `## [edge]` section of CHANGELOG.md into a section for the new version, leaving an
# empty edge. Prints the new version; writes the release notes to NOTES_FILE.
#   scripts/release.sh patch|minor|major NOTES_FILE
set -euo pipefail
bump="${1:-}"
notes_file="${2:?usage: scripts/release.sh patch|minor|major NOTES_FILE}"
repo_url="${REPO_URL:-https://github.com/tfpp/the-game}"
project=game/project.godot
changelog=CHANGELOG.md

current="$(sed -nE 's/^config\/version="([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' "$project")"
[[ -n "$current" ]] || { echo "no config/version=\"X.Y.Z\" in $project" >&2; exit 1; }
IFS=. read -r major minor patch <<<"$current"
case "$bump" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="$major.$((minor + 1)).0" ;;
  patch) next="$major.$minor.$((patch + 1))" ;;
  *) echo "bump must be patch, minor or major" >&2; exit 2 ;;
esac
if git rev-parse -q --verify "refs/tags/v$next" >/dev/null; then
  echo "v$next is already tagged" >&2
  exit 1
fi
[[ "$(grep -c '^## \[edge\]$' "$changelog")" == 1 ]] ||
  { echo "$changelog needs exactly one '## [edge]' heading" >&2; exit 1; }

# The edge's lines, without leading or trailing blank lines.
python3 "$(dirname "$0")/feature_notes.py" edge WORKTREE > "$notes_file"
if [[ ! -s "$notes_file" ]]; then
  echo "- No notable changes." > "$notes_file"
fi

# Replace the edge with an empty one and the new release below it.
awk -v heading="## [$next]($repo_url/releases/tag/v$next) - $(date -u +%F)" -v notes="$notes_file" '
  $0 == "## [edge]" {
    print; print ""; print heading; print ""
    while ((getline line < notes) > 0) print line
    print ""
    skipping = 1; next
  }
  /^## / { skipping = 0 }
  !skipping { print }
' "$changelog" > "$changelog.new"
mv "$changelog.new" "$changelog"

sed -i.bak -E "s/^config\\/version=\"$current\"$/config\\/version=\"$next\"/" "$project"
rm -f "$project.bak"
echo "$next"
