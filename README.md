# Casino Royale

[![Play now](https://img.shields.io/badge/play-tfpp.github.io%2Fthe--game-blue)](https://tfpp.github.io/the-game/)
[![Game CI](https://github.com/tfpp/the-game/actions/workflows/game-ci.yml/badge.svg)](https://github.com/tfpp/the-game/actions/workflows/game-ci.yml)
[![Pages](https://github.com/tfpp/the-game/actions/workflows/pages.yml/badge.svg)](https://github.com/tfpp/the-game/actions/workflows/pages.yml)

**▶ Play it in your browser: <https://tfpp.github.io/the-game/>**

Casino Royale is a multiplayer game of desperation, greed and fleeting fortune.
Gamble inside the worn Golden Crown, then leave its gates for rain-soaked alleys
and an abandoned parking garage. Search for valuables, fight over them, escape
alive and sell what you carried home. Your winnings feed the same wallet used at
the slots and roulette table; dying during an excursion scatters your valuables
for other players to claim.

The game uses first-person Source-style movement (strafe-jumping, timed b-hops)
and is built by friends and LLM agents through Discord. Someone posts `/feature`
in Discord, a coding agent opens a pull request, a trusted member approves it
from the thread, and the change ships to everyone.

## Contents

- [How it works](#how-it-works)
- [Controls](#controls)
- [Repository layout](#repository-layout)
- [Getting started](#getting-started)
- [Contributing](#contributing)
- [Documentation](#documentation)
- [Credits](#credits)

## How it works

```
Discord ──/feature──▶ bot ──▶ GitHub issue ──▶ agent.yml (Claude / Codex / pi)
                       ▲                              │
                       │ progress, CI, approvals      ▼
                       └────────────────────── pull request ──▶ merge queue ──▶ main
                                                                                  │
                        GitHub Pages (web client) ◀── pages.yml ◀─────────────────┤
                        homelab (dedicated server) ◀── server-image.yml ◀─────────┘
```

- **Game:** Godot 4.7 (GDScript, Jolt physics, WebGL2). The web client and the headless
  dedicated server come from one project and talk over WebSockets at a 64 Hz tick.
- **Accounts:** a Go API handles email/password and Discord sign-in, display names, and
  signed join tickets that the game server checks before a player spawns.
- **Agents:** the harness runs the agent, re-runs `harness/verify.sh` until it passes, and
  opens the PR. Features live in `game/features/<name>/` and load themselves, so parallel
  PRs rarely conflict.
- **Merging and deploys:** the bot merges approved PRs one at a time, then deploys the
  matching server image once the client and server builds for that commit are both ready.

See [docs/architecture.md](docs/architecture.md) for the full design.

## Controls

Keyboard and mouse, touch and standard gamepads all work, online and offline.

| Input | Move | Look | Jump | Menu |
|---|---|---|---|---|
| Desktop | WASD / arrows | Mouse | Space / mouse wheel | Esc |
| Controller | Left stick | Right stick | A / Cross | Start |
| Touch | Drag left side | Drag right side | JUMP button | II button |

Jump happens on the press, not while held: time it on landing to b-hop. The menu has
resume, display name, link Discord, leave and sign out. More in
[docs/controls.md](docs/controls.md).

## Repository layout

| Path | What | Docs |
|---|---|---|
| [`game/`](game/) | Godot 4.7 client and dedicated server: world, Source movement, networking, features | [game/AGENTS.md](game/AGENTS.md) |
| [`api/`](api/) | Go accounts service: email/Discord sign-in, display names, join tickets | [architecture](docs/architecture.md#accounts-api) |
| [`bot/`](bot/) | Go Discord bot: `/feature`, `/revise`, `/approve`, `/queue`, merge coordinator, server deploys | [bot/README.md](bot/README.md) |
| [`harness/`](harness/) | Agent runner, prompts and `verify.sh` (the definition of done) | [harness/README.md](harness/README.md) |
| [`docs/`](docs/) | Architecture, controls, commit and pull request conventions | |

`api/` and `bot/` are separate Go modules joined by the root `go.work`.

## Getting started

### Prerequisites

- [Godot 4.7.2](https://godotengine.org/) on `PATH` as `godot` (`brew install --cask godot`)
- [uv](https://docs.astral.sh/uv/), for the GDScript formatter and linter
- Go, for `api/` and `bot/`

### Run the game

```bash
godot --path game --editor   # open in the editor
godot --path game            # play offline (the process is its own server)
```

### Verify

```bash
harness/verify.sh            # harness tests, GDScript lint + tests + smoke runs, Go checks
game/scripts/check.sh        # game checks only
```

`harness/verify.sh` must pass before any commit or PR.

### Local multiplayer

Without accounts (`--dev-insecure-auth` skips sign-in):

```bash
godot --path game --headless -- --server --port=7777 --dev-insecure-auth
godot --path game -- --connect=ws://127.0.0.1:7777 --dev-insecure-auth --name=Alice
```

With real accounts, run the API locally and share its ticket key with the server:

```bash
openssl rand -hex 32 > /tmp/ticket-key

(cd api && API_ADDR=127.0.0.1:8080 API_DB=/tmp/api.db API_TICKET_KEY_FILE=/tmp/ticket-key \
  API_DEV_LOG_MAIL=true API_ALLOWED_ORIGINS=http://localhost:8060 \
  API_CLIENT_URL=http://localhost:8060/ go run ./cmd/api)

godot --path game --headless -- --server --port=7777 --ticket-key-file=/tmp/ticket-key
```

Sign-up emails are printed to the API's log instead of being sent.

### Web build

```bash
game/scripts/export.sh web                 # exports to build/web/
python3 -m http.server -d build/web 8060
```

Open <http://localhost:8060/?server=ws://127.0.0.1:7777&api=http://127.0.0.1:8080/api>
to join the local server.

## Contributing

The usual way in is Discord: `/feature request:<text> harness:<claude|codex>` starts
an agent using the required harness choice, and `/revise <changes>`
in the thread adjusts its PR. To work on the repo directly:

- Put features in `game/features/<name>/` with a `feature.tscn`, and tests in
  `game/tests/features/<name>/`. Follow the multiplayer rules in
  [game/AGENTS.md](game/AGENTS.md).
- `.github/`, `harness/`, `bot/`, `api/`, `game/core/`, `main.tscn` and `project.godot`
  are reserved for human review (see `.github/CODEOWNERS`).
- Commits follow [Conventional Commits](docs/conventional-commits.md), and pull requests
  follow [docs/pull-requests.md](docs/pull-requests.md).
- Go code: `gofmt`, `go vet` and `go test ./...`.

## Documentation

- [Architecture](docs/architecture.md): networking and authority, accounts, the agent
  pipeline, merging, deploys and milestones
- [Controls](docs/controls.md): input devices, touch and controller behavior, device testing
- [Game agent guide](game/AGENTS.md): layout, adding a feature, multiplayer rules
- [Harness](harness/README.md): triggers, modes and setup
- [Bot](bot/README.md): commands, approvals, the merge queue and setup

## Credits

Third-party assets and libraries are listed in [CREDITS.md](CREDITS.md).
