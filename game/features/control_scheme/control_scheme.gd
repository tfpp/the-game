extends Node
## The "Controls" page of the Settings menu (`features/settings/`): handedness
## presets, look sensitivity for mouse, controller and touch, and per-action rebinding
## for keyboard & mouse and controllers. The page itself is `controls_page.gd`; the
## action catalog and rebinding helpers are `input_bindings.gd`.
##
## Input defaults to the classic right-handed layout (WASD to move, Space to jump),
## except for the account "DoctorDalek", who defaults to left-handed (arrow keys, Shift)
## instead. That account name isn't known yet when this feature loads (features load
## before networking starts), so a fresh install applies the right-handed guess right
## away and corrects it once the local player's account name arrives from the server,
## unless the player has already changed a control by hand in the meantime.
##
## Everything persists locally per install through `SettingsStore` ("controls"):
## {"scheme", "sensitivity", "stick_scale", "touch_scale", "bindings"}, where bindings
## maps an action to its rebound slots: {"kbm": {...}, "pad": {...}}.

const Bindings := preload("res://features/control_scheme/input_bindings.gd")
const ControlsPage := preload("res://features/control_scheme/controls_page.gd")
const SETTINGS_PAGES_GROUP := &"settings_pages"
const STORE_NAME := "controls"
const DOCTOR_DALEK_NAME := "DoctorDalek"

## The slot waiting for a new input: {"action": StringName, "pad": bool}, or empty.
var capture: Dictionary = {}
## True on a fresh install until the local player's account name is known, so the
## guessed default can still be corrected for DoctorDalek before anyone notices.
var _default_pending := false
## Rebound slots, as saved: action -> {"kbm": data, "pad": data}.
var _overrides: Dictionary = {}
## Each rebound action's bindings before any override, for "Reset all bindings".
var _defaults: Dictionary = {}
var _page: ControlsPage


func _ready() -> void:
	add_to_group(SETTINGS_PAGES_GROUP)
	_load()
	# Other features register their actions in their own _ready, possibly after this
	# one, so apply rebinds once they all have.
	apply_overrides.call_deferred()


func _process(_delta: float) -> void:
	if _default_pending:
		_resolve_default()


func settings_page_label() -> String:
	return "Controls"


func settings_page_build() -> Control:
	capture = {}
	_page = ControlsPage.new(self)
	return _page


## While a slot is waiting for input, the next bindable press becomes its binding.
## Esc cancels. Returns true when the event was used.
func settings_page_input(event: InputEvent) -> bool:
	if capture.is_empty():
		return false
	var pad: bool = capture["pad"]
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		if event.is_pressed():
			cancel_capture()
		return true
	if Bindings.is_bindable(event, pad):
		rebind(capture["action"], pad, event)
		return true
	if pad and event is InputEventMouseButton:
		# Clicking elsewhere while waiting for a controller button gives up on it.
		cancel_capture()
		return false
	# Swallow everything else that could trigger the UI (releases, other devices).
	return (
		event is InputEventKey
		or event is InputEventJoypadButton
		or (not pad and event is InputEventMouseButton)
	)


func begin_capture(action: StringName, pad: bool) -> void:
	var same: bool = capture.get("action", &"") == action and capture.get("pad", false) == pad
	capture = {} if same else {"action": action, "pad": pad}
	_refresh_page()


func cancel_capture() -> void:
	capture = {}
	_refresh_page()


## Binds `event` to the action's keyboard & mouse or controller slot and saves it.
func rebind(action: StringName, pad: bool, event: InputEvent) -> void:
	var data := Bindings.to_data(event)
	if data.is_empty():
		return
	_default_pending = false
	_snapshot(action)
	Bindings.bind(action, pad, Bindings.from_data(data))
	var slots: Dictionary = _overrides.get(str(action), {})
	slots["pad" if pad else "kbm"] = data
	_overrides[str(action)] = slots
	capture = {}
	_save()
	_refresh_page()


## Picks a handedness preset: movement and jump keys go back to that preset's layout,
## other bindings (including controller ones) are kept.
func set_scheme(scheme: Controls.Scheme) -> void:
	_default_pending = false
	for action: StringName in Bindings.SCHEME_ACTIONS:
		var slots: Dictionary = _overrides.get(str(action), {})
		slots.erase("kbm")
		if slots.is_empty():
			_overrides.erase(str(action))
	_apply_scheme(scheme)
	_save()
	_refresh_page()


