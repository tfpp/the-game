# NPC dialogue panel

`npc_dialogue.gd` (`NpcDialogue`, a `CanvasLayer`) is a reusable, client-local
conversation panel in the Golden Crown style: a brass-framed portrait (or the
speaker's initial), the speaker's name, a short line and large action buttons.

```gdscript
var dialogue := NpcDialogue.new()
add_child(dialogue)
dialogue.open("Bartender", "Evening. What'll it be?", [
	{"label": "Buy", "action": _open_shop},
	{"label": "Ask", "action": func() -> void: dialogue.say("…")},
	{"label": "Leave", "action": Callable(), "close": true},
], portrait_texture)  # portrait is optional
```

- Open it only after the feature's own validated Use. Actions just call back into the
  feature; anything that changes shared state still goes through the feature's server
  request (for example `NetworkedInteraction.request_action`).
- `say(line)` replaces the line, `close(resume)` hides it (`resume = false` when another
  panel takes over), `closed` fires afterwards. `"close": true` closes before the action.
  A `"Leave"` action uses the secondary parchment style.
- Joins `modal_ui` and calls `Controls.pause()` while open. Esc / controller B close it;
  controller Start closes it and hands over to the pause menu. The first action takes
  controller focus; buttons never rely on hover.
- Layout: side-by-side with a row of up to four actions on wide screens; on narrow or
  portrait screens (`is_narrow()`: under 600 physical pixels wide, or taller than wide)
  it stacks, shrinks the portrait, drops the ornamental rule and lists one action per
  line. It compensates the stretched 1280x720 canvas like `ui/login`, so buttons stay
  48 physical pixels tall.

Used by the bartender (`features/bar_companion/bar_shop_menu.gd`). Tests:
`tests/unit/test_npc_dialogue.gd`, `tests/features/bar_companion/test_bar_shop.gd`.
