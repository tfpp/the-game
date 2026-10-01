# Agent guide

Monorepo for a Discord-driven, agent-built multiplayer game. Architecture:
`docs/architecture.md`.

- `game/`: Godot 4.7 GDScript project. Read `game/AGENTS.md` before touching it.
- `bot/`, `api/`: Go services. Use `gofmt`, `go vet` and `go test ./...`.
- `harness/`: agent runner and `verify.sh`.
- `docs/`: intended game design, lore, visual references, delivery phases, technical
  architecture and contributor guides. Start with the reading order below.

## Required game context

Before planning or implementing a task, read both of these documents in full:

1. [Lore and world](docs/design/lore.md): the setting, tone, established canon and
   mysteries that should remain undefined.
2. [Gameplay](docs/design/gameplay.md): the player experience, core loop, movement,
   combat, economy and multiplayer goals.

Use them to understand what Casino Royale should become: a safe social and gambling
hub in The Golden Crown, connected by elevator to fast, low-friction PvPvE excursions
in the slums. Keep changes consistent with that direction unless the user explicitly
requests a departure. Preserve intentionally undefined lore and TBD mechanics.

These documents describe intended design, not necessarily shipped behavior. Inspect
the relevant code and tests to establish what exists, and identify material differences
when they affect the task. Reading the design does not expand the requested scope.

## Documentation map

After the required reading, follow the documents relevant to the task:

| Path | What to find / when to read |
| --- | --- |
| [docs/design/lore.md](docs/design/lore.md) | World premise, Golden Crown, slums, elevator, tone and canon. Required for every task. |
| [docs/design/gameplay.md](docs/design/gameplay.md) | Intended player loop and system behavior. Required for every task. |
| [docs/design/art-style.md](docs/design/art-style.md) | Visual direction, geometry, textures, materials and lighting. Read before visual or asset work. |
| [docs/asset-generation.md](docs/asset-generation.md) | Agent workflow for creating and updating assets: Blockbench MCP, references, low-poly modeling, small textures, GridMap interiors, export and rendered review. Read before model, texture or interior work. |
| [game/features/casino_hub/gridmap/README.md](game/features/casino_hub/gridmap/README.md) | How interiors are built from GridMap tiles and a MeshLibrary. Read before building or changing rooms; the casino (`casino_gridmap.tscn`, `gridmap/tiles.tscn`) is the example to copy. |
| [docs/design/model-workflow.md](docs/design/model-workflow.md) | Model authoring, UV maps, generated texture templates, validation and the 128px texture limit. |
| [docs/design/concept-art/](docs/design/concept-art/) | Visual references. Open relevant images before modeling or scene design: `dealer.png` and `dealer-side.png` for the character, `casino.png` for the casino, and `elevator-parking-garage.png` / `loot-parking-garage.png` for garage scenes. |
| [docs/design/zones/](docs/design/zones/) | Location-specific design, grouped by zone type. Read the relevant zone document before changing its layout, encounters or atmosphere. |
| [docs/design/zones/slums/parking-garage.md](docs/design/zones/slums/parking-garage.md) | Garage layout, vertical progression, combat, loot and atmosphere. |
| [docs/design/zones/casinos/the-golden-crown.md](docs/design/zones/casinos/the-golden-crown.md) | Casino-specific document; currently a placeholder. Use lore and gameplay for established casino requirements. |
| [docs/project/phases.md](docs/project/phases.md) | Delivery phases, dependencies and progress checklist. Consult before feature planning; check prerequisite work in code before moving to a later phase. |
| [docs/architecture.md](docs/architecture.md) | Service boundaries, networking, accounts, deployment and the agent pipeline. Read for implementation context. |
| [docs/guns.md](docs/guns.md) | Every gun, its owning feature and whether it uses the player hand rig or floats. |
| [docs/controls.md](docs/controls.md) | Player inputs across keyboard/mouse, controller and touch, plus device checks. |
| [docs/conventional-commits.md](docs/conventional-commits.md) | Commit message conventions. |
| [docs/pull-requests.md](docs/pull-requests.md) | Pull request requirements and review guidance. |

Run `rg --files docs` to discover new documents and references beyond this map.
Follow relevant links within the documents and read directory-specific `AGENTS.md`
files before editing the corresponding code.

## Rules

- Build interiors (walls, floors, ramps, ceilings) as GridMap tiles from a MeshLibrary,
  not CSG geometry. Read the GridMap guide in the documentation map when needed and
  use the casino (`casino_gridmap.tscn` with `gridmap/tiles.tscn`) as the example.
- Model and world textures must be no larger than **128×128 pixels**. Treat the
  limit as a maximum, not a default: scale texture size to physical size and visible
  detail (small simple pickups can use 16×16 or 32×32; modest props 32×32 or 64×64).
  Follow the GoldSrc-inspired art direction and UV workflow in `docs/design/model-workflow.md`.
  Keep larger painting sources and UV guides outside `game/`; they are authoring
  documents, not runtime textures.
- Never introduce Python code, scripts, tooling or runtime/build dependencies. Use
  GDScript, Go, shell or the repository's existing native systems instead.
- Never commit to or push `main` directly. Before starting work, run
  `git switch main && git pull --ff-only`, then create a new branch from it
  (`git switch -c <type>/<short-description>`).
- `harness/verify.sh` must pass before any commit or PR.
- Feature work goes in `<type>/<short-description>`. Don't modify `.github/`, `harness/`,
  `bot/`, `api/`, `game/core/` or `game/project.godot` unless the task explicitly asks
  for it. Those paths need human review.
- Every notable change adds a new JSON file in the owning feature's
  `game/features/<name>/release_notes/` directory. Use a unique issue-prefixed or
  descriptive filename, even when several PRs change the same feature. See
  `docs/release-notes.md` for the schema. The same file supplies the in-game entry,
  release bullets and Discord edge announcements. For cross-cutting tooling/docs work,
  use the nearest affected feature (release tooling belongs to `changelog`).
- Do not edit the shared `game/features/changelog/entries.gd` or `CHANGELOG.md` lists
  to record new changes. They retain legacy history; release automation updates
  `CHANGELOG.md`. Once a note ships in a release, keep its filename, title and content
  immutable and add a new file for the next change. Do not bump `config/version`.
- Commits follow Conventional Commits (`docs/conventional-commits.md`).
- Pull requests follow (`docs/pull-requests.md`).
