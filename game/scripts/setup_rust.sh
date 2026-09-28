#!/usr/bin/env bash
# Explicit toolchain setup for contributors and CI; build_rust.sh never installs tools.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
if ! command -v rustup >/dev/null; then
  installer=$(mktemp)
  curl --proto '=https' --tlsv1.2 -fsS https://sh.rustup.rs -o "$installer"
  sh "$installer" -y --profile minimal --default-toolchain none
  rm -f "$installer"
fi
rustup toolchain install 1.98.1 --profile minimal --component rustfmt,clippy
if [[ "${1:-native}" == web ]]; then
  rustup toolchain install nightly-2026-04-01 --profile minimal --component rust-src \
    --target wasm32-unknown-emscripten
  sdk="${EMSDK:-$root/build/emsdk}"
  if [[ ! -f "$sdk/emsdk" ]]; then
    git clone --depth 1 --branch 3.1.74 https://github.com/emscripten-core/emsdk.git "$sdk"
  fi
  "$sdk/emsdk" install 3.1.74
  "$sdk/emsdk" activate 3.1.74
fi
