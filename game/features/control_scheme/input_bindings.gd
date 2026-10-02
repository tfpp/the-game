extends RefCounted
## The Controls page's catalog of rebindable actions and the helpers to rebind them.
##
## Every action has two binding slots: keyboard & mouse, and controller. Rebinding a
## slot replaces the first binding of that kind (the "primary" one) and leaves any
## extras alone, so jump keeps its controller bind when Space is rebound.
## Bindings are saved as small dictionaries: {"key": physical_keycode},
## {"mouse": button_index} or {"pad": button_index}.

const Glyphs := preload("res://features/control_scheme/input_glyphs.gd")

## Actions listed on the Controls page, by section: [action, label]. Actions a feature
## registers that aren't listed here still show up, under "Other".
const SECTIONS: Array[Dictionary] = [
	{
		"title": "Movement",
		"actions":
		[
			[&"move_forward", "Move forward"],
			[&"move_back", "Move back"],
			[&"move_left", "Strafe left"],
			[&"move_right", "Strafe right"],
			[&"jump", "Jump"],
			[&"crouch", "Crouch (toggle)"],
		],
	},
	{
		"title": "Items",
		"actions":
		[
			[&"primary_action", "Use held item / punch (hold to power punch)"],
			[&"kick", "Kick (hold to power kick)"],
			[&"use", "Interact"],
			[&"drop_item", "Drop item"],
			[&"inventory", "Inventory"],
			[&"roulette_bets", "Roulette: bet view (while seated)"],
		],
	},
	{
		"title": "Chat",
		"actions":
		[
			[&"chat_open", "Open chat"],
			[&"voice_talk", "Push to talk (hold)"],
		],
	},
	{
		"title": "View",
		"actions":
		[
			[&"toggle_third_person", "Third-person camera"],
			[&"orbit_third_person", "Orbit third-person camera (hold)"],
			[&"toggle_flashlight", "Flashlight"],
			[&"toggle_noclip", "Noclip (requires sv_cheats)"],
			[&"toggle_console", "Developer console"],
			[&"spray", "Spray"],
			[&"emote_flip_off", "Emote wheel (hold)"],
			[&"toggle_changelog", "Release notes"],
			[&"gps", "GPS phone"],
		],
	},
]

## Bindings that can't be changed, shown for reference: [label, keyboard, controller].
## Esc must stay the menu key (browsers use it to leave pointer lock), and the sticks
## are read directly.
const FIXED_ROWS: Array[Array] = [
	["Look", "Mouse", "Right stick"],
	["Menu", "Esc", "Start"],
]

## Movement also always works on the left stick, whatever is bound here.
const STICK_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right"
]

## Handedness presets own these actions' keyboard bindings.
const SCHEME_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"jump"
]

## Never rebindable or listed under "Other".
const RESERVED_ACTIONS: Array[StringName] = [&"release_mouse"]


## Every catalog section whose actions exist, plus an "Other" section for actions no
## section lists. Each section: {"title": String, "actions": [[action, label], ...]}.
static func sections() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var listed: Array[StringName] = []
	for section: Dictionary in SECTIONS:
		var present: Array = []
		for entry: Array in section["actions"]:
			listed.append(entry[0])
			if InputMap.has_action(entry[0]):
				present.append(entry)
		if not present.is_empty():
			result.append({"title": section["title"], "actions": present})
	var other: Array = []
	for action: StringName in InputMap.get_actions():
		if listed.has(action) or RESERVED_ACTIONS.has(action) or str(action).begins_with("ui_"):
			continue
		if InputMap.action_get_events(action).is_empty():
			continue
		other.append([action, str(action).capitalize()])
	if not other.is_empty():
		result.append({"title": "Other", "actions": other})
	return result


## Every action that can be rebound (see `sections`).
static func actions() -> Array[StringName]:
	var result: Array[StringName] = []
	for section: Dictionary in sections():
		for entry: Array in section["actions"]:
			result.append(entry[0])
	return result


static func matches_slot(event: InputEvent, pad: bool) -> bool:
	return InputLabels.is_pad(event) if pad else InputLabels.is_keyboard_or_mouse(event)


## True if `event` can be bound to a slot: a key (not Esc), mouse button or controller
## button press. Esc is reserved for the menu.
static func is_bindable(event: InputEvent, pad: bool) -> bool:
	if not event.is_pressed() or event.is_echo():
		return false
	if pad:
		return event is InputEventJoypadButton
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return code != KEY_NONE and code != KEY_ESCAPE
	return event is InputEventMouseButton


