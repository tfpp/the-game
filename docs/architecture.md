# Architecture

Friends post a feature request in Discord and an LLM coding agent builds it as a PR
against a multiplayer Godot sandbox. Trusted users approve merges from Discord, and the
game ships to GitHub Pages (client) and the homelab (server).

```
Discord ◀──▶ bot (Go, homelab)  ──GitHub App──▶  issues / PRs / workflow_dispatch
                 │                                        │
                 │ merge coordinator (serial)             ▼
                 │                          Actions: agent.yml → harness/ → PR
                 │                                   game-ci.yml → harness/verify.sh
                 ▼                                   pages.yml   → GitHub Pages (web client)
            api (Go, homelab)                        server-image.yml → ghcr.io → homelab
            accounts, sessions, join tickets
                 ▲
Browser ─────────┘  wss://game.chrisbox.dev (Cloudflare Tunnel) ──▶ game server (Godot headless, homelab)
```

## Repo layout

| Path | What | Language |
|---|---|---|
| `game/` | Godot 4.7 project: web client and dedicated server from one codebase | GDScript |
| `bot/` | Discord bot, job tracking, merge coordinator | Go |
| `api/` | Accounts (Discord OAuth plus email/password), sessions, game join tickets | Go |
| `harness/` | Agent runner: adapters, prompts, `verify.sh` (the definition of done) | bash |
| `.github/workflows/` | CI, Pages, images, `agent.yml` | YAML |
| `docs/` | This file and ADR-style notes | Markdown |

`bot/` and `api/` are separate Go modules joined by a root `go.work`.

## Game (`game/`)

- **Engine:** Godot 4.7, GDScript, Jolt physics, and the Compatibility renderer (WebGL2).
  There is no compile step, so each agent iteration takes seconds rather than minutes.
- **Tick:** 64 Hz fixed physics (`physics/common/physics_ticks_per_second`) with physics
  interpolation turned on for rendering.
- **Movement:** Source `CGameMovement` math is a pure function
  (`core/movement/source_movement.gd`), and collision is Godot's `move_and_slide` on Jolt.
  Tunables in `MovementConfig` use Source units (320 max speed, 100 airaccelerate, 30 u/s
  air wish cap, 800 gravity). There is no auto-hop: a jump happens only on the tick the key
  is *pressed*, and pressing on the landing tick skips friction.
- **Web:** single-threaded web export, so no COOP/COEP headers are needed on GitHub Pages.
  The mouse is captured on click, because browsers require a user gesture for pointer lock.
- **Menu:** the view is either playing (mouse captured) or showing the menu in
  `ui/login/`; there is no click-to-play overlay. Whenever the mouse is free with nothing
  on screen (Esc, a lost or refused pointer lock), the menu opens: Resume, change display
  name, link Discord, leave and play offline, sign out. Buttons that return to the game
  capture the mouse on press, inside the click browsers require for pointer lock. On the
  web, Esc can't re-lock the pointer, so it leaves the menu up; natively it resumes.
- **HUD corners:** version (top left), players and connection (top right), controls
  (bottom left).

### Networking and authority

Godot's high-level multiplayer runs over `WebSocketMultiplayerPeer`. WebSocket works in
browsers and passes through nginx-proxy-manager with TLS, so no UDP port-forward is needed.

| State | Authority | Mechanism |
|---|---|---|
| Player movement (position, velocity, view angles) | **Owning client** | `MultiplayerSynchronizer` on each `Player`; `set_multiplayer_authority(peer_id)` |
| Spawning and despawning players | Server | `MultiplayerSpawner` (`main.tscn/PlayerSpawner`) with a custom `spawn_function` |
| Respawns and teleports | Server requests it, owner applies it | `Player.server_teleport` RPC (rejected unless the sender is peer 1) |
| Everything else (features, world state, scores, items) | **Server** | Server-owned nodes, `MultiplayerSpawner` / `MultiplayerSynchronizer`, and client→server request RPCs |

Rules for features, repeated in `game/AGENTS.md`:
- Mutate shared state only when `multiplayer.is_server()` is true.
- Clients ask for changes with `@rpc("any_peer")` request RPCs, and the server validates
  the sender with `multiplayer.get_remote_sender_id()`.
