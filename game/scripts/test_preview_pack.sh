#!/usr/bin/env bash
# Exercise the actual preview.yml packaging step against current/legacy HTML.
set -euo pipefail
cd "$(dirname "$0")/../.."
preview_test_dir=$(mktemp -d)
trap 'rm -rf "$preview_test_dir"' EXIT
awk '
  /- name: Fit the Pages file size limit/ { step=1; next }
  step && /        run: \|/ { body=1; next }
  body && /^      - name:/ { exit }
  body { sub(/^          /, ""); print }
' .github/workflows/preview.yml > "$preview_test_dir/package.sh"
[[ -s "$preview_test_dir/package.sh" ]]

for preview_case in current legacy; do
  mkdir -p "$preview_test_dir/$preview_case/web"
  if [[ "$preview_case" == current ]]; then
    sed 's/\$GODOT_URL/index.js/g' game/features/touch_controls/shell.html \
      > "$preview_test_dir/$preview_case/web/index.html"
  else
    printf '<html><head></head><body><script src="index.js"></script></body></html>\n' \
      > "$preview_test_dir/$preview_case/web/index.html"
  fi
  printf 'engine fixture' > "$preview_test_dir/$preview_case/web/index.wasm"
  printf 'game pack fixture' > "$preview_test_dir/$preview_case/web/index.pck"
  (cd "$preview_test_dir/$preview_case" && bash -e -o pipefail "$preview_test_dir/package.sh")
  grep -q '<script src="wasm-gz.js"></script></head>' \
    "$preview_test_dir/$preview_case/web/index.html"
  gzip -cd "$preview_test_dir/$preview_case/web/index.wasm.gz" | grep -qx 'engine fixture'
  gzip -cd "$preview_test_dir/$preview_case/web/index.pck.gz" | grep -qx 'game pack fixture'
  [[ ! -f "$preview_test_dir/$preview_case/web/index.wasm" ]]
  [[ ! -f "$preview_test_dir/$preview_case/web/index.pck" ]]
done
# A file actually over the host limit must still fail the step.
truncate -s 26214401 "$preview_test_dir/legacy/web/oversized.bin"
rm "$preview_test_dir/legacy/web/index.wasm.gz" "$preview_test_dir/legacy/web/index.pck.gz"
printf 'engine' > "$preview_test_dir/legacy/web/index.wasm"
printf 'pack' > "$preview_test_dir/legacy/web/index.pck"
if (cd "$preview_test_dir/legacy" && bash -e -o pipefail "$preview_test_dir/package.sh" >/dev/null); then
  echo 'Preview packaging incorrectly accepted a file over 25 MiB' >&2
  exit 1
fi
printf 'Preview packaging tests passed (current/legacy loader, gzip round trip, size guard).\n'