## Puts every binding back to its default for the current preset.
func reset_bindings() -> void:
	for action: String in _defaults:
		Bindings.set_events(StringName(action), _defaults[action])
	_defaults.clear()
	_overrides.clear()
	capture = {}
	Controls.apply_scheme(Controls.scheme)
	_save()
	_refresh_page()


func set_mouse_sensitivity(value: float) -> void:
	Controls.sensitivity = _clamp(value, ControlsPage.MOUSE_RANGE)
	_save()


func set_stick_scale(value: float) -> void:
	Controls.stick_sensitivity = (
		Controls.STICK_SENSITIVITY * _clamp(value, ControlsPage.SCALE_RANGE)
	)
	_save()


func set_touch_scale(value: float) -> void:
	Controls.touch_sensitivity = (
		Controls.TOUCH_SENSITIVITY * _clamp(value, ControlsPage.SCALE_RANGE)
	)
	_save()


## Re-applies every saved rebind on top of the current defaults.
func apply_overrides() -> void:
	for action: String in _overrides:
		if not InputMap.has_action(action):
			continue
		_snapshot(StringName(action))
		var slots: Dictionary = _overrides[action]
		for slot: String in ["kbm", "pad"]:
			if not slots.get(slot) is Dictionary:
				continue
			var event := Bindings.from_data(slots[slot])
			if event != null:
				Bindings.bind(StringName(action), slot == "pad", event)
	_refresh_page()


func _apply_scheme(scheme: Controls.Scheme) -> void:
	Controls.apply_scheme(scheme)
	# The preset rewrote these, so their defaults are whatever it set.
	for action: StringName in Bindings.SCHEME_ACTIONS:
		_defaults.erase(str(action))
	apply_overrides()


## Remembers an action's bindings before its first rebind.
func _snapshot(action: StringName) -> void:
	if not _defaults.has(str(action)):
		_defaults[str(action)] = InputMap.action_get_events(action).duplicate()


## Reads saved settings. A fresh install has nothing saved yet, so this guesses
## right-handed and flags the default as pending until `_resolve_default` can check the
## local player's account name.
func _load() -> void:
	var data := SettingsStore.load_data(STORE_NAME)
	_default_pending = not data.has("scheme")
	Controls.apply_scheme(
		(
			Controls.Scheme.LEFT_HANDED
			if str(data.get("scheme", "right")) == "left"
			else Controls.Scheme.RIGHT_HANDED
		)
	)
	Controls.sensitivity = _clamp(
		float(data.get("sensitivity", Controls.sensitivity)), ControlsPage.MOUSE_RANGE
	)
	Controls.stick_sensitivity = (
		Controls.STICK_SENSITIVITY
		* _clamp(float(data.get("stick_scale", 1.0)), ControlsPage.SCALE_RANGE)
	)
	Controls.touch_sensitivity = (
		Controls.TOUCH_SENSITIVITY
		* _clamp(float(data.get("touch_scale", 1.0)), ControlsPage.SCALE_RANGE)
	)
	var bindings: Variant = data.get("bindings", {})
	_overrides = (bindings as Dictionary).duplicate(true) if bindings is Dictionary else {}


## Corrects a still-pending default to left-handed once the local player's account name
## turns out to be DoctorDalek. A no-op until the local player exists and has a name
## (set by the server on spawn), and permanently skipped once the player has changed a
## control by hand (see `set_scheme` and `rebind`).
func _resolve_default() -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null or player.display_name.is_empty():
		return
	_default_pending = false
	if player.display_name == DOCTOR_DALEK_NAME:
		_apply_scheme(Controls.Scheme.LEFT_HANDED)
		_refresh_page()
	_save()


func _save() -> void:
	(
		SettingsStore
		. save_data(
			STORE_NAME,
			{
				"scheme": "right" if Controls.scheme == Controls.Scheme.RIGHT_HANDED else "left",
				"sensitivity": Controls.sensitivity,
				"stick_scale": Controls.stick_sensitivity / Controls.STICK_SENSITIVITY,
				"touch_scale": Controls.touch_sensitivity / Controls.TOUCH_SENSITIVITY,
				"bindings": _overrides,
			}
		)
	)


func _refresh_page() -> void:
	if is_instance_valid(_page) and _page.is_inside_tree():
		_page.refresh()


static func _clamp(value: float, bounds: Vector3) -> float:
	return clampf(value, bounds.x, bounds.y)
