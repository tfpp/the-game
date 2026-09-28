## Task: implement a feature request

Build the request at the end of this prompt (`## Request (issue #N)` and any discussion
under it) as a new change on `{{BRANCH}}`. Players write these in Discord, often as one
informal line. They leave out what they take for granted: that the feature works for
everyone on the server, looks right, and fits the rest of the game. Build that, not just
the literal words.

### Steps

1. **Understand the request.** Note the outcome players should see, every explicit detail
   (keys, numbers, names, places, looks) and the details they would assume. Decide open
   questions yourself and list those decisions in the summary.
2. **Investigate, even for a small request.** Rework that reviewers asked for has often
   come from skipping this.
   - Search `game/` for the behavior and its nouns (`rg -i`), and read the READMEs of
     candidate owners (`rg --files game/features | rg README`).
   - Read the owner's scripts, scenes and tests, and the reference features for this kind
     of request under "Playbooks". Follow their patterns.
   - Before choosing a key, check `game/core/input/controls.gd`,
     `game/features/control_scheme/input_bindings.gd`, `rg KEY_ game/features` and the
     open PRs, so you don't take a key that another feature uses.
   - Before placing anything in the world, read the layout of that area (see "World
     content" under "Playbooks").
3. **Record the plan.** Write the Integration notes (Systems inspected, Reuse decision) in
   `{{OUT}}/summary.md` before you edit code, and keep them current.
4. **Design the multiplayer behavior.** Decide which server node owns each piece of shared
   state, how clients ask to change it, and how it replicates. Decide what late joiners
   see, and what happens on disconnects, respawns, two players acting at once, and offline
   play (a server with a single peer).
5. **Build and test.** Work in the feature's directory, following `game/AGENTS.md` and the
   playbook. Write tests as you go (see "Tests") and run them with the targeted commands
   from "Checking your work".
6. **Document.** Give a new system or public interface a short README in its feature
   directory, update the README of any feature whose behavior or interface you change, and
   add the changelog entries.
7. **Review your diff** against "What verify.sh can't see", then run `harness/verify.sh`,
   commit, and finish the summary. Reviewers first try the change in an offline web preview
   (single player), so make sure it works there and tell them where to find it.

### Playbooks

Start from the closest existing feature of the same kind. Paths are relative to `game/`.

- **Something players use** (machines, tables, doors, containers): put it in the
  `interactables` group with `can_use()`, `interaction_text()` and `use()`
  (`features/interaction/README.md`). `use()` only sends a request; the server checks the
  sender, range and state again. See `features/loot/loot_container.gd`,
  `features/slot_machine/` and `features/parking_garage/garage_door.gd`.
- **An action on a key** (spray, noclip): register it at runtime with
  `Controls.ensure_action()`, not in `project.godot`. Label it in `SECTIONS` in
  `features/control_scheme/input_bindings.gd`, and act only while
  `Controls.gameplay_active()` (see `features/spray/spray.gd`). Add a controller button if
  a free one fits. Touch players only have movement, look, Use, Jump and the menu
  (`features/touch_controls/`), so say in the summary how they can use it, if at all.
- **Money, items, weapons and damage:** charge and pay out through the wallet in
  `features/money/` (`PlayerMoney.charge()`, as `features/gun_machine/gun_machine.gd`
  does), never through a second balance. Items belong to `features/holdables/` and
  `features/inventory/`, guns to `features/gun_machine/`. Hurt players by calling
  `apply_damage()` on the `combat` group's node from server code
  (`features/combat/README.md`). Other targets join the `killable` group and implement
  `take_hit()` (frogs, penguin, soccer ball); `features/animal_effects/` has the shared
  death explosion.
- **Creatures and NPCs:** the server simulates them and clients show synchronized state.
  See `features/frogs/` (with a README), `features/penguin/`, `features/gnomes/` (navmesh
  paths) and `features/shooting_gallery/`.
- **World content** (props, decor, geometry, rooms): `features/casino_hub/README.md` maps
  the main level (gaming floor, parlors, lobby, promenade) with coordinates, and
  `features/annex/README.md` and `features/parking_garage/README.md` cover their areas.
  Position content with the feature root's transform (the `Features` node is at the
  origin). Derive heights from the actual geometry (a box's top is its center y plus half
  its height), and keep walkways, ramps, doorways and the spawn clear. Run the layout test
  for the area you build in and add your own placement assertions:
  `tests/features/casino_hub/test_casino_layout.gd`,
  `tests/features/annex/test_accessibility.gd` or
  `tests/features/parking_garage/test_garage_layout.gd`. A new room is a `StreamedRoom`
  behind `RoomDoor`s, far from the rest of the map (`features/room_doors/README.md`). Use
  the CC0 packs in `assets/kenney/` (literal `res://` paths) or CSG and primitive meshes.
