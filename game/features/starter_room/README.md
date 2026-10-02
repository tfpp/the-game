# Operations garage

This shared concrete garage is reachable by its door on the casino north promenade.
The whole garage, including the upstairs office, is a **safe zone**
(`features/safe_zone`): no PvP damage or firearm use, and rejected shots spend no
ammo. Self-damage commands retain the existing safe-zone exception.
New joins, fall recovery and combat respawns start in the Crown (`../crown_spawn/`).
Walk to the van's driver side and press **E / B or Circle / touch USE**. Pick a
numbered destination on its schematic route map: **The Golden Crown**, **Basement
Garage B1**, **Street District**, **Gun Shop · Rusty Hogg's**, or **Crown Strip Mall**. A two-second engine-start/acceleration sound
and opaque driving screen precede travel. Buttons support touch and controller
focus; the list scrolls on small/landscape screens. Esc / Back to garage dismisses
an unsubmitted map. There is no extra key or purchase.

The walking exit reaches the casino without the driving screen. Return through
**OPERATIONS GARAGE** on the casino north promenade at (-7, 1.1, -19.7), or find
**Operations Garage** in GPS. The street's existing casino entrance returns to the
Crown; the basement garage's existing return portal reaches the dev room, whose
exit reaches the casino. The gun shop door returns directly here; its street and parked van are scenery only.
The strip mall route preloads its existing plaza floor and arrives beside the return
kiosk; use that kiosk to return to the casino.

## Ownership and integration

- `Room` is a `StreamedRoom` at (0,0,-3000), bounds x ±8.2, z ±9.2, y -1…6.
  Only static GridMaps, fixtures and workshop props live in `interior.tscn`.
  Van, collision, authenticated endpoints and markers remain on every peer.
  `starter_room.gd` checks the local initial/respawn position before player physics
  and preloads the base floor while the server assignment is in flight. Dedicated
  servers skip it; subsequent content lifetime stays with RoomVisibility.
- `Spawn` marks the garage arrival point for its floor preload and tests. It is no
  longer in `player_spawn`; `crown_spawn` supplies that marker. The square around
  it is clear of the van and workshop props.
- Structure uses the casino's **1 × .25 × 1m GridMap** and existing floor/wall tile
  shapes/transforms, copied to `garage_tiles.tres` with existing concrete materials.
  Separate east/west and north/south grids preserve corner panels. Floor top is y=0,
  ceiling bottom 4.75m; two shadowless lights illuminate the room.
- `OperationsVan` uses `NetworkedInteraction.register_use/request_use` to open a
  private map. Its `travel` action accepts exactly one integer `zone`, resolves only
  configured existing arrival markers, and validates the authenticated player,
  range, pending trip and Combat's `is_respawning()` again on the server.
- Pending trips are server memory, per peer (no van-wide cooldown). Death,
  disconnect, walking away and network mode changes cancel them. After two seconds
  the server calls the existing owner `server_teleport` and `SlumRuns.finish()` like
  existing development portals. No new excursion, private instance, money, loot or
  persistence system is introduced. Late joiners see the same static base, not old
  transitions. Offline uses the same authority path.
- The owner-only departure event preloads a destination StreamedRoom before the
  teleport. The destination button recaptures the pointer inside its user gesture;
  the noninteractive transition preserves that lock while `modal_ui` blocks gameplay.
  The modal closes when the player arrives, on death/session changes, or after a
  bounded timeout. GameAudio owns the shared `van_departure` UI cue and bus.

## Assets and review

Van: one indexed 176-triangle mesh, one 128×128 painted atlas, floor-centred pivot,
5m long × 2.2m wheel width × 2.25m high, front **+Z**. The simple gameplay collider
is separate. Rolling shutter: one static mesh using an existing small steel-like
texture. Cabinet, crate and barrel reuse the procedural prop kit.

