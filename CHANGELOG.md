# Changelog

Every notable change, newest first. `edge` is what's on `main` but not released yet.

**In every pull request with a change players, operators or contributors would notice, add
a bullet to the end of `## [edge]`:** imperative, one line per change where possible, no
version. Releases are cut by hand (the `release` workflow): it moves `edge` into a section
for the new version. See "Versioning" in [docs/architecture.md](docs/architecture.md).
- Add Zohran Mamdani as a casino patron who strolls the gaming floor beside the slot machines
  with a floating name tag.

## [edge]

- Brand the game Casino Royale and dress the Rain Alleys with original vertex-authored OBJ dumpsters, boarded facades, fire escapes, lamps and fence wire.
- Replace the garage's box-shaped wrecks with original low polygon OBJ sedans, preserving varied paint, missing hoods, collision and searchable loot.
- Brighten the slums and garage at night, correct car mesh faces, open wrecked car boots when searched, and let players drag shared stash items into backpack slots.

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
- Reduce rendering work by culling distant rooms, batching frog detail meshes, disabling
  whole-world sun shadows and playing garage ambience only when a player is nearby.
- Keep offline players on the leaderboard and remember signed-in scores across reconnects
  and server restarts.
- Press ~ for a Source-style settings console with autocomplete and command history;
  use sv_cheats 1 to unlock noclip and sv_cheats 0 to disable it for everyone.
- Stop casino benches and props from sliding when you turn the camera, and stop guns,
  gnomes and other plain-coloured props from rendering almost black.
- Add four walking casino patrons to the gaming floor: punch them to stagger them, knock
  them out into a limp ragdoll, and watch them get back up and carry on.
- Pray at the Kaaba with Use: a chant plays and each prayer adds a stacking blessing (up
  to 5) that gives your losing slot spins another roll until you win.
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
- Rebuild the hotel wing as a four-floor hotel around a skylit central atrium, with
  switchback ramps, gallery railings and guest rooms on every upper floor.

- Join procedural wall corners with mitred trim and one shared pillar; connect raised rooms with level landings, ramps capped at 10 degrees and walkable stairs.
- Connect the four-floor atrium as a separate classic-hotel wing, with gentle ramps, shared guest-room doors and GPS routing between wings.
- Add synchronized swinging room doors and a Reading Room key for the locked study two stair flights up.
- Keep stairs between 30 and 37 degrees, with level landings and ramps capped at 10 degrees.
- Use live hotel lighting and fast geometry builds during development, with no required lightmap bake.
- Add reusable networked entity and player interaction components; migrate doors and pickups and document the shared workflow for contributors.
- Add three reusable hotel kits and a plain concrete service kit, with nearby hotels connected by a branching sewer network, junctions, an alternate loop and three climbable ladders.
- Space corridor lights, seal window views with day/night sky backdrops, and replace door lock labels with Kenney door and key sounds.
- Add thirteen hotel skylights, reusable ceiling pieces for every room kit, and broad live daylight with readable night lighting.
- Add the atrium wing to GPS, keep bird simulation server-authoritative after joining, and clean up Windows multiplayer test processes reliably.
- Use Godot for repository snapshots and multiplayer test runners; remove Python installation from export jobs.
- Handle container checkout ownership and empty Git output when generating export snapshots, and report the underlying Git error on failure.
- Compress the preview's game pack alongside the WebAssembly engine to fit the host's per-file size limit.
- Open the Golden Crown's slum gate for shared trips to the rain alleys or parking garage; drop carried valuables on slum deaths and sell survivors' loot into the persistent casino wallet.
- Add a fenced, rain-soaked alley map with searchable dumpsters, boarded buildings, puddles and failing streetlights.
- Reduce scene draw calls by batching frog details, clipping other rooms from each player's server-assigned view, removing the full-world sun shadow pass, and playing rain ambience only near players.
- Keep hotel rooms, stairs, sewers and the atrium readable at night and on phones
  with steady indoor ambient lighting.
- Remove the Adventure Arcade, its computer games and Python authoring and probe scripts.
- Shoot salon guests, dealers, the bartender and the apartment clerk with any gun;
  they return after six seconds.
- Enter VR from the Quest / WebXR menu in Quest Browser with headset look, stick
  movement, snap turning, jump and nearby object interaction.
- Knock out Mamdani instead of killing him; he wakes up a few seconds later. Press Use
  near him for $10 of subway fare, once an hour.
- Add a FIRE button to the touch controls and let the controller's right trigger attack
  and shoot, alongside the existing right bumper.
- Explore the annex wings to find six hidden joke plaques with no extra controls.
- Meet Donald Trump following the mayor by the slots; use E to pay him $100.
- Fix the web client crashing (`null function`) and getting stuck on "Joining…" when
  joining a server after signing in.
- Move feature textures, models and audio into `game/assets/<feature>/`.
- Add pixel-art roulette table textures (wheel, betting layout, felt, rail, apron) under
  `game/assets/roulette/textures/`.
- Celebrate winning slot machine spins with fireworks over the cabinet and gold coins
  spilling from the tray; both grow with the size of the prize.

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
- Show the agent's reasoning effort next to its model in PR descriptions, ðŸ¤– comments and Discord notifications.

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
