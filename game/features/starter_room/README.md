# Operations garage

This shared concrete garage is reachable by its door on the casino north promenade.
The whole garage, including the upstairs office, is a **safe zone**
(`features/safe_zone`): no PvP damage or firearm use, and rejected shots spend no
ammo. Self-damage commands retain the existing safe-zone exception.
New joins, fall recovery and combat respawns start in the Crown (`../crown_spawn/`).
Walk to the route-map panel behind the van's driver door and press
**E / B or Circle / touch USE**. Pick a
numbered destination on its schematic route map: **The Golden Crown**,
**Street District**, **Gun Shop · Rusty Hogg's**, or **Crown Strip Mall**. The old
shared **Basement Garage B1** route is hidden and server-rejected unless
`sv_cheats` is enabled; normal slum excursions use the Crown elevator. A two-second engine-start/acceleration sound
and opaque driving screen precede travel. Buttons support touch and controller
focus; the list scrolls on small/landscape screens. Esc / Back to garage dismisses
an unsubmitted map. There is no extra key or purchase.

The walking exit reaches the casino without the driving screen. Return through
the unsigned garage door on the casino north promenade at (-7, 1.1, -19.7), or find
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

Van: an armoured cash-in-transit model with two 128×128 painted atlases,
floor-centred pivot and front **+Z**. The detailed ladder chassis has axles, leaf
springs, driveshaft and exhaust. Both cab doors and rear cargo doors open outward
with **E / controller Use / touch USE** when standing beside their handles.
The cab doors have sloped inset windows, recessed handles, fitted inner panels
and mirrors that follow their leaves. Their server-owned state replicates to all
players, including late joiners.
Moving leaf collision clears the cab and cargo openings. The route-map panel
behind the driver door keeps the original travel interaction separate.
Rolling shutter: separate fixed guide rails/housing and a moving painted steel
leaf with collision, using the shared 128px garage-finishes atlas. The service cabinet reuses the procedural prop kit; workshop equipment
shares the lift enamel/steel atlas.

Authoritative native builder, exact UV guide, original painting and prompt:
`docs/design/model-sources/operations-van/` (original shell/paint) and
`docs/design/model-sources/armoured-operations-van/` (enhancement recipe).
The new model review renders are under `docs/design/previews/armoured-operations-van/`.
Normal rebuilding preserves approved
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

## Workshop lift and private rear stash

Use the red lift control panel to raise, stop or lower the van. Stand outside the
support-arm bay when lowering; it refuses and stops descent if another player
enters underneath. Four pads support the chassis rails. The engine meets its
gearbox and shaft, which reaches the rear differential and axle; both axles meet
the wheel hubs. The lift raises 1.95m, leaving space to walk underneath. This is
an inspection lift; vehicle upgrade/tuning mechanics are not added. Van travel
requires the lift to be fully lowered; accepted trips lock its controls.

Open either rear cargo door while the van is lowered, then use **PRIVATE STASH**
at the rear opening. Each player has 24 individual item spaces (no stacking).
Store and Take tabs use click/tap buttons and existing item icons; withdrawals
use the first empty backpack slot. Carried equipment can also be deposited;
keys remain on the key ring. Phones show two columns with 52px navigation
buttons, at least 106px item buttons, a scrolling grid and fixed Back control.
No drag or new input binding is required.

Contents live only in server-side `PlayerInventory.van_stash`, excluded from
Hand replication. Authenticated interaction events reveal contents only to the
requester. Every transfer locks inventory, saves the complete carried/stashed
snapshot, then applies and acknowledges it. Failed saves retain the old state;
a lost save response is read back, and unresolved writes remain locked until
reconnecting rather than permitting duplicate items. No client-supplied account
or player identity is accepted. Raised/closed-door/distant access is rejected.

Signed-in storage uses the existing signed accounts inventory API and SQLite
record. Offline storage atomically replaces `user://offline-inventory.json`,
including carried items to prevent a deposited item reappearing on restart.
Once activated, the ordinary inventory is saved locally too. Preserve this file
for offline saves and the accounts database for server saves. Anonymous dev-auth
multiplayer has no stable account identity and cannot use saved stash storage.
Old snapshots without `van_stash` load with empty storage. Unknown IDs and keys
are filtered on restore; storage is capped at 24.

