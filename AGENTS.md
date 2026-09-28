# Agent guide

Monorepo for a Discord-driven, agent-built multiplayer game. Architecture:
`docs/architecture.md`.

- `game/`: Godot 4.7 GDScript project. Read `game/AGENTS.md` before touching it.
- `bot/`, `api/`: Go services. Use `gofmt`, `go vet` and `go test ./...`.
- `harness/`: agent runner and `verify.sh`.

## Rules

- Never commit to or push `main` directly. Before starting work, run
  `git switch main && git pull --ff-only`, then create a new branch from it
  (`git switch -c <type>/<short-description>`).
- `harness/verify.sh` must pass before any commit or PR.
- Feature work goes in `<type>/<short-description>`. Don't modify `.github/`, `harness/`,
  `bot/`, `api/`, `game/core/` or `game/project.godot` unless the task explicitly asks
  for it. Those paths need human review.
- Every new feature must add one entry to the in-game changelog: `ENTRIES` in
  `game/features/changelog/entries.gd` (players open it in-game with `L`). Add the
  entry in the same change that ships the feature.
- Keep `CHANGELOG.md` up to date: every change that players, operators or contributors
  would notice adds a bullet to the end of its `## [edge]` section, in the same change.
  Don't add version sections or change `config/version`: releases are cut by hand with the
  `release` workflow, which rolls `edge` into the new version.
- Commits follow Conventional Commits (`docs/conventional-commits.md`).
- Pull requests follow (`docs/pull-requests.md`).