- Replicate server state with a `MultiplayerSynchronizer` (authority 1) or a spawner.

Movement is client-authoritative, so remote players see what the owner simulated. There is
no server reconciliation. The server may add sanity checks (speed/teleport limits) and
respawn via RPC. That tradeoff is deliberate for a friends-only sandbox.

**Run modes** (`core/net/network.gd`):
- Dedicated server: `godot --headless -- --server --port=7777`.
- Client: `-- --connect=ws://host:7777`, or `?server=wss://…` on the web.
- Offline: the default. The process is its own server, so single player works without
  a backend.

## Accounts (`api/`)

A Go service (`net/http`, pure-Go SQLite via `modernc.org/sqlite`, no CGO) on the same
VM as the game server. Every route is under `/api/`, so one hostname serves both: the
tunnel sends `game.chrisbox.dev/api/*` to the API and everything else to the game server.

- **Accounts:** one row per player, reached by email and password (argon2id, 19 MiB /
  t=2 / p=1), by Discord OAuth2 (scope `identify`), or both once linked. Every player
  picks a unique display name (3-16 of `[A-Za-z0-9_]`, unique ignoring case); Discord
  sign-ups pick one too instead of inheriting their Discord name. Anyone with an account
  may play.
- **Email** (Resend): sign-up stores a *pending* sign-up and mails a link. The account is
  created only when the link is followed, with the password from that sign-up, so nobody
  can pre-set a password for someone else's address. Sign-up and reset answer the same
  way whether or not an address has an account; sends happen in the background so timing
  doesn't leak it either.
- **Sessions:** a random bearer token returned in JSON, stored by the web client in
  `localStorage` (and in `user://` natively). The client lives on another site
  (`tfpp.github.io`), so there are no cookies; CORS allows exactly the configured origins,
  without credentials. Sessions last 30 days; a password reset revokes all of them.
- **Links back to the client** use URL fragments (`#verify=`, `#reset=`, `#forgot`,
  `#discord_code=`, `#auth_error=`), which browsers never send to servers. Session tokens
  never appear in URLs.
- **Discord:** `POST /api/auth/discord/start` takes `code_challenge = hex(sha256(verifier))`
  and returns Discord's authorize URL. Discord redirects to
  `/api/auth/discord/callback`, which sends the browser back to the client with a
  2-minute, one-time `#discord_code=`. The client redeems it with the verifier it kept, so
  only the browser that started the flow can. With a session and `link: true`, the same
  flow links Discord to the signed-in account.
- **Secrets** are files (`*_FILE` settings), never environment variables. Email or
  Discord switch themselves off (and `/api/health` says so) until their secrets exist.
- **Rate limits** (in memory, per IP from `CF-Connecting-IP` and per email or account)
  cover sign-up, login, reset, token redemption, name changes and tickets.
- **Storage:** SQLite (WAL) in `/data/api.db`. The bot keeps its own `bot.db`. Mapping
  Discord users to game accounts will need a read-only view of this one. Secrets in the database (sessions, email tokens, OAuth state,
  login codes) are stored as SHA-256 hashes. Migrations are append-only and tracked
  with `PRAGMA user_version`.

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /api/health` | | Liveness, plus whether email and Discord are enabled |
| `POST /api/auth/signup` | | `{email, password, display_name}` → 202, mails a link |
| `POST /api/auth/verify-email` | | `{token}` → session |
| `POST /api/auth/login` | | `{email, password}` → session |
| `POST /api/auth/logout` | bearer | Revokes the session |
| `POST /api/auth/password-reset/request` | | `{email}` → 202, mails a link |
| `POST /api/auth/password-reset/confirm` | | `{token, password}` → session |
| `POST /api/auth/discord/start` | optional | `{code_challenge, link}` → `{url}` |
| `GET /api/auth/discord/callback` | | Discord redirect target |
| `POST /api/auth/discord/exchange` | | `{code, code_verifier}` → session |
| `GET /api/me` | bearer | The account |
| `PUT /api/me/display-name` | bearer | `{display_name}`; 409 `name_taken` |
| `POST /api/join-ticket` | bearer | `{ticket, expires_at}`; 409 without a display name |

**Configuration** (environment): `API_ADDR` (`:8080`), `API_DB`, `API_PUBLIC_URL`
(`https://game.chrisbox.dev`, used for the Discord redirect URI), `API_CLIENT_URL`
(`https://tfpp.github.io/the-game/`), `API_ALLOWED_ORIGINS` (comma-separated),
`API_TRUST_CF_CONNECTING_IP`, `API_TICKET_KEY_FILE`, `DISCORD_CLIENT_ID`,
`DISCORD_CLIENT_SECRET_FILE`, `RESEND_API_KEY_FILE`, `MAIL_FROM`. For local development,
`API_DEV_LOG_MAIL=true` logs emails (with their links) instead of sending them.

