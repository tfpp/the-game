# Third-person camera

F3 toggles the local camera preference. On phones, tap the small **CAM** button
beside the menu. The camera sweeps behind the player's eye and shortens its distance
around collision; the local body is shown when there is room.

Hold **middle mouse** and move the mouse to orbit without turning the character.
Rebind **Orbit third-person camera (hold)** in Settings > Controls; the existing
control settings save the binding and offer reset-to-default. Mouse/touch sensitivity
settings also apply to orbit. In third person, right-side touch swipes orbit directly,
while the left stick, JUMP, USE and FIRE remain independent. In first person swipes
still turn/aim the player. Controller right-stick aiming remains unchanged; there is
no new default controller binding because existing buttons are occupied.

Orbit is an offset from player aim and stays where you leave it, including on mouse
release. Ordinary mouse/controller look still turns the player and carries that offset
with it. Toggle to first person to reset the orbit (on phones, also use first person
to change character aim). Pitch is limited to ±89 degrees. Pause/focus loss, modal
menus and XR immersion clear the held modifier; press it again after resuming.
Switching from touch/controller to a mouse or rebound key keeps the new hold intact.
Replacing/disconnecting the local player resets orbit but keeps the F3
preference. Camera mode and angles are session-local, not saved or replicated. Remote
players and authoritative weapon aim are unaffected. Movement follows the camera's
horizontal heading: forward goes away into the view, back comes toward the camera,
and strafing goes screen-left/right, even when orbit faces the character. This applies
to keyboard bindings, controller movement and the touch left stick. Camera pitch does
not change movement speed or add vertical movement. Character facing is still aim,
not automatically turned toward movement.

The feature joins `third_person_camera`: `toggle_camera()` is the shared guarded
F3/touch entry point; `orbit_look(change: Vector2) -> bool` accepts sensitivity-scaled
radians and returns true only when it consumed local third-person look. TouchControls
falls back to `Controls.look_delta` otherwise. Mouse orbit consumes motion in `_input`
before Player's `_unhandled_input` aim handler.

`movement_yaw(player: Player) -> float` supplies the current local camera heading to
Player's existing movement tick, after its look input is consumed. It uses live yaw
plus orbit rather than a potentially stale rendered camera transform. First person,
XR and other players return their unchanged aim yaw; without this feature Player
also falls back to aim yaw. SourceMovement acceleration, analog input strength and
owner-authoritative position/velocity replication remain unchanged.

During WebXR immersion this feature leaves the headset camera and hidden local body
alone. Toggles/orbit are ignored in VR, and the same preference resumes when the
session ends. Tests live in `tests/features/third_person/`, with XR transitions in
`tests/features/webxr/test_integration.gd` and binding persistence in
`tests/features/control_scheme/test_rebinding.gd`.

The HUD crosshair (group `aim_reticle`, `ui/hud.tscn`) is hidden while the third-person
camera is active and shown again in first person, VR, or without a local player.