New native model/paint authoring: `docs/design/model-sources/workshop-lift/`.
Review: `docs/design/previews/workshop-lift/` and `docs/design/previews/van-stash/`.
`test_van_stash.gd` covers real two-client privacy/late join, authentication,
capacity, stale requests, transfer durability, response loss, account/local
reload and phone tap controls. Existing inventory/loot/travel coverage remains.

The cleaned workshop places its steel workbench below the mezzanine, with drawer
banks, hanging tools, a vise and socket tray. A wheeled tool chest sits alongside;
the compressor, tire rack and mechanic's creeper sit on the right wall, outside
the lift bay. The floor jack parks near the bench. Loose crate/barrel clutter is
removed and the service cabinet moves against the left wall. Hazard borders mark
the service bay. These are inspection/set-dressing props; room architecture stays
in its existing GridMaps. Equipment has seven indexed meshes, 2,528 triangles,
one material and reuses the lift's approved 128px atlas. Native authoring and
review: `docs/design/model-sources/garage-tools/`. Layout tests cover the original
spawn/exit/van routes plus standing areas and the workbench approach.

The framed side window overlooks a real streamed alley with wet asphalt, brick
walls, service props, outdoor rain and lightning. `alley_weather.gd` reuses the
pawn shop storm recordings through GameSFX, disables effects on dedicated servers,
and stops ambience when the camera leaves the garage. The window glass seals the
GridMap opening. `garage_finishes.tscn` owns the textured shutter and broom
cupboard; floating world debug labels have been removed. Interaction prompts and
functional screens remain available.

## Working workshop

`Room/Workbench` is always present on every peer, beside the existing model.
Use opens an owner-only blueprint workbench with 106px gear cards, model previews,
before/after damage and live salvage counts. Install and Back controls stay fixed
at 60px while the content scrolls on phones and landscape screens.
A stock firearm in hand or backpack can be tuned once for **two carried Scrap and
one Electronics**. The tuned item (`tuned:<stock ID>`) deals 15% more damage and
retains normal ammo, magazines, animations, skins and handling. Its identity
survives dropping, backpack moves, stash transfers and saved inventory reloads.
Salvage remains loot that can alternatively be sold; no cash or XP system is added.
`WorkbenchRecipes` builds a detached full inventory snapshot, and `GearWorkbench`
validates sender, range, exact gear ID, materials and inventory availability.
Inventory stays locked during the existing atomic persistence commit. Only a
successful save applies the upgraded item and material consumption. Failed or
uncertain saves use the inventory store's existing recovery policy.

`Room/RollerDoor` is also always present, with server-owned replicated height and
target, moving collision and open/stop/close control beside the left guide rail.
The painted leaf feeds into the fixed roller housing; the shader clips material
above the slot. Closing reverses when players or physics items occupy the opening.
A real four-metre GridMap aperture reveals a rainy road with lane markings,
sidewalks, parked scenery and lamps. A permanent invisible full-height
collision boundary keeps walking and jumping players inside. Obstruction queries
exclude this fixed boundary. Only rendering bounds include the road; membership
and safe-zone bounds remain those of the original garage. The road has no
interactions, travel destination or excursion.

`garage_atmosphere.gd` owns camera-scoped spatial fluorescent hum, original quiet
radio music and a motor loop while the shutter moves. A short, occasional dip in
one bay lamp never extinguishes the workshop. Opening the shutter admits louder
storm ambience. Existing native radio, coffee cups, coat rack, office chair and
table lamp add personal details. Sounds and scenery unload with the interior;
dedicated servers skip audio and lighting effects. All sounds use GameSFX.

Authoring: `docs/design/model-sources/garage-atmosphere/build.gd` bakes the road
scenery GridMaps and original sound loops. The existing garage-finishes builder now
exports separate leaf/frame meshes sharing the approved 128px atlas. Focused tests
cover exact recipe consumption, durable saves/failures, restored tuned items,
ammo compatibility, shutter physics/range, remote use and late joining.

The ImageGen background source and exact prompt are preserved in
`docs/design/model-sources/workbench-ui/`. Its native importer writes a 128px
mipmapped panel; all text, counts, item previews and controls remain live Godot UI.
