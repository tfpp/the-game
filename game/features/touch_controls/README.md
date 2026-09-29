# Touch controls

Phone overlay (`touch_controls.gd`): floating move stick on the left, drag-to-look on
the right, JUMP, USE, FIRE and a pause button. Shown only while `Controls.touch_visible()`.

`attack_input.gd` presses `primary_action` and `gun_fire` (what the left mouse button
does) via `send_attack()`. The FIRE button holds them while touched, and the controller
right trigger (`JOY_AXIS_TRIGGER_RIGHT`) presses them once past 0.5 and releases below
0.3. The right bumper stays bound too. Desktop bindings are unchanged.
