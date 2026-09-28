# Controls

The client supports keyboard/mouse, touch, and standard gamepads (including browser
controllers such as Backbone). Online and offline play use the same inputs.

| Input | Move | Look | Jump | Use | Menu |
| --- | --- | --- | --- | --- | --- |
| Desktop | WASD / arrows | Mouse | Space / wheel up or down | E | Escape |
| Controller | Left stick | Right stick | A / Cross (bottom face button) | B / Circle | Start |
| Touch | Drag left side | Drag right side | JUMP button | USE button | II button |

Use works while looking at a nearby interactable. A prompt identifies the target;
menus and chat suppress interaction. The slot machine is near the initial spawn area.

Desktop mouse sensitivity and movement bindings are unchanged. Jump remains a press,
not a hold-to-bunny-hop action, for every input device. Joysticks preserve analog
movement speed. Controller sticks use a radial 0.18 deadzone and right-stick look is
scaled by elapsed time.

On phones, Resume/Play starts without requesting mouse capture. Touch movement,
looking, and jumping use separate finger IDs, so they work simultaneously. The web
shell accounts for iPhone safe areas, and rotation releases active touches.

A connected controller hides the touch controls automatically. In browsers, a button
press may be needed before the browser exposes the controller. Start opens/resumes
the game menu; use the D-pad or left stick to navigate buttons and A to activate.
Sign-in text fields still use the keyboard. Disconnecting the controller pauses play
and restores touch controls after Resume on a phone. Losing window focus also pauses
and clears pending touch/look/jump input. A physical mouse click or movement key
switches back to desktop input; desktop play requires mouse capture as before.

Implementation: shared state in `game/core/input/controls.gd`, touch overlay and web
shell in `game/features/touch_controls/`, with player and menu integration. The core
changes require human review under the repository's normal review rules.

## Validation

Run `harness/verify.sh` for automated regression tests and multiplayer smoke tests.
For device acceptance, open the exported web build on iOS Safari and check:

1. Resume with no controller; move, look, and jump simultaneously with three fingers.
2. Rotate between portrait and landscape; check notch/home-indicator clearance.
3. Connect Backbone (press a button if necessary); verify the touch controls hide,
   both sticks work, A jumps, and Start opens the menu.
4. Resume with A, then disconnect Backbone and resume with touch.
5. Background and return to Safari; confirm play is paused with no stuck movement.

Browser automation with simulated touch/gamepads supplements these checks; it does
not replace testing a physical Backbone on iOS Safari.
