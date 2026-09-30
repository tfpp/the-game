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
- `assets/`: all media (textures, models, audio, fonts). Put a feature's files in
  `assets/<feature>/` (e.g. `assets/roulette/textures/`), never inside `features/`;
  keep scenes, materials and scripts in the feature. `assets/kenney/` holds whole
  Kenney packs (CC0; see its README). Exports ship only the files the game
  references (`scripts/unused_assets.gd`), so write asset paths as full literal
  `res://` strings, not built at runtime. Exception: `features/world_builder/textures/`
  stays put because baked `.scn` files reference it by path; moving it needs a re-bake.
- `tests/`: GUT tests (`test_*.gd`, `extends GutTest`). Put feature tests in
  `tests/features/<name>/`.

## Adding a feature

- First search for an existing system that owns the requested behavior. Read its code,
  interfaces, callers and tests. Reuse or extend it when it fits; keep shared state and
  authority in that system rather than duplicating them in a new feature.
- If no suitable system exists, create a new one and explain why the nearest existing
  systems do not fit. Do not force unrelated features together. A new feature should
  still use existing wallet, combat, interaction or other services where applicable.
- Extend an existing feature in its own directory. For a distinct new feature needing
  its own loaded scene, create `features/<name>/feature.tscn`. The game loads every one at startup, sorted by
  directory name, as `/root/Game/Features/<name>`. Directories without a `feature.tscn`
  (shared scripts, libraries) are not loaded.
- Don't edit `main.tscn`, `world/` or another feature merely to load a new scene. Position
  it with its root node's transform; the `Features` node sits at the origin. Extending an
  existing feature's API for the requested behavior is allowed; preserve its existing
  callers and test both its original behavior and the new integration.
- Features load on every peer before networking starts, so spawners, synchronizers and
  RPCs inside the scene have matching paths everywhere. The multiplayer rules below apply.
- A scene that fails to load is logged and skipped, which fails the smoke tests.
- Put tests in `tests/features/<name>/`.
- Record each notable change in its own `release_notes/<issue>-<description>.json`
  under the owning feature; see `../docs/release-notes.md`. Do not append to shared lists.
- New rooms and areas of the map need a GPS destination (`features/gps/README.md`).
- Player preferences go on a page in the Esc menu's Settings (join the `settings_pages`
  group; see `features/settings/settings.gd`) and persist with `SettingsStore`. New input
  actions show up on the Controls page automatically; add them to `SECTIONS` in
  `features/control_scheme/input_bindings.gd` for a proper label.

## Multiplayer rules (important)

- Use [`NetworkedEntity` / `NetworkedInteraction`](core/net/README.md) for new shared
  entities and when changing an existing entity's networking. Declare replicated
  fields on the component and register validation/apply callbacks in the feature.
  Keep gameplay rules in those callbacks; reuse the component for sender identity,
  server requests, cooldowns, replication and session lifecycle. Prefer this to
  copying RPC and synchronizer boilerplate into each feature. Explain any exception.
- For player interactions, use `NetworkedInteraction.register_use` and `request_use`.
  Never accept a player ID from a client payload as proof of identity. Add automated
  authority and late-join coverage when introducing shared state. Existing specialized
  systems can migrate incrementally; player movement retains its client authority.
- **Server-authoritative by default.** Change shared state only inside
  a registered server apply callback or `if multiplayer.is_server():`.
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

- Never introduce Python scripts, tooling or dependencies. Use GDScript and the
  existing native toolchain for game features, asset work and build utilities.
- Model and world textures have a hard **128×128 maximum** on both dimensions.
  Choose power-of-two size by physical scale and visible detail: small pickups can
  use 16×16 or 32×32, modest props 32×32 or 64×64, and larger models up to 128×128.
  The maximum is not a default. Use nearest mipmap filtering and
  GoldSrc-inspired coarse painted detail. See `../docs/design/model-workflow.md`.
  Author explicit UV1 islands with padding; stack or mirror repeated surfaces to
  reuse pixels. Allocate texel density by visibility and detail importance, pack with
  rotation, and avoid giving hidden faces equal texture budgets. Export a UV template, then
  check the applied result on the actual model. Keep larger painting sources and
  authoring guides outside `game/`. Vertex colours can tint the artwork.
  Keep cards, chips, text and interaction targets readable.

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