## A saveable copy of `event`, or an empty Dictionary if it can't be bound.
static func to_data(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		var data := {
			"key": key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		}
		# Left and right modifiers (Shift, Ctrl, Alt, Command) share a keycode and differ
		# only by location. Unsided bindings match either side.
		if key.location != KEY_LOCATION_UNSPECIFIED:
			data["location"] = key.location
		return data
	if event is InputEventMouseButton:
		return {"mouse": (event as InputEventMouseButton).button_index}
	if event is InputEventJoypadButton:
		return {"pad": (event as InputEventJoypadButton).button_index}
	return {}


## A clean binding event (no pressed state, any device) from saved data, or null.
static func from_data(data: Dictionary) -> InputEvent:
	if data.has("key"):
		var key := InputEventKey.new()
		key.physical_keycode = int(data["key"]) as Key
		key.location = int(data.get("location", KEY_LOCATION_UNSPECIFIED)) as KeyLocation
		return key
	if data.has("mouse"):
		var mouse := InputEventMouseButton.new()
		mouse.button_index = int(data["mouse"]) as MouseButton
		return mouse
	if data.has("pad"):
		var pad := InputEventJoypadButton.new()
		pad.button_index = int(data["pad"]) as JoyButton
		pad.device = -1  # All devices: any connected controller.
		return pad
	return null


## Replaces the primary binding of the slot's kind on `action` with `event` (or adds it
## if that slot was empty), dropping any other copy of the same input on the action.
static func bind(action: StringName, pad: bool, event: InputEvent) -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	var replaced := false
	var next: Array[InputEvent] = []
	for existing: InputEvent in events:
		if not replaced and matches_slot(existing, pad):
			next.append(event)
			replaced = true
		elif to_data(existing) != to_data(event):
			next.append(existing)
	if not replaced:
		next.append(event)
	set_events(action, next)


static func set_events(action: StringName, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for event: InputEvent in events:
		InputMap.action_add_event(action, event)


## Other rebindable actions that share any input in `action`'s slot, so a
## double-booked key can be flagged.
static func conflicts(action: StringName, pad: bool) -> Array[StringName]:
	var mine: Array[Dictionary] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if matches_slot(event, pad):
			mine.append(to_data(event))
	var result: Array[StringName] = []
	if mine.is_empty():
		return result
	for other: StringName in actions():
		if other == action:
			continue
		for event: InputEvent in InputMap.action_get_events(other):
			if matches_slot(event, pad) and _overlaps_any(mine, to_data(event)):
				result.append(other)
				break
	return result


## True if `data` would fire on any input in `list` (see `overlaps`).
static func _overlaps_any(list: Array[Dictionary], data: Dictionary) -> bool:
	for mine: Dictionary in list:
		if overlaps(mine, data):
			return true
	return false


## True if two saved bindings can fire on the same input: identical, or the same key
## where at least one side is unsided (plain "Shift" overlaps "Left Shift").
static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	if not (a.has("key") and b.has("key")):
		return a == b
	if int(a["key"]) != int(b["key"]):
		return false
	var side_a := int(a.get("location", KEY_LOCATION_UNSPECIFIED))
	var side_b := int(b.get("location", KEY_LOCATION_UNSPECIFIED))
	return (
		side_a == KEY_LOCATION_UNSPECIFIED or side_b == KEY_LOCATION_UNSPECIFIED or side_a == side_b
	)


## The page label for `action`, falling back to a humanized action name.
static func label_for(action: StringName) -> String:
	for section: Dictionary in SECTIONS:
		for entry: Array in section["actions"]:
			if entry[0] == action:
				return str(entry[1])
	return str(action).capitalize()


## The slot's current binding text for the page, e.g. "Space / Wheel" or "Left stick".
static func slot_text(action: StringName, pad: bool) -> String:
	var text := InputLabels.action_label(action, pad)
	if pad and STICK_ACTIONS.has(action):
		return "Left stick" if text.is_empty() else "Left stick, " + text
	return text if not text.is_empty() else "—"


## The slot's bindings as glyphs, in the same order as `slot_text`. Empty if any
## binding has no glyph (the page shows `slot_text` then) or nothing is bound.
static func slot_glyphs(action: StringName, pad: bool) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	if pad and STICK_ACTIONS.has(action):
		result.append(Glyphs.named("Left stick"))
	if not InputMap.has_action(action):
		return result
	for event: InputEvent in InputMap.action_get_events(action):
		if InputLabels.is_pad(event) != pad:
			continue
		var glyph := Glyphs.for_event(event)
		var button := event as InputEventMouseButton
		# Like slot_text, either wheel direction reads as just "Wheel".
		if button and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			glyph = Glyphs.named("Wheel")
		if glyph == null:
			result.clear()
			return result
		if not result.has(glyph):
			result.append(glyph)
	return result
