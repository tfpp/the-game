# Gun inspection

Press **F** with a gun equipped in first person to lift it, turn it to examine both
sides, and settle back into the ready pose. The pistol, SMG, shotgun, AWP and all six
generated ammo families have distinct timings and poses. Inspect weapon is rebindable
under Settings > Controls > Items. Repeated presses do not restart the animation.
Fire, reload, drop, switching equipment, third person, and menus cancel immediately.

`rust/src/motion.rs` owns animation state, timing, smooth interpolation and poses.
`rust/src/lib.rs` exposes that controller as Godot's `WeaponInspect` class through
godot-rust. This is a **runtime Rust GDExtension**, not generated animation data or a
GDScript implementation of the motion. `gun_inspect.gd` is the input and mount adapter.
Its priority 15 runs after the camera and before Hand/GunRig update at priority 20.
The offset moves the hand root so its grip and supporting arm follow the gun; recoil
keeps its separate nested view transform. Inspection is local cosmetic state and
does not send RPCs, change ammo or alter the server's aim calculation.

## Build

From the repo root:

```sh
game/scripts/setup_rust.sh       # install pinned Rust 1.98.1, rustfmt and clippy
game/scripts/build_rust.sh native
godot --path game --editor

game/scripts/setup_rust.sh web   # also nightly-2026-04-01 + Emscripten 3.1.74
GODOT=godot game/scripts/export.sh web
```

Native macOS, Linux x86_64 and Windows x86_64 library paths are declared in
`gun_inspect.gdextension`; build for the editor's platform before importing. Linux
server exports need the Linux library and are built on Linux in CI. Build products
under `bin/` and `rust/target/` are ignored; Cargo.lock is committed.

Web uses the same Rust code compiled to `wasm32-unknown-emscripten` with
`experimental-wasm-nothreads`, alongside Godot's extension-enabled, single-threaded
web template. The setup follows the [godot-rust web export guide](https://godot-rust.github.io/book/toolchain/export-web.html).
Nightly is pinned because the legacy Emscripten exception flags change across Rust
releases. Keep its version, compiler flags and Emscripten version together when upgrading.

`harness/verify.sh` now runs Rust formatting, clippy and unit tests and builds the
native library before the usual Godot checks. GUT integration tests under
`tests/features/gun_inspect/` load the real Rust class and exercise F, every gun family,
return to rest, cancellation, menu suppression and isolation from remote hands.
