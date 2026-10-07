# Brine & Bureaucracy

A **free** original pirate-comedy text adventure cabinet stands on the Golden
Crown's northeast promenade at **(17, 0, -18.8)**, facing +Z into the hall. From
the elevator spawn, turn right and continue past the street/gaming-suites doors.
It is separate from the slot bank, VIP doorway, spawn jitter and open PR #510's
statue position. The saved GridMap promenade supports its floor-centred base.

Approach the front, look at its screen, and **Use: E / controller B or Circle /
touch USE**. Choose text verbs and dialogue using mouse, touch, or standard
D-pad/focus navigation and A/Cross. No text entry, new key or keyboard is needed.
The story has four locations, fictional pocket items, combination/trade puzzles,
a three-exchange battle of wits and an ending. It borrows Monkey Island's comic
adventure spirit, not its script, characters, locations, music or artwork.
The cabinet fiction establishes no new world canon.

**Hint** offers contextual help. **Log** shows the last eight exchanges.
**Close / pause**, Esc or controller cancel leaves the game; Use again to resume.
Controller Start closes without resuming, letting the existing menu open.
**Start over… / Play again** asks for confirmation. Incorrect replies are
retryable; there are no deaths, unwinnable item losses, wagers or real rewards.
All story items are fictional, not inventory pickups.

## Ownership and interface

- `machine.gd` is the distinct feature's stable endpoint, loaded automatically
  through `feature.tscn`; no main-scene/feature-loader edits.
- Reuse the common `interactables` interface: `can_use(player)`,
  `interaction_text()`, `use()`. NetworkedInteraction resolves the real sender
  and range, then validates living player, front side, aim and unobstructed access.
- `request_choice(id: String, revision: int)` sends exactly `choice` and
  `revision` via the registered `choose` action. The server requires a previously
  opened story, range/front/line-of-sight/life, exact types, current revision, an
  actually available choice, and a per-player 120ms wall-clock delay. No player
  identity, money, story state or arbitrary command is accepted from a client.
- `story.gd` owns the small deterministic story rules. Only the server cabinet
  stores/mutates one story per authenticated peer. Simultaneous players do not
  share progress or a cabinet-wide cooldown. Revisions remain monotonic over
  replay so old commands cannot advance a new voyage.
- `open` and `page` are recipient-only reliable authority events carrying a
  detached current page (place, description, response, pockets, bounded log,
  choices and revision). There is **no mutable public cabinet state to replicate**.
  Reopening supplies the current private snapshot; late joiners get their own
  fresh story on Use, never old events or someone else's transcript. Clients
  cannot advance progress locally.
- Closing, walking/teleporting away or death closes the modal without erasing
  progress; actions while distant/dead are denied. Replacing a player on respawn
  retains their peer's story. Disconnect, server restart/redeploy or a network
  mode change clears connection-session progress. No disk or account persistence.
  Offline peer 1 uses the same validated server path with no backend.
- `screen.gd` allocates the local UI only after authorized Use (never on a
  dedicated server). It joins `modal_ui` and uses Controls.pause/start; gameplay
  movement/fire/Use are suppressed. The responsive scrolling panel has 56px
  controls and a fixed Close footer in portrait and short landscape views.
  Delayed choice replies cannot reopen a dismissed screen.

The cabinet reuses `casino_props/props/video_poker_machine.tscn`, its original
painted 128px atlas, collider and native mesh. A small unlit screen quad covers
the old poker display, with readable Label3D text; no new media, texture generation,
lights, shadows, camera swap or continuous cabinet processing is added.
Existing wallet, backpack, quests, computers and gambling remain untouched.

## Checks and actual rendered review

From the repository root:

```sh
godot --headless --path game --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/adventure_machine -gexit
godot --headless --path game --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir= -gtest=res://tests/features/casino_hub/test_casino_layout.gd -gexit
harness/verify.sh
```

The feature tests include a real ENet server, two concurrent clients and a late
third client: private replies, complete voyage, replay, reopening, forged/stale
and distant requests, disconnect cleanup, and client non-authority.
Other tests exercise offline/touch common Use, modal/focus/phone layout,
life/range/obstruction, alternative puzzle order, bounded snapshots, and saved-level
floor/support/route checks including existing slot approaches.

With a graphical renderer (xvfb-run works in CI):

```sh
godot --path game --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/adventure_machine/visual_probe.tscn -- /tmp/adventure-machine
```

Captures include the actual saved casino, cabinet, desktop/phone/landscape panels
and a dialogue state. Reviewed images stay local in `/tmp/adventure-machine/`
(or the supplied folder), following the repository's ignored-preview policy.
These are native Compatibility renders, not browser performance measurements or
physical-device acceptance.
