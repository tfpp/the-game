# Changelog

Every notable change, newest first. `edge` is what's on `main` but not released yet.

**In every pull request with a change players, operators or contributors would notice, add
a bullet to the end of `## [edge]`:** imperative, one line per change where possible, no
version. Releases are cut by hand (the `release` workflow): it moves `edge` into a section
for the new version. See "Versioning" in [docs/architecture.md](docs/architecture.md).

## [edge]

- Add an F-toggle flashlight with shared beams and a rebindable Controls entry.
- Connect all gnome holes through enterable tunnels with four-times running speed and labeled exits.
- Hang a BREAKING NEWS screen over the casino floor that scrolls top headlines from
  TheNewsAPI; servers set `THENEWSAPI_TOKEN` to enable it.
- Give coding agents a step-by-step implement workflow, playbooks for common kinds of
  features, a checklist of problems `verify.sh` can't catch, exact changelog placement,
  and clearer revise and merge-conflict instructions.
- Restyle the casino with 128-pixel world textures, nearest mipmap filtering, matte vertex lighting, subtle surface dithering and texture distortion, and angular adult avatars.
- Reduce casino prop geometry and batch static decoration; mobile uses a 540-pixel 3D height budget without shadows or MSAA while keeping the HUD sharp.

- Build a furnished casino salon with generated burgundy carpet and felt, low-poly adult patrons, a bottle-lined bar, framed paintings, warm lighting and a walkable upstairs gallery; keep all eight slots accessible in one bank and include the new geometry on the desktop radar.

- Remodel the card tables, chairs and salon patrons with curved upholstery, shaped supports and fitted anatomy; use a shared 128px surface atlas and texture previously plain model materials.
- Fetch news headlines only on the server, every 15 minutes, and cache them there so
  clients never call TheNewsAPI and restarts reuse recent headlines.
- Make phones and tablets run faster: render fewer 3D pixels, keep two nearby lights, hide
  small props past 40 metres and cap physics catch-up on slow frames.
- Keep offline players on the leaderboard and remember signed-in scores across reconnects
  and server restarts.
- Press ~ for a Source-style settings console with autocomplete and command history;
  use sv_cheats 1 to unlock noclip and sv_cheats 0 to disable it for everyone.
- Play Super Turbo Turkey Puncher 3 on two mouse-operated computers in the Adventure
  Arcade, with shared screens, timed rounds and cabinet high scores.
- Stop casino benches and props from sliding when you turn the camera, and stop guns,
  gnomes and other plain-coloured props from rendering almost black.
- Add four walking casino patrons to the gaming floor: punch them to stagger them, knock
  them out into a limp ragdoll, and watch them get back up and carry on.
- Pray at the Kaaba with Use: a chant plays and each prayer adds a stacking blessing (up
  to 5) that gives your losing slot spins another roll until you win.
- Enter the Adventure Arcade without a long freeze: cabinets now show an attract screen
  and only load and start their game when someone uses them.
- Find gnome holes as doggy doors on the outer walls: gnomes now come out one by one,
  wander their own routes around players, NPCs and frogs, and can be killed like frogs
  until their burrow next comes out.

- Add a JSON world-authoring tool that places rooms, connects hallways, and bakes chunked meshes, collision and room markers into saved Godot scenes.

- Add textured hotel architecture to the world builder: profiled mouldings, fluted columns, recessed panel doors, framed windows and independently adjustable room/hallway heights.

- Show a clouded daylight sky through procedural windows in the world-builder preview, with adjustable sky texture and heading.

- Connect a separate, streamed hotel wing to the casino south lobby with labelled two-way teleport doors.

- Map world-builder rooms and hallways on the radar using baked structural collision, including streamed and transformed scenes.

- Expand the generated hotel to six rooms and five corridors; add an offline UV2 lightmap bake with soft lamp shadows, diffuse bounces and additive flashlights.

- Compile lighting with the world-builder command and fix pillar joins, curved normals, lightmap detail and striped flashlight shadows.

