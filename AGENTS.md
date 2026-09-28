# Agent guide

Monorepo for a Discord-driven, agent-built multiplayer game. Architecture:
`docs/architecture.md`.

- `game/`: Godot 4.7 GDScript project. Read `game/AGENTS.md` before touching it.
- `bot/`, `api/`: Go services. Use `gofmt`, `go vet` and `go test ./...`.
- `harness/`: agent runner and `verify.sh`.

## Rules

- `harness/verify.sh` must pass before any commit or PR.
- Feature work goes in `game/features/<name>/`. Don't modify `.github/`, `harness/`,
  `bot/`, `api/`, `game/core/` or `game/project.godot` unless the task explicitly asks
  for it. Those paths need human review.
- Every new feature must add one entry to the in-game changelog: `ENTRIES` in
  `game/features/changelog/entries.gd` (players open it in-game with `L`). Add the
  entry in the same change that ships the feature.
- Commits follow Conventional Commits (`docs/conventional-commits.md`).
- Pull requests follow (`docs/pull-requests.md`).
