# Phase 1 polish plan

This is the task list for turning Casino Royale into a semi-polished minimum viable
game: a safe Golden Crown hub, a working elevator into instanced slum zones, quick
loot runs, selling and buying. It refines the Phase 1 checklist in
[project/phases.md](project/phases.md) using the state of `main` at `fb223120`
(2026-10-02).

Each task is sized for one agent and one pull request. Tasks list their
dependencies; anything without one can start immediately. Follow `AGENTS.md`,
`game/AGENTS.md`, the [lore](design/lore.md) and [gameplay](design/gameplay.md)
documents, and tick a box here (and in `project/phases.md` where it matches) in the
PR that finishes it.

## Current state (audit)

Found by reading the feature READMEs and code and rendering the live main scene
under Xvfb (casino floor, elevator wall, slum gate, pawn shop, both slum arrivals).

**Works today**

- The Golden Crown: gaming floor with slots, roulette, bar, patrons, mariachi band,
  food court, pawn shop and many side rooms (`features/casino_hub`, `annex`, ...).
- Slum excursions: the south lobby **gate** (`features/slum_runs/slum_gate.gd`)
  sends everyone to one shared excursion, picked at random from
  `SlumArrivalPoint`s: the old P1–P3 parking garage or the Rain Alleys.
- Searchable loot containers (`features/loot`), six valuables with
  `sale_value_cents` (`features/holdables/items`), the pawn counter that buys them
  (`slum_runs/loot_fence.gd`), the gun wall and gun machine to buy weapons,
  server-authoritative combat and death drops of valuables.
- Garage enemies in three tiers (`features/garage_enemies`), in both the old garage
  and the B1–B5 basement garage (`features/procedural_rooms`).
- Room streaming per client (`features/room_visibility`) and render isolation for
  the garages (`RenderZone`).

**Gaps against the design**

- The casino **elevator** (`features/elevator`) only opens and closes. Travel is
  disabled, there is no capacity limit and no weight light. The slum gate does the
  elevator's job instead.
- Excursions are **not instanced**: every group shares one slum, and all zones live
  in one world, so network updates go to everyone everywhere.
- The intended garage (five floors around an open central shaft, start at the top,
  harder deeper) does not exist. There are two partial garages: the old P1–P3
  mock-up (scheduled for deletion in `docs/code-cleanup.md`) and B1–B5, reached only
  by a dev teleporter, the operations-garage van or a service lift.
- **The casino is not a safe zone**: nothing stops PvP damage or firing inside it.
- Starting flow: new players spawn in the operations garage (`starter_room`), not
  the Crown, and the first frame is a full-screen Esc menu over the scene.
- **Signs are floating text**: about 110 `Label3D` nodes across 38 scenes. The
  worst offenders are `casino_hub/interior.tscn` (15), `parking_garage/garage.tscn`
  (6), `kebab_shop/shop_view.tscn` (6), `annex/easter_eggs.tscn` (6),
  `hotel_props/interior.tscn` (5) and `street_district/feature.tscn` (4). The
  elevator's "ELEVATOR" sign and floor indicators, the pawn shop price tags and the
  slum gate are also plain labels.
- Slum arrivals are very dark and give no orientation; the garage arrival shows an
  almost empty black frame.
- Many dev/test destinations are reachable from normal play (dev room portals,
  street casino portal, procedural garage teleporter, GPS entries).

## Milestone A: elevator and instanced zones

### A1. Zone instance registry (server)
- [x] Add a server-owned `ZoneInstances` service (new feature, e.g.
  `features/zone_instances/`) that creates an instance id for a group, records which
  peers and which slum scene belong to it, and frees it when the last member leaves,
  dies out or disconnects.
- Each slum scene is instantiated once per instance at its own far-apart world
  offset (e.g. x = 4000 × instance index) so groups never see or touch each other.
- Shared zones (Crown, its rooms, gnome doors, starter garage) stay single and are
  not managed by this service.
- Tests: two groups get two instances; leaving frees; disconnect frees; offline
  single peer works.
- Touches only new feature code; explain any need for `game/core/net/` in the PR.
- Completed in #443: `features/zone_instances` `ZoneRegistry` tracks members, slum,
  far-apart slots (x = 4000 × slot) and frees on leave/death/disconnect; the slum gate
  records its run there. Scene copies at the offset are not placed yet (A3/A4).

### A2. Per-zone network relevance (depends on A1)
- [x] Send player, enemy and loot replication only to peers in the same zone
  instance (MultiplayerSynchronizer visibility filters / `set_visibility_for`).
  Chat stays global.