### Joining a game

1. The client calls `POST /api/join-ticket` and gets a 60-second ticket:
   `"v1." + base64(json) + "." + base64(HMAC-SHA256(key, "v1." + base64(json)))`, where
   the JSON is `{"aid", "name", "exp", "nonce"}`. HMAC rather than Ed25519 because Godot's
   `Crypto` can't verify Ed25519; the API and game server share a key file on one host.
2. The client connects and presents the ticket through SceneMultiplayer's auth handshake
   (`send_auth`), before it counts as connected.
3. The server (`core/net/network.gd`, `core/net/join_ticket.gd`) checks the signature,
   expiry and lifetime, and rejects reused nonces. On success it completes the handshake,
   so `peer_connected` means "authenticated", and the player spawns with the account's
   display name. Otherwise it sends the reason and drops the peer; silent peers time out
   after 5 seconds. A second connection for the same account replaces the first.

**Version check.** The client's auth message is `{"version", "ticket"}`, and the server
refuses any build but its own before looking at the ticket (so the ticket isn't spent).
The version is the git commit: `pages.yml` and `server-image.yml` pass `BUILD_VERSION`
(the commit SHA) to `scripts/export.sh`, which bakes it into a generated
`res://build_info.gd`. Unexported runs report `dev` and match each other;
`--build-version=X` overrides it for tests. A refused web client explains the mismatch
and offers **Reload page**. The HUD's top-left corner shows the release version
(`application/config/version` in `project.godot`, bumped by hand at milestones) and the
short commit hash; the top-right corner shows the player count and connection state.

Because both artifacts come from the same commit, **the server must be deployed right
after each merge that changes `game/`**: until then, freshly loaded Pages clients are
turned away with the mismatch message.

Unauthenticated peers get no RPCs, spawns or replication. A shared test vector in
`api/internal/ticket/ticket_test.go` and `game/tests/unit/test_join_ticket.gd` keeps the
Go signer and the GDScript verifier in step.

**Server flags:** `--ticket-key-file=PATH` (the server refuses to start without a key), or
`--dev-insecure-auth` for local tests, which also accepts unsigned `dev:<name>` tickets.
**Client flags:** `--ticket=...`, or `--dev-insecure-auth [--name=Bob]`. Otherwise a
client with a server configured (the web default) shows the login screen
(`ui/login/`) over the offline room. `--api=` / `?api=` override the API URL
(`game/network/api_url`).

## Agent pipeline

1. `/feature <text>` in Discord. The bot (`bot/`, details in `bot/README.md`) checks the
   requester role and the per-user limit. It then creates a GitHub issue through its GitHub
   App, ending in a `Requested-by:` trailer, and opens a thread. If the concurrency cap is
   reached, the request waits in line and starts when a run finishes.
2. The bot dispatches `agent.yml` with a `request_id`, which the run name echoes. On
   GitHub, a maintainer can also add the `agent` label or comment `/agent` (details in
   `harness/README.md`). `agent.yml` runs three jobs:
   - **gate** (`harness/gate.sh`) accepts only senders with write access or bots listed
     in `AGENT_TRUSTED_BOTS`.
   - **agent** runs `harness/run.sh --agent claude|codex|pi --mode implement|revise|resolve-conflicts`
     with the model credential and no write token.
   - **publish** (`harness/publish.sh`) runs from the default branch with an App token.
3. The agent works on `agent/<issue>-<slug>`. `run.sh` re-runs `harness/verify.sh` after
   it and sends failures back (3 attempts by default), then commits and bundles the result.
   `publish.sh` pushes the bundle without force and opens the PR with the App token, so CI
   triggers.
   - The App has no Workflows permission, so agents can't change `.github/workflows/`.
   - PRs touching `CODEOWNERS` paths are flagged.
   - Without our own App, publish falls back to the installed Claude GitHub App's token,
     through the OIDC exchange `claude-code-action` uses.
4. The run comments on the issue or PR with the PR link, or with the failing verify output.
   The App's webhooks (`issue_comment`, `workflow_run`, `pull_request`) bring those
   comments, CI results on the agent branch, and the merge or close back to the thread.
   A reconcile loop polls while runs are active, in case a webhook is missed.
5. `/revise <changes>` in the thread (or `/agent <feedback>` on the PR) starts a `revise`
   run. `/agent resolve-conflicts` merges `main` in and resolves any conflicts.

**Agents:** Claude Code runs on GitHub-hosted runners using `CLAUDE_CODE_OAUTH_TOKEN`
(from `claude setup-token`). Codex and pi need persisted `auth.json` logins, so they run on
a self-hosted, ephemeral runner on the homelab.

## Merging

Approvals come from Discord, and a single coordinator in the bot applies them in order
(details in `bot/README.md`). `main` has no branch protection; the coordinator is the
gate.
- When CI passes, the thread offers **Approve & merge** (or `/approve`) to a trusted
  Discord role. The approval is pinned to the PR's head SHA; any other push voids it.
- The coordinator takes one PR at a time:
  1. Re-check the head SHA.
  2. If the branch is behind main, update it on GitHub's side and wait for CI.
  3. Squash-merge with an expected `sha`.
- **Conflicts:** the bot starts the agent in `resolve-conflicts` mode, and the new SHA
  needs re-approval.
- **After every change to main:** the bot re-checks the other open PRs, warns their
  threads about new conflicts and has the agent resolve them.
- `/queue` shows the agent runs or the merge queue.
- **Human-only paths:** PRs touching paths listed in `CODEOWNERS` (`.github/`, `harness/`,
  `bot/`, `api/`, the core feature loader, movement and net, `main.tscn`, `project.godot`)
  cannot be approved from Discord.

**Conflict avoidance:** each feature lives in `game/features/<name>/` and self-registers:
the game instances every `features/<name>/feature.tscn` under `Game/Features` at startup
(`core/features/feature_loader.gd`, see `game/AGENTS.md`). Parallel PRs therefore don't
touch shared scenes and rarely touch the same files.

## Deploy

| Artifact | Built by | Runs on |
|---|---|---|
| Web client | `pages.yml` (Godot web export) | GitHub Pages |
| Dedicated server | `server-image.yml` → `ghcr.io/tfpp/the-game-server` | Homelab VM (docker compose, deployed from `~/code/homelab`) |
| API | `api-image.yml` → `ghcr.io/tfpp/the-game-api` | Homelab VM, same compose project |
| bot | `bot-image.yml` → `ghcr.io/tfpp/the-game-bot` | Homelab VM, same compose project; webhooks at `game.chrisbox.dev/bot/github` |

The client and server must run the same code, and the join handshake enforces it (see
"Version check"). Once `pages.yml` and `server-image.yml` have both succeeded for the same
`main` commit, the bot asks the homelab to deploy that server image (a request file that
a host service acts on; see `bot/README.md`), then tells the merged PRs' threads they're
live. The API and the bot are still deployed by hand.

## Milestones

1. **v0.1:** empty room, Source movement, first-person view, Pages deploy, dedicated
   server, CI. *(done in this scaffold)*
2. **v0.2:** deploy the server to the homelab behind NPM, and have the web client default
   to `wss://game.chrisbox.dev`.
3. **v0.3:** `api/` accounts (Discord plus email/password) and join tickets.
4. **v0.4:** `harness/` plus `agent.yml` (Claude), triggered by label/comment/dispatch.
5. **v0.5:** `bot/` MVP (`/feature`, threads, status), then revise loops.
6. **v0.6:** Discord approvals, the merge coordinator, `/queue`, self-registering
   features and automatic server deploys; later, a homelab runner with Codex/pi.