- Replace the world-builder Blender pipeline with native Godot LightmapGI compilation, saved lightmaps and dynamic-object probes; keep normal exports independent of the baker.

- Reuse unchanged world-builder bakes using input and output content hashes; add `--rebake` and reduce pillars and light fittings to at most eight radial sides.

- Keep the hotel baked lighting below 1 MB in both saved and exported assets, and enforce the budget before publishing new bakes.
- Inspect the build's repository snapshot with read-only Git commands in the console;
  type git help to see the supported commands.
- Add a wandering bird that flies continuously between players and casino patrons.
- Add an Electron desktop app for the live website on Linux, macOS and Windows,
  with portable app packaging commands.
- Add a curl installer for the Electron desktop app on macOS, Linux and Windows Git Bash,
  with locked dependencies and safe rebuilds.
- Claim a free apartment at the Lily Apartments front desk in the south lobby, and
  take the express elevator to new ten-unit floors as more residents move in.
- Add a GPS phone: press P (or pick GPS in the Esc menu), search for a room, and follow the
  purple route on the radar and the direction banner, including through doors.

## [0.7.1](https://github.com/tfpp/the-game/releases/tag/v0.7.1) - 2026-09-28

- Stop the HUD version test from failing CI after every release.

## [0.7.0](https://github.com/tfpp/the-game/releases/tag/v0.7.0) - 2026-09-28

- Character Model (Esc menu) now picks a body, a head and a tail independently: a
  frog head or bird head, and a lizard, fin or fluffy tail, on any body (including
  the girl and penguin builds), so you can mix and match your own impossible
  creature.
- Add a day/night cycle: a full day repeats every 48 real-time minutes, with the sun
  swinging across the sky, the skybox fading between day and night, and ambient
  lighting dimming at night. It runs off the real-world clock, so it stays in sync
  for everyone without any extra networking.
- Rank connected players by wallet balance and show a swarm of flies over the poorest
  80% of them, rounded down; nobody is flagged with fewer than two connected wallets.
- Frogs jump twice as high by default now, with a new "Frog jump height" slider in
  Game settings (Esc > Settings > Game) to tune it further; they also bounce off walls
  at an oblique angle mid-hop instead of stopping dead, ribbit when shot, and there are
  now 12 of them instead of 6.
- Version releases by hand from the `release` workflow, which picks the patch, minor or
  major bump, tags it, publishes a GitHub Release and shows the version in the HUD.
- Keep this changelog, with an `edge` section rolled into each release.
- Group the in-game release notes (`L`) by version, showing the last 10 releases and what's
  new since the latest one.
- Announce each release in Discord once it is live, with its changelog notes, and each
  deploy's new edge changes as "New on edge".
- Add a Game settings page (Esc > Settings > Game) to tune jump height and frog hop rate
  for everyone in the world.
- Switch the UI to Inter (body), Exo 2 (headings), Barlow (buttons) and Orbitron (HUD
  readouts), and put the release notes on a light sheet with palette-matched headings.
- Deploy the accounts API automatically when its image is built, so API changes (like the
  wallet endpoint) no longer wait for a manual deploy.
- Add `/close` to the Discord bot: in a feature thread, it closes the feature's PR without
  merging and its issue as not planned.
- Close a Discord feature's issue automatically when the agent makes no changes for it.
- Show each agent run's token usage and estimated cost in its PR and in the Discord thread.
- Give the girl model a smaller collision hitbox and 15% less passive income.
- Add `/usage` to the Discord bot: it shows how much of Claude's 5-hour and weekly usage
  limits the agent has used, and when they reset.
- Add sprays: press T to spray a decal on the surface you're looking at, visible to
  everyone (placeholder image for now).
- Add 1960s brass wall sconces to the annex corridors and rooms, dim by day and
  glowing at night, so they no longer go pitch black after dark.