- Late joiners of an instance get its current state; peers in other instances get
  nothing.
- This touches `game/core/net/` or the player scene: needs human review, say so.
- Verified on the Phase 1 branch: transport tests mutate real player movement,
  enemy state and searched-container contents and check member delivery, outsider
  exclusion and late-entry state. Separate transport checks cover private item,
  projectile, damage and death events, plus global chat. Player identities remain
  available for the roster and owner RPCs; unrelated peers receive no movement
  and their hidden player collider is disabled. Core networking/player changes
  require human review in the PR.

### A3. Load only the active zone on clients (depends on A1)
- [x] Clients load the slum scene of their own instance only and free it on return;
  the server keeps the instances it owns. Reuse `room_visibility` / `StreamedRoom`
  rather than a second loader. Noclipping out of a slum must not show the casino.
- Verified on the Phase 1 branch: transport tests check exclusive map spawning,
  free-on-return and member retention. The WebSocket cab round trip checks rider
  transfers, private-map cleanup and the outsider remaining in the shared hub.
  Crown cosmetic unloading and its assertions are deferred to Part 2. The private
  camera mask stays on the instance layer outside its bounds, excluding the Crown;
  saved-map tests check server floor collision after client visuals unload.

### A4. Elevator travel to a random slum (depends on A1)
- [x] Enable travel in `features/elevator/elevator_cab.gd`: after the doors close
  with riders inside, the server asks `ZoneInstances` for a new instance with a
  random registered `SlumArrivalPoint` (`dev_elevator/slum_destinations.gd`) and
  moves exactly the riders there together, keeping cab-relative positions.
- Add a cab-style arrival (doors open onto the slum) and a return elevator in each
  slum that brings its riders back to the Crown cab.
- Keep the existing door, hall-call and obstruction behavior and tests.
- Verified on the Phase 1 branch: the server collects the cab's occupants after
  closure, selects a registered destination and waits for owning-client readiness.
  The production WebSocket test sends two riders together, keeps the outsider in
  the hub and verifies their return positions. Offline cab tests also check yaw
  and pitch preservation; existing door, obstruction, capacity and late-join tests
  pass in the full suite. Garage and alley instances both construct return cabs.

### A5. Capacity limit and weight light (depends on nothing)
- [x] Count riders inside the cab volume on the server. With more than 4 riders the
  doors refuse to close and a red **OVER CAPACITY** lamp (a modeled lamp with an
  emissive lens, not a Label3D) lights inside and above the hall doors. Replicate
  the lamp state for late joiners. Test 4 vs 5 riders and riders leaving.

### A6. Retire the slum gate (depends on A4)
- [x] Once the elevator travels, remove the south lobby gate as an entrance (or turn
  it into scenery), update `slum_runs` README, GPS and tests so the elevator is the
  only way into the slums.
- The gate is collision scenery without an interaction script. Normal van and
  service-lift garage bypasses are locked behind cheats; GPS hints point to the
  Crown elevator. The gate regression checks its non-interactive state, while the
  production cab test verifies departure and return through the elevators.

## Milestone B: the parking garage zone

### B1. Choose one garage and delete the other
- [x] Make the B1–B5 procedural garage the parking garage destination: give it a
  `SlumArrivalPoint` and a return elevator, and remove its dev teleporter, van
  route and service-lift entrance from normal play. Then delete the old P1–P3
  mock-up as listed in `docs/code-cleanup.md`, moving the tests that relied on it.
- The old loaded map is deleted; shared car/door/light utilities remain. The
  five-floor registration and top return cab are checked by destination and
  excursion tests. Van, developer portal and service-lift bypasses require cheats.

### B2. Central open shaft and top-down progression (depends on B1)
- [x] Rework the garage per `docs/design/zones/slums/parking-garage.md`: at least
  five floors around an open shaft to the sky, arrival on the top floor, darker and
  wetter floors further down, ramps and jumpable gaps between floors. Build with
  GridMap tiles. Keep layout tests for clear ramps and arrival.
- Five saved level tiles preserve the sky-open shaft and top arrival. Actual
  controller checks traverse all four ramps and stairways both ways, jump each
  shortcut and drop only one storey. B1 is dry; B2–B5 increase puddle count and
  area. Lower floors reduce tube energy and increase failures; rendered captures
  review all five water depths and the four shortcut landings.

### B3. Spawn enemies at random pre-placed points (depends on B1)
- [x] Replace fixed enemy placement with `EnemySpawnPoint` markers per floor; each
  instance picks a random subset at start. Deeper floors have more and stronger
  spawns. Server-only rolls, deterministic in tests with a seeded RNG.
