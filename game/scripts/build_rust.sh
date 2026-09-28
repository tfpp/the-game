#!/usr/bin/env bash
# Build the inspect GDExtension before Godot imports scripts that use its class.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
crate="$root/game/features/gun_inspect/rust"
output="$root/game/features/gun_inspect/bin"
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
command -v cargo >/dev/null || { echo 'Run game/scripts/setup_rust.sh first.' >&2; exit 1; }
mkdir -p "$output"
cd "$crate"
case "${1:-native}" in
  check)
    cargo +1.98.1 fmt --check
    cargo +1.98.1 clippy --locked --all-targets -- -D warnings
    cargo +1.98.1 test --locked
    ;;
  native)
    cargo +1.98.1 build --locked --release
    case "$(uname -s)" in
      Darwin) library=libgun_inspect.dylib ;;
      Linux) library=libgun_inspect.so ;;
      MINGW*|MSYS*) library=gun_inspect.dll ;;
      *) echo 'Unsupported native Rust build platform.' >&2; exit 1 ;;
    esac
    cp "target/release/$library" "$output/$library"
    ;;
  web)
    sdk="${EMSDK:-$root/build/emsdk}"
    [[ -f "$sdk/emsdk_env.sh" ]] || { echo 'Run game/scripts/setup_rust.sh web first.' >&2; exit 1; }
    # shellcheck source=/dev/null
    EMSDK_QUIET=1 source "$sdk/emsdk_env.sh" >/dev/null
    export RUSTFLAGS='-C link-args=-sSIDE_MODULE=2 -C llvm-args=-enable-emscripten-cxx-exceptions=0 -Z default-visibility=hidden -Z link-native-libraries=no -Z emscripten-wasm-eh=false'
    cargo +nightly-2026-04-01 build --locked --release --features web \
      -Zbuild-std --target wasm32-unknown-emscripten
    cp target/wasm32-unknown-emscripten/release/gun_inspect.wasm "$output/gun_inspect.wasm"
    ;;
  *) echo 'Usage: build_rust.sh native|web|check' >&2; exit 1 ;;
esac
