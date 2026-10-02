# Quest 3 / WebXR

Open the game's HTTPS URL in Quest Browser, join normally (or choose **Play
offline**), then open the menu → **More** → **Quest / WebXR** → **Enter VR**. Accept the
browser's immersive-session permission. Desktop and unsupported browsers show an
explanation and keep ordinary play available. Entry must be a button press; it
never starts automatically.

This is a seated/standing-in-place mode using Touch controllers:

- Left thumbstick walks in the direction you look, using the existing player hull.
- Right thumbstick snaps 30 degrees; return it to centre before turning again.
- A jumps. Either trigger uses the nearest eligible object; the headset shows its
  existing interaction text and optional color (including loot rarity and price).
  These are proximity interactions, not controller rays.
- Right grip fires, uses a held item or punches using existing action handlers.
  Left grip reloads generated guns. X opens the inventory.
- B or Y leaves VR. The Quest system's exit control also works.
- Opening any game panel leaves VR so you can operate it in the browser. Return via
  Quest / WebXR → Enter VR afterwards. Ordinary 2D HUD layers are hidden in VR.

The initial head pose calibrates to the game's eye height, including when seated.
Head orientation feeds the existing player's yaw/pitch. Small physical head
translations are visual lean only: they do **not** move the collision hull. Use the
stick for travel, not room-scale walking. Hands are not tracked multiplayer avatars;
held items retain their existing head-aimed presentation, not controller aiming.
Other keyboard-only actions remain available outside VR. No hand-tracking or AR.

## Ownership and integration

`webxr.gd` owns only local session lifecycle, browser setup UI and render settings.
`vr_rig.gd` attaches to the existing local Player and supplies `Controls.Device.XR`
movement/jump plus the existing interaction and item action paths. Player still
owns movement, collision and its existing replicated position/yaw/pitch. Existing
server RPC handlers remain responsible for gameplay validation. No RPC, shared
state, persistence or dependencies on sibling PRs are added. Other peers and late
joiners see an ordinary player through Player/Sync.

The rig updates input before Player physics, and its camera adapter after Player
and third-person presentation but before held-item mounts. F3's preference is
preserved while VR suppresses its camera displacement/body visibility. Teleports
(including changes to facing) continue through the existing owner path. Losing the
local player exits VR; respawns on the same player follow its new position.

Pause, lost headset visibility/tracking, disconnected controllers and session exit
clear VR motion/held fire. Session denial leaves a retryable browser panel. Exit
restores the input device, camera, canvas visibility and resolution scale. Modal
cameras such as arcade computers retain control when they initiate the exit.

`core/input/controls.gd` adds an isolated XR device so browser-emulated gamepad or
mouse events cannot steal input or double movement. `project.godot` enables XR
shader variants **only for web exports**, needed for stereo rendering before
runtime initialization. Both are human-review paths. The existing Compatibility
renderer and single-thread export stay in place; no OpenXR/plugin install is needed.
RetroStyle preserves the viewport render scale, including browser resize events.
Mobile uses the same rendering settings as desktop; WebXR owns its immersive scale.

Implementation references: [Godot WebXR](https://docs.godotengine.org/en/4.7/tutorials/xr/webxr_intro.html),
[session API](https://docs.godotengine.org/en/4.7/classes/class_webxrinterface.html),
and [XR shader setup](https://docs.godotengine.org/en/4.7/tutorials/xr/setting_up_xr.html).

## Validation

Run `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/features/webxr -gexit`
from `game/`. Tests exercise lifecycle cleanup, input isolation, camera/teleport
math, snap-turn latching, modal camera preservation, shared loot Use/range checks,
third-person restoration and mobile resize compatibility.

Physical acceptance still requires a Quest 3: test HTTPS entry/denial/re-entry,
both eyes, controller mappings, seated calibration/recenter, tracking loss,
teleport/respawn, a slot/door/loot interaction, inventory exit and multiplayer
visibility. Check performance/comfort in the furnished casino and streamed rooms;
headless CI cannot establish stereo rendering or a headset frame-rate guarantee.