- Authored markers feed a server-generated plan sent as spawn data. Seeded tests
  check distinct points, repeatability, variation between seeds and increasing
  encounter strength. Populations are 2/3/4/4/6; the B1 arrival lane stays clear.

### B4. Floor-scaled loot (depends on B1)
- [x] Give each floor its own `LootTable` so common cheap items dominate the top and
  rare valuables appear deeper. Containers reset per instance.
- Independent tables and seeded containers yield increasing expected value per
  crate: $2.44/$3.82/$6.02/$16.48/$23.78. Plan tests check the weights and table
  isolation; excursion tests check a new run gets fresh containers.

### B5. Difficulty pass (depends on B2–B4)
- [x] Tune enemy health, damage, reaction time and counts so a solo player can clear
  the top floor with a pistol and the bottom floor needs a better gun or a group.
  Document the numbers in the garage_enemies README.
- The controlled real-map exercise clears B1 with two pistol shots and 100 HP.
  B5 has one knifer and five gunmen, with 1.5x damage and 0.75x windup; its exposed
  pistol run dies after four enemies, while the M4A4 clears all six at 100 HP.
  The fixture observes actual death events, weapon cooldowns and reloads. Earlier
  floors and base profiles are unchanged; numbers and fixture limitations are in
  the enemy README. Enemy, plan and excursion regressions pass 34 tests / 328
  assertions. This proves the stronger-weapon route, not impossibility of a
  skilled movement-based pistol run.

## Milestone C: loot and economy

### C1. Five loot tiers
- [x] Settle on five valuables with clear rarity and prices (e.g. scrap, stolen
  wallet, electronics, watch, jewelry; cash bundle as money). Show rarity color in
  the inventory icon and pickup prompt. Keep the pawn counter as the sale path
  (Phase 1 in `phases.md` asked for direct money; selling already works, so keep it
  and note the decision).
- Completed in #430: retain the existing $1/$3/$7/$10/$15 prices, add gray/green/
  blue/purple/gold common-to-legendary metadata, icon borders and readable
  rarity/price details. Cash bundles remain separate $5 monetary loot redeemed
  at the pawn counter; saved cash items and sale/death-drop rules are preserved.
  Garage/alley weights already decline by valuable tier; floor scaling stays B4.

### C2. Pickup feedback
- [x] When a player takes loot, show a short toast "Picked up <name> ($<value>)" and
  play a pickup sound via `GameAudio.play_ui()`.
- Completed in #432: the server sends the taker an owner-only `picked_up` event
  after a stash claim; `features/loot/loot_toast.gd` shows the rarity-colored toast.
  The existing owner-only `pickup` cue from `PlayerInventory` provides the sound.

### C3. Clear death penalty messaging
- [x] On death in a slum, tell the player what was dropped and that weapons were
  kept. Respawn back in the Crown (not the operations garage).
- Completed in #466: after the respawn, `slum_runs` sends the victim an owner-only
  message naming each dropped valuable and confirming weapons were kept. Combat
  already respawns at the Crown `player_spawn` marker (#436).

## Milestone D: safe casino

### D1. No combat in the Crown
- [x] Server rejects `apply_damage` between players and from enemies while the
  victim is inside a shared casino zone; weapons cannot fire there (lowered pose).
  Shooting-gallery targets and other `killable` toys keep working. Tests for PvP
  blocked inside and allowed in a slum.
- Completed in #434: `features/safe_zone` boxes cover the Crown, annex, lounge,
  cellar and hotel wing (not the B1–B5 garage below). Combat ignores damage between
  players when either is inside; held and gun-machine guns refuse to fire there.
  No lowered pose yet. Enemies never reach the Crown, and their damage is
  self-attributed, so the check is PvP-only.

### D2. Spawn and first minute in the Crown
- [x] Spawn new players in the Crown near the elevator, not in the operations
  garage, and don't open the Esc menu over the scene on first load (show a small
  "Click to play" prompt instead). Keep the operations garage reachable by door.
- Completed in #436: `features/crown_spawn` supplies the only `player_spawn` marker at
  (0, 1, -16), in front of the elevator inside the safe zone; the login screen shows a
  small "Click to play" prompt until the player has played once.

### D3. Hide dev and test content
- [x] Remove dev room portals, the street-casino portal, the procedural garage
  teleporter and dev elevator entries from GPS and from walkable reach in normal
  builds. Keep them behind `sv_cheats` / noclip.
