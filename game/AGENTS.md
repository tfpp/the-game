# Game agent guide

A Godot 4.7 (GDScript) multiplayer sandbox. The web client and the dedicated server are
built from this one project. Read `../docs/architecture.md` for the big picture.

## Definition of done

Run `../harness/verify.sh`, or `scripts/check.sh` for the game only. It must pass:
- `gdformat --check`
- `gdlint`
- a headless import with no script errors
- GUT tests
- an offline smoke run
- a 1 server + 2 client multiplayer smoke test

## Layout

- `core/`: engine-level systems (movement, player, networking, input, game root,
  feature loader). Avoid editing this for features. Changes here need human review.
- `features/<name>/`: one directory per feature, containing its scenes and scripts.
- `world/`: level geometry (CSG for now).
- `ui/`: HUD and menus.
- `tests/`: GUT tests (`test_*.gd`, `extends GutTest`). Put feature tests in
  `tests/features/<name>/`.

## Adding a feature

- Create `features/<name>/feature.tscn`. The game loads every one at startup, sorted by
  directory name, as `/root/Game/Features/<name>`. Directories without a `feature.tscn`
  (shared scripts, libraries) are not loaded.
- Don't edit `main.tscn`, `world/` or other features to wire yours in. Position it with
  its root node's transform; the `Features` node sits at the origin.
- Features load on every peer before networking starts, so spawners, synchronizers and
  RPCs inside the scene have matching paths everywhere. The multiplayer rules below apply.
- A scene that fails to load is logged and skipped, which fails the smoke tests.
- Put tests in `tests/features/<name>/`.
- Player preferences go on a page in the Esc menu's Settings (join the `settings_pages`
  group; see `features/settings/settings.gd`) and persist with `SettingsStore`. New input
  actions show up on the Controls page automatically; add them to `SECTIONS` in
  `features/control_scheme/input_bindings.gd` for a proper label.

## Multiplayer rules (important)

- **Server-authoritative by default.** Change shared state only inside
  `if multiplayer.is_server():`.
  - Clients request changes via `@rpc("any_peer", "call_local", "reliable")` functions.
  - The server validates `multiplayer.get_remote_sender_id()`.
- **Replication:**
  - Spawn networked nodes on the server through a `MultiplayerSpawner`.
  - Sync their state with a `MultiplayerSynchronizer` whose authority is 1 (the server).
- **The one exception is player movement,** which is client-authoritative: each `Player`
  is owned by its peer and synced by `Player/Sync`.
  - Don't move other players directly.
  - To move a player from the server, call
    `player.server_teleport.rpc_id(player.get_multiplayer_authority(), pos)`.
- Offline mode is a server with a single peer (id 1), so server code paths also run in
  single player.
- Don't use `get_tree().root` paths across peers. Node names must match on every peer
  (spawners handle this).

## Style

- Use static typing everywhere. Untyped declarations are errors (see `project.godot`
  `[debug]`).
- Movement math lives in `core/movement/source_movement.gd` as pure static functions.
  Keep it deterministic and unit-tested.
- Units: Source "hammer units" in config, meters at runtime (`MovementConfig.UNIT_TO_METERS`).
- Keep scenes (`.tscn`) small and text-diffable.

## Commands

```bash
scripts/check.sh               # everything
godot --headless -s addons/gut/gut_cmdln.gd   # tests only
godot -- --server --port=7777  # local dedicated server (add --headless for no window)
godot -- --connect=ws://127.0.0.1:7777       # client
scripts/export.sh web|server|all   # needs export templates
```
