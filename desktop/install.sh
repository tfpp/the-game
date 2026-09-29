#!/usr/bin/env bash
# Run with curl .../desktop/install.sh | bash (no sudo).
set -euo pipefail

main() (
  local ref=main prefix='' platform arch revision parent work lock bundle executable
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ref|--prefix)
        [[ $# -ge 2 && -n "$2" ]] || { echo "Missing value for $1" >&2; return 1; }
        if [[ "$1" == --ref ]]; then ref=$2; else prefix=$2; fi
        shift 2 ;;
      --help)
        echo 'Usage: bash install.sh [--ref BRANCH_OR_COMMIT] [--prefix INSTALL_DIRECTORY]'
        echo 'Requires Node.js 22.12+, npm and curl. Supports macOS, Linux and Windows Git Bash.'
        return ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
  done
  for tool in node npm curl; do
    command -v "$tool" >/dev/null || { echo "Install $tool first, then rerun this installer." >&2; return 1; }
  done
  node -e 'const [a,b]=process.versions.node.split(".").map(Number); if(a<22||(a===22&&b<12)){console.error("Node.js 22.12+ is required");process.exit(1)}'
  platform=$(node -p 'process.platform')
  arch=$(node -p 'process.arch')
  case "$arch" in x64|arm64) ;; *) echo "Unsupported architecture: $arch" >&2; return 1 ;; esac
  case "$platform" in
    darwin) prefix=${prefix:-"$HOME/Applications/TheGame"}; executable=TheGame.app ;;
    linux) prefix=${prefix:-"${XDG_DATA_HOME:-$HOME/.local/share}/the-game-desktop"}; executable=TheGame ;;
    win32)
      command -v cygpath >/dev/null || { echo 'Use Git Bash on Windows.' >&2; return 1; }
      prefix=${prefix:-"$(cygpath -u "${LOCALAPPDATA:?LOCALAPPDATA is required}")/TheGame"}
      executable=TheGame.exe ;;
    *) echo "Unsupported platform: $platform" >&2; return 1 ;;
  esac
  [[ "$ref" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo 'Invalid source ref' >&2; return 1; }
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *$'\n'* && "$prefix" != *$'\r'* ]] || {
    echo 'The install directory must be an absolute path without line breaks.' >&2; return 1;
  }
  prefix=${prefix%/}
  [[ ! -L "$prefix" ]] || { echo 'Refusing to replace a symlink install directory.' >&2; return 1; }
  if [[ -e "$prefix" && ! -f "$prefix/.the-game-installer" ]]; then
    echo "Refusing to replace unmanaged directory: $prefix" >&2; return 1
  fi
  parent=$(dirname "$prefix")
  mkdir -p "$parent"
  lock="$prefix.install-lock"
  mkdir "$lock" 2>/dev/null || { echo "Another install may be running: $lock" >&2; return 1; }
  work=$(mktemp -d "$parent/.the-game-install.XXXXXX") || { rmdir "$lock"; return 1; }
  # Keep the previous installation intact until downloading and packaging succeed.
  trap 'status=$?; if [[ -d "$work/previous" && ! -e "$prefix" ]]; then mv "$work/previous" "$prefix" || exit "$status"; fi; rm -rf "$work"; rmdir "$lock"; exit "$status"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [[ "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    revision=$ref
  else
    revision=$(curl --fail --silent --show-error --location --retry 3 --connect-timeout 20 \
      "https://api.github.com/repos/tfpp/the-game/commits/$ref" | \
      node -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const v=JSON.parse(s).sha;if(!/^[a-f0-9]{40}$/.test(v))process.exit(1);console.log(v)})')
  fi
  printf 'Installing The Game for %s/%s from %s\n' "$platform" "$arch" "$revision"
  mkdir "$work/source"
  for file in package.json package-lock.json main.cjs policy.cjs; do
    curl --fail --silent --show-error --location --retry 3 --connect-timeout 20 \
      "https://raw.githubusercontent.com/tfpp/the-game/$revision/desktop/$file" -o "$work/source/$file"
  done
  (
    cd "$work/source"
    npm ci --include=dev --no-audit --no-fund </dev/null
    npm run package -- --platform="$platform" --arch="$arch" </dev/null
  )
  bundle="$work/source/dist/TheGame-$platform-$arch"
  [[ -e "$bundle/$executable" ]] || { echo 'Packager did not produce the expected app.' >&2; return 1; }
  printf '%s\n' "$revision" > "$bundle/.the-game-installer"
  if [[ -d "$prefix" ]]; then mv "$prefix" "$work/previous"; fi
  mv "$bundle" "$prefix"
  if [[ "$platform" == linux ]]; then
    local applications="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    mkdir -p "$applications"
    node - "$prefix" "$applications/the-game.desktop" <<'NODE'
const fs = require('node:fs');
const [prefix, destination] = process.argv.slice(2);
// Desktop Entry Exec has its own quoting rules (including literal percent signs).
const exec = '"' + (prefix + '/TheGame').replace(/[\\"`$]/g, c => '\\' + c).replace(/%/g, '%%') + '"';
fs.writeFileSync(destination, '[Desktop Entry]\nType=Application\nName=The Game\nExec=' + exec.replace(/\\/g, '\\\\') + '\nTerminal=false\nCategories=Game;\n');
NODE
    printf 'Installed. Open The Game from your applications menu, or run:\n  %q\n' "$prefix/$executable"
  elif [[ "$platform" == darwin ]]; then
    printf 'Installed. Open the app in Finder, or run:\n  open %q\n' "$prefix/$executable"
  else
    printf 'Installed. Open this app in Explorer:\n  %s\n' "$(cygpath -w "$prefix/$executable")"
  fi
  echo 'Rerun this command to update the desktop wrapper. The game itself updates from the live website.'
)

# Everything is parsed before starting, including when this file arrives through a pipe.
main "$@"