- Completed in #438: `features/dev_access` `DevGate` hides and server-locks the old
  casino and street casino doors on the promenade and the street district, hotel props
  and procedural garage teleporters in the dev room until `sv_cheats 1`; GPS hides
  `dev_only` places and skips locked doors. The dev room booth stays open because the
  lounge, cellar, hotel wing and apartments are still entered from it, and the van
  routes stay for B1. The dev elevator pad already sat in a sealed room.

## Milestone E: signs as real models

Use `docs/design/prop-generation.md`: textures at most 128×128, scaled to size.
Replace one area per task so each PR stays reviewable.

### E1. Shared sign kit
- [x] Add a small `features/signage/` kit: backing board, brass/neon frame, wall
  bracket and hanging variants, with letters baked into a small texture or built
  from a shared letter-tile atlas (instanced quads on a mesh, no `Label3D`). Include
  a test that every sign has a backing mesh and sits flush on its wall.
- Completed in #441: `SignBoard` (`features/signage/sign_board.tscn`) builds a
  backing box, frame bars and flush/bracket/hanging mounts in brass or neon; letters
  are quads into the runtime-painted 64×64 `SignLetterAtlas`. No signs replaced yet.

### E2. Casino signs (depends on E1)
- [x] Replace the 15 `Label3D` signs in `casino_hub/interior.tscn` (THE GOLDEN CROWN,
  room names, directional sign) and the elevator's sign and floor indicators.
- Completed in #495: all 15 interior labels and the elevator `Sign`, `Indicator` and
  `CabIndicator` are flush brass `SignBoard`s at the old transforms; the atlas gained `<` `>`.

### E3. Shop and price signs (depends on E1)
- [x] Pawn shop (`pawn_shop`, `wall_gun.gd` price tags), kebab shop, food court
  stands, bar, gun machine and slot cabinet labels become modeled plaques/tags.
- Fixed captions use the shared modeled sign kit; shop/slot and main-scene bar
  captures review scale and attachment. The remaining runtime labels are changing
  status/stakes, character names and dialogue, listed in the kit README.

### E4. Remaining world signs (depends on E1)
- [x] Annex, hotel, apartments, room doors, slum alley, garage and street district.
  Keep `Label3D` only for dynamic text that must change at runtime (names over
  heads, live counters), and list those exceptions in the kit README.
- A source audit of these runtime areas finds no remaining fixed `Label3D` signs.
  Annex plaque letters are saved atlas meshes; the other fixed signs use mounted
  `SignBoard`s. Remaining example-lab labels and authoring capture tools are
  standalone development fixtures, outside runtime world signs.

## Milestone F: presentation polish

### F1. Slum readability
- [x] Brighten arrivals enough to orient (a working light near each arrival and
  return elevator, visible landmark), keeping darkness elsewhere. Check that enemies
  are readable per the gameplay doc.
- Actual main captures review both arrivals and return cabs, plus enemy silhouettes
  at five and twelve metres. Garage light pools, floor plaques and the central
  shaft orient arrivals; the alley return has a working lamp on a modeled bracket.

### F2. Elevator ride presentation (depends on A4)
- [x] Short (≤ 2 s) ride: hum, shake, floor indicator ticking, chime, doors open.
  No loading screen if the zone is already loaded.
- Verified on the Phase 1 branch: the production WebSocket round-trip test returns
  two riders to a preloaded Crown in 1.088 seconds, retaining cab-relative poses.
  Cab tests cover indicator progression, local camera shake/restoration and hum
  shutdown; arrival opens the doors and sends the existing arrival-bell event.

### F3. HUD tidy-up
- [x] Review overlapping HUD (version badge, radar, hotbar labels, money, HP) on a
  phone-sized screen; hide the hotbar's "Hand" and slot labels when empty.
- Actual main captures cover 360x780 and 780x360, empty and occupied inventories.
  The empty panel collapses; occupied slots keep the current theme and touch targets.
  Compact layouts retain main's sideways scrolling row. Touch controls, money,
  health and ammo remain separate. Radar
  remains desktop-only. Hotbar regression tests check empty-slot collapse.

### F4. Web performance check (deferred to Part 2)
- [ ] Profile the web build in the Crown and in a slum; keep dynamic lights and
  per-frame work within budget. Record numbers in `docs/profiling-animation.md` or a
  new profiling note.
- First pass recorded in [profiling-web.md](profiling-web.md): light/process census
  of the Crown and both slum instances and a GUT light-budget guard. No web export
  templates exist on CI, so the browser profile itself is still to do.

## Suggested order

A5, C1, C2, D1, D2, D3, E1 can start in parallel. Then A1 → A2/A3/A4 → A6, F2;
B1 → B2/B3/B4 → B5; E1 → E2/E3/E4; F1 and F3 any time.