Authoritative native builder, exact UV guide, original painting and prompt:
`docs/design/model-sources/operations-van/`. Normal rebuilding preserves approved
paint. See that README for commands. Actual Compatibility renderer captures under
`docs/design/previews/operations-garage/` include arrival, rear, underside, route map,
phone layout and driving screen. No browser performance claim is made.

```sh
# From game/
godot --headless --fixed-fps 64 -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/features/starter_room -gexit
# Requires a display (xvfb-run works in CI):
godot --rendering-method gl_compatibility --audio-driver Dummy \
  res://tests/features/starter_room/capture.tscn -- /tmp/operations-garage
```

## Upstairs CRT jobs application

Climb the two-metre-wide west stairs (bottom at x -6, z 0) to the **2.5 m-high
mezzanine**, and use the CRT on the desk with **E / B or Circle / touch USE**.
The **Crown OS desktop** opens first. Launch **Jobs** for five optional surveys,
one for each existing
van destination. Select one, exit the application, travel there and stay within
five metres of the arrival marker for three consecutive seconds. The job is pinned
at the **top right**, below the connection readout. Return to this computer and
**Submit report** to collect **$10 + 25 XP**. No purchase, extra key, level gate or
casino assignment is involved. The van still works exactly as before.

Buttons support controller focus and touch; the application scrolls on small screens.
Log off / Esc closes it, and walking out of range or dying closes it too.
An accepted contract survives death/respawn. Survey dwell resets if you leave its
arrival area or die; once a report is ready it stays ready until submitted.

`job_terminal.gd` owns per-peer `records` (`job`, `ready`, `done`, `xp`) replicated by
NetworkedInteraction, including late-join snapshots. Accept and claim requests validate
transport sender, payload, range, life, destination and current state. Clients never
supply progress, reward, XP or another player's ID. A server-side payout lock prevents
duplicate claims, and settlement defers outside the synchronous component callback.
Wallet failures keep the ready report and operation ID for a retry through existing
`PlayerMoney.credit_coin`; XP is awarded only after wallet success. Players can work
on the same job independently, including offline peer 1.

Jobs and XP are **connection-session state**, not a permanent leveling system:
each destination can be completed once per connection; disconnect/server restart or
network-mode change clears them. Earned authenticated money persists in the existing
wallet; offline money remains temporary. No shared wallet or API interface changed.

The office is part of the same StreamedRoom (not a separately teleported room).
Architecture remains saved GridMaps, reusing garage concrete slabs and a feature-owned
concrete stair/industrial steel guard library (`upstairs_tiles.tres`). The stair
profile and smooth walking proxy retain the original dimensions; no casino carpet,
walnut or brass guard finish is used. The original spawn square, walking exit and van approach
remain clear. Static props live in streamed `interior.tscn`; the terminal endpoint
and GPS marker always exist in `feature.tscn`. The desk and CRT reuse existing
painted hotel/casino assets (no new meshes or textures, lights or shadows).
Desk top y=3.303 supports the CRT; mezzanine headroom is 2.25 m. Rebuild only the
new editable stair/deck GridMaps with:

```sh
godot --headless --path game -s res://features/starter_room/tools/build_upstairs.gd
```

The capture command above now also renders stairs, CRT, desktop/phone application
and a synthetic ready-job phone pin. Captures are under
`docs/design/previews/garage-jobs/`; they review presentation, not a paid transaction
or browser performance. New tests cover validated jobs, continuous survey presence,
existing wallet payout/retry, XP, lifecycle, private pin/modal behavior, actual stair
walking/headroom and ENet authenticated requests/concurrent records/late joins.

## Crown OS desktop