- **Panels and menus:** a panel that frees the mouse joins the `modal_ui` group and calls
  `Controls.pause()` when it opens, then leaves the group and calls `Controls.start()` when
  it closes; otherwise the Esc menu pops up over it
  (`features/inventory/inventory_screen.gd`, `features/leaderboard/leaderboard_panel.gd`).
  Esc menu links join `esc_menu_links` and implement `esc_menu_label()` and
  `esc_menu_open()` (`ui/login/login_screen.gd`). Settings pages follow `game/AGENTS.md`.
  Check what already occupies the screen, and keep the layout usable on a phone.
- **Chat commands:** join the `chat_commands` group and implement `handle_chat_command()`
  (`features/suicide/suicide.gd`).
- **Sound:** `GameAudio.play_at()` for sounds in the world and `GameAudio.play_ui()` for
  interface sounds (`features/game_audio/README.md`). Buttons click on their own.
- **Persistence:** most feature state lives in server memory and resets when the server
  restarts or redeploys. That's usually fine; say so in the summary. Player preferences
  use `SettingsStore`, and money persists through `features/money/`.

### Tests

Put tests in `game/tests/features/<name>/`. Copy the setup of the nearest existing test:
they instantiate `res://core/player/player.tscn` and set peer ids directly. Test behavior,
not just that nodes exist:

- rules and math as pure functions (placement, facing, rolls, timers);
- the server path: a valid request changes state, and a request from the wrong peer, out
  of range or in the wrong state doesn't (`tests/features/inventory/test_inventory.gd`,
  `tests/features/loot/test_loot_container.gd`);
- what a late joiner sees (`tests/features/slot_machine/test_slot_presentation.gd`);
- the positions, clearances and routes of anything you placed;
- the original behavior of any system you extended.

Some systems also have real server-and-client probes (`rg --files game/tests | rg
network_test`). If you change one of those systems, run its probe as its README describes.

### What verify.sh can't see

Nobody watches your change run before review, and reviewers have sent work back for each
of these. Check your diff for them before you finish:

- **Facing and direction.** Forward is -Z (`SourceMovement.wish_direction()`), but some
  models face +Z (the ferry, the penguin). Models face the way they move, seats and helms
  face forward, and pressing forward moves forward. A ferry once drove backwards.
- **Placement.** Things sit in the world the way the request imagines them: a hole is dug
  into the ground rather than a prop standing on it, a tail comes out of the rear, and
  "spread out" means far apart. Nothing floats, sinks or clips. Compute positions from the
  real geometry and pin them in tests. Compare positions in one space: feature roots are
  rarely at the origin, and mixing `position` with `global_position` once silently broke
  gnome avoidance.
- **Every view and device.** First and third person (F3), your own player and others,
  desktop, touch and controller. A fix once made projectiles invisible in first person.
- **Every peer.** Late joiners see the current state; disconnects and respawns clean up;
  two players at once can't break or duplicate anything; offline play works.
- **Existing options.** New choices handle the existing ones: a body-part picker has to
  cope with the penguin body.
- **Cost on the web client.** The game runs in a browser (WebGL2, single-threaded). Keep
  per-frame work small, add few dynamic lights and shadows, and don't run anything
  expensive for players who aren't nearby.

{{TASK}}
