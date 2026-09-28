class_name InputLabels
extends RefCounted
## Player-facing names for input bindings ("W", "Left click", "A / Cross"), shared by
## the HUD's key hints and the Controls settings page so both follow rebinding.

const PAD_BUTTONS := {
	JOY_BUTTON_A: "A / Cross",
	JOY_BUTTON_B: "B / Circle",
	JOY_BUTTON_X: "X / Square",
	JOY_BUTTON_Y: "Y / Triangle",
	JOY_BUTTON_BACK: "Back / Select",
	JOY_BUTTON_GUIDE: "Home",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB / L1",
	JOY_BUTTON_RIGHT_SHOULDER: "RB / R1",
	JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_MISC1: "Share",
	JOY_BUTTON_TOUCHPAD: "Touchpad",
}

const MOUSE_BUTTONS := {
	MOUSE_BUTTON_LEFT: "Left click",
	MOUSE_BUTTON_RIGHT: "Right click",
	MOUSE_BUTTON_MIDDLE: "Middle click",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
	MOUSE_BUTTON_WHEEL_LEFT: "Wheel left",
	MOUSE_BUTTON_WHEEL_RIGHT: "Wheel right",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4",
	MOUSE_BUTTON_XBUTTON2: "Mouse 5",
}

const ARROW_KEYS := {
	KEY_UP: "Up arrow",
	KEY_DOWN: "Down arrow",
	KEY_LEFT: "Left arrow",
	KEY_RIGHT: "Right arrow",
}

const MOVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_left", &"move_back", &"move_right"]


## The platform's name for a modifier key ("Command" and "Option" on a Mac, "Ctrl",
## "Alt" and "Windows" on Windows), or "" for other keys.
static func modifier_name(code: Key) -> String:
	var mac := OS.has_feature("macos") or OS.has_feature("web_macos")
	var windows := OS.has_feature("windows") or OS.has_feature("web_windows")
	match code:
		KEY_SHIFT:
			return "Shift"
		KEY_CTRL:
			return "Control" if mac else "Ctrl"
		KEY_ALT:
			return "Option" if mac else "Alt"
		KEY_META:
			return "Command" if mac else ("Windows" if windows else "Super")
	return ""


## True for controller input; false for keyboard and mouse.
static func is_pad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


static func is_keyboard_or_mouse(event: InputEvent) -> bool:
	return event is InputEventKey or event is InputEventMouseButton


static func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if ARROW_KEYS.has(code):
			return str(ARROW_KEYS[code])
		var base := modifier_name(code)
		if base.is_empty():
			base = OS.get_keycode_string(code)
		match key.location:
			KEY_LOCATION_LEFT:
				return "Left " + base
			KEY_LOCATION_RIGHT:
				return "Right " + base
		return base
	if event is InputEventMouseButton:
		var index := (event as InputEventMouseButton).button_index
		return str(MOUSE_BUTTONS.get(index, "Mouse %d" % index))
	if event is InputEventJoypadButton:
		var button := (event as InputEventJoypadButton).button_index
		return str(PAD_BUTTONS.get(button, "Button %d" % button))
	return event.as_text()


## The action's bindings for one kind of device, joined with " / ". Both wheel
## directions together read as just "Wheel". Empty if nothing is bound.
static func action_label(action: StringName, pad: bool) -> String:
	if not InputMap.has_action(action):
		return ""
	var labels: Array[String] = []
	for event: InputEvent in InputMap.action_get_events(action):
		if is_pad(event) != pad:
			continue
		var label := event_label(event)
		if label in ["Wheel up", "Wheel down"]:
			label = "Wheel"
		if not labels.has(label):
			labels.append(label)
	return " / ".join(labels)


## HUD hint for walking: "Left stick" on a controller, "Arrow keys" for the arrows, or
## the four keys in forward-left-back-right order ("W A S D").
static func movement_label(pad: bool) -> String:
	if pad:
		return "Left stick"
	var keys: Array[String] = []
	var arrows := true
	for action: StringName in MOVE_ACTIONS:
		var first := _first_label(action)
		arrows = arrows and first.ends_with(" arrow")
		keys.append(first if not first.is_empty() else "?")
	return "Arrow keys" if arrows else " ".join(keys)


static func _first_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		if is_keyboard_or_mouse(event):
			return event_label(event)
	return ""