The same upstairs CRT now runs a simulated personal desktop with classic
Windows/Linux-style chrome: teal wallpaper, icon shortcuts, grey beveled controls,
blue window title bars and a bottom taskbar. Click a desktop shortcut or **Start**
to open **Jobs**, **Notes**, **Files**, **Calculator**, or **Help**. Multiple windows
can remain visible together. Drag a title bar to move a window and its bottom-right
grip to resize it (mouse or touch). Clicking or focusing app controls brings that
window to the front. **□** maximizes/restores a window and supports controller focus.
The calculator opens as a compact utility window. Windows stay within the workspace
above the taskbar and shrink to fit small viewports; contents remain scrollable.
**Minimize** hides only that app, the taskbar restores it, and **Close** removes it
from the taskbar. **Log off** or Esc leaves the computer.
The taskbar stays below the workspace; app contents scroll and follow controller
focus in short viewports. **Start → Log off** leaves the computer. Text entry requires a physical or on-screen keyboard;
controller users can navigate buttons and use the calculator keypad.

Notes has a fixed top **New / Save** toolbar and document-name field above the
editor. New or opening another file asks before discarding unsaved changes; cancel
to save first. Files opens and deletes saved documents, and an already-open Files
list refreshes after saving. Names are at most 32 characters; there are up to 12 private
documents of 4096 characters each. Saving an existing name replaces that document.
Saving is explicit, not automatic. Documents and drafts survive
closing apps/logging off and death, but reset on disconnect, network-mode change
or game restart. Nothing is uploaded, shared with other players or stored on disk.
The calculator supports decimal +, -, *, / with left-to-right chaining, clear and
division-by-zero handling (not expression precedence).

`desktop.gd` owns only private UI and bounded session documents. GarageJobPanel
retains the original modal/pin lifecycle and public open/close/request_result
interfaces; Jobs uses the original validated terminal actions, replicated records,
progress and wallet settlement unchanged. `desktop_theme.gd` supplies classic
chrome shared by all apps; `desktop_shortcut.gd` draws small native shortcut icons.
`desktop_window.gd` handles local focus, drag/resize gestures, maximize/restore and
workspace bounds (including canvas scaling and viewport changes).
The capture recipe includes the Start menu and concurrent apps; revised desktop,
jobs, phone notes and landscape calculator reviews are in
`docs/design/previews/crown-os/`.
Opening the desktop still requires the
server-authorized in-range use event. No new RPC, gameplay state, placement,
persistence system, key or host OS/internet access is introduced. Late joins see
existing job snapshots, never another player's desktop or documents.

## Heist planning wall

The east wall beside the van's open arrival aisle carries two 2.8 × 2.1 m boards:
**WORLD / ROUTE MAP** circles **OPERATIONS GARAGE / YOU ARE HERE** in red, and
**GOLDEN CROWN / BLUEPRINTS** shows the main hall, sunken gaming pit, both ramps,
west balcony bar and elevator, plus an upper-bar section. The world map is a
schematic of the van's three existing destinations, not literal distances or a
claim about the intentionally undefined city geography. Red entry arrows are
heist-style scenery, not new missions or travel controls. Just walk over and look;
keyboard, touch and controller all use their normal movement/look controls.

`planning_board.gd` constructs static art only when StreamedRoom loads the interior,
with no processing, collision, RPCs, extra lights or shared mutable state. It reuses
SignBoard's exact letter quads and the shared 64px glyph atlas; the two paper charts
share a painted 128px atlas. This avoids unreadable rasterized map labels. Late joins
and room reloads see identical boards; van, jobs and walking exit remain unchanged.

The stair library builder retains existing cell IDs and collision shapes but emits
new squared steel hand/knee rails with upright supports. Existing weathered concrete
and steel textures are reused. Art sources, UV template, ImageGen prompt, rebuild
commands and Compatibility renderer review are documented in
`docs/design/model-sources/garage-planning/README.md`. The capture command above also
renders both boards, the stair underside and mezzanine guard. Placement/winding,
materials, texture budget and streaming reload checks are in `test_planning_art.gd`.

Tests cover spawn fallback/override, actual initial floor contact, spawn and approach
clearance, indexed winding/UVs/budget, all real arrival links, streamed floor preload,
excursion finish, validated requests, cancellation, concurrent preparation, modal
cleanup and real ENet sender/private-event/late-join/disconnect behavior.