- Run Codex on GitHub-hosted Actions runners with a ChatGPT subscription login and the existing agent verification and PR publishing flow.
- Require a Claude or Codex harness choice for Discord `/feature` requests, preserve it for revisions and conflict fixes, and default to Opus 5.5 or GPT-6 Astra respectively with low reasoning.
- Include model, token usage and estimated API-equivalent cost in PR templates and Opened/Pushed Discord notifications, with readable PR-number links.
- Make the penguin-facing regression test independent of frame timing by checking its forward offset at fixed waddle phases.
- Show Claude and Codex subscription limits together in Discord `/usage`, with independent error handling and a read-only Codex login file.
- Add a Retry button to Discord messages about failed, cancelled or never-started `implement` and `revise` runs, so the requester can start the run again.
- Name cancelled, failed and skipped agent jobs in the "did not produce a change" comment, without listing unavailable model, token and cost fields.
- Post every bot message in Discord feature threads as a colour-coded embed (agent progress, CI, previews, approvals, merge queue, conflicts, merges and deploys), with model, shortened token count (such as 1.4M) and estimated cost as fields on agent notifications.
- Show the agent's reasoning effort next to its model in PR descriptions, 🤖 comments and Discord notifications.

- Add a Monkey Island demo arcade with a brass-trimmed cabinet and synchronized local emulation for every player.
- Autosave shared arcade progress, restore it after server restarts, and pause the demo when everyone disconnects.
- Play arcade audio from the cabinet, fading to silence at five metres.
- Add Sam & Max, Fate of Atlantis, Passport to Adventure and Day of the Tentacle demo cabinets, each with independent shared progress and sound.

- Play adventure cabinets directly on their 3D screens, look around while playing, and simplify the control deck by removing the joystick.

- Bring the arcade play view closer to the screen, keeping the cabinet edges visible and restoring the normal view on exit.

- Simplify arcade play to one leave button, automatically taking controls when a cabinet is free.

- Add doors that link rooms, starting with a lounge and a wine cellar behind a booth in the south lobby. Each room is its own scene, which clients load only while they're inside and dedicated servers never load.

- Move the adventure cabinets into a dedicated room reached from the casino, unload emulators outside it, and pause shared progress while the room is empty.
- Reduce arcade frame delivery delay and fix sound dropping out after delayed updates while preserving positional audio and the five-metre cutoff.
- Show only the weekly Codex limit in Discord `/usage`, hiding the 5-hour window and per-model limits such as `gpt-reserve`.

- Open blocked annex junctions, restore solid room floors and walls, and clear the west petting-parlor exit.
- Add a desktop-only top-right radar with a roof-free floor plan, facing arrow and nearby player markers.

- Give the casino generated carpet, wallpaper and walnut textures with PBR finishes, plus detailed stools, benches, planters and chandeliers.
- Rebuild the slots with bevelled cabinets, animated printed reels, metal trim, buttons and coin trays while preserving payouts and multiplayer state.
- Size the shooting-gallery entrance sign to fit its doorway instead of floating across the casino view.
- Search wrecked cars in the parking garage for randomized loot (wallets, watches,
  jewelry, electronics, scrap, cash bundles) through a reusable, server-authoritative
  loot container and data-driven loot tables that can be reset between visits.

## [0.6.0](https://github.com/tfpp/the-game/releases/tag/v0.6.0) - 2026-09-28

Versioning starts here, matching milestones v0.1 to v0.6. Highlights so far:

- Source-style movement multiplayer on the web, with a dedicated server on the homelab.
- Accounts with Discord or email sign-in, and join tickets checked by the game server.
- Discord bot: `/feature` and `/revise` agent runs, approvals, a merge queue and automatic server deploys.
- Money: a persisted wallet, income over time, coins, a slot machine, a roulette table and a gun machine.
- Weapons and combat: an AWP, SMG and shotgun, a hotbar, recoil and item drops.
- The world: an expanded map with connected rooms, the Gilded Lily casino, an elevator, a pond,
  trampolines, the NYC ferry, frogs, gnomes, a penguin, a Kaaba landmark and a soccer ball.
- Chat, push-to-talk voice chat, a third-person camera, noclip, a Settings menu with rebindable
  controls and audio, and an in-game changelog.
