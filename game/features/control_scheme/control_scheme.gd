extends CanvasLayer
## Defaults input to the classic right-handed layout (WASD to move, Space to jump),
## except for the account "DoctorDalek", who defaults to left-handed (arrow keys, Shift)
## instead. That account name isn't known yet when this feature loads (features load
## before networking starts), so a fresh install applies the right-handed guess right
## away and corrects it once the local player's account name arrives from the server,
## unless the player has already picked a scheme by hand in the meantime. Real play time
## (not wall-clock time since launch) unlocks switching to the other layout after
## UNLOCK_SECONDS; a small corner button then lets a player switch between the two.
## The unlocked progress and chosen scheme persist locally per install, the same way the
## account session does (`core/net/account_api.gd`): localStorage on the web, a
## ConfigFile natively.

const MODAL_GROUP := &"modal_ui"
const NATIVE_STORE := "user://controls.cfg"
const STORAGE_KEY := "the-game.controls"
const UNLOCK_SECONDS := 300.0
## Local saves are a nice-to-have, not shared state, so writes are worth throttling.
const SAVE_INTERVAL_S := 5.0
const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const DOCTOR_DALEK_NAME := "DoctorDalek"

var played_s := 0.0

var _panel: Control
var _status: Label
var _switch_button: Button
var _open_button: Button
var _save_in := SAVE_INTERVAL_S
## True on a fresh install until the local player's account name is known, so the
## guessed default can still be corrected for DoctorDalek before anyone notices.
var _default_pending := false


func _ready() -> void:
	layer = 9
	Controls.apply_scheme(_load())
	_build()
	_refresh()


func _process(delta: float) -> void:
	if _default_pending:
		_resolve_default()
	if Controls.gameplay_active():
		played_s += delta
		_save_in -= delta
		if _save_in <= 0.0:
			_save_in = SAVE_INTERVAL_S
			_save()
	_open_button.visible = not _other_modal_ui_open()
	if _panel.visible:
		_refresh()


func _input(event: InputEvent) -> void:
	if _panel.visible and event.is_action_pressed(&"release_mouse"):
		get_viewport().set_input_as_handled()
		_close()


func unlocked() -> bool:
	return played_s >= UNLOCK_SECONDS


## "m:ss" remaining before the other layout unlocks, floored at zero.
static func remaining_text(remaining_seconds: float) -> String:
	var whole := int(maxf(remaining_seconds, 0.0))
	return "%d:%02d" % [whole / 60, whole % 60]


func _other_modal_ui_open() -> bool:
	if is_in_group(MODAL_GROUP):
		return false
	return get_tree().get_first_node_in_group(MODAL_GROUP) != null


func _open() -> void:
	_panel.visible = true
	add_to_group(MODAL_GROUP)
	Controls.pause()
	_refresh()


func _close() -> void:
	_panel.visible = false
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	Controls.start()


func _toggle_scheme() -> void:
	if not unlocked():
		return
	_default_pending = false
	var next := (
		Controls.Scheme.LEFT_HANDED
		if Controls.scheme == Controls.Scheme.RIGHT_HANDED
		else Controls.Scheme.RIGHT_HANDED
	)
	Controls.apply_scheme(next)
	_save()
	_refresh()


func _refresh() -> void:
	var left_handed := Controls.scheme == Controls.Scheme.LEFT_HANDED
	_status.text = (
		"Left-handed: arrow keys to move, Shift to jump."
		if left_handed
		else "Right-handed: WASD to move, Space to jump."
	)
	if unlocked():
		_switch_button.disabled = false
		_switch_button.text = (
			"Switch to right-handed (WASD + Space)"
			if left_handed
			else "Switch to left-handed (arrows + Shift)"
		)
	else:
		_switch_button.disabled = true
		_switch_button.text = (
			"%s controls unlock after %s of play"
			% [
				"Right-handed" if left_handed else "Left-handed",
				remaining_text(UNLOCK_SECONDS - played_s),
			]
		)


## Reads saved progress and returns the scheme to start with. A fresh install has
## nothing saved yet, so this guesses right-handed and flags the default as pending
## until `_resolve_default` can check the local player's account name.
func _load() -> Controls.Scheme:
	var text := _load_value()
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not parsed is Dictionary:
		_default_pending = true
		return Controls.Scheme.RIGHT_HANDED
	var data := parsed as Dictionary
	played_s = maxf(float(data.get("played_s", 0.0)), 0.0)
	return (
		Controls.Scheme.RIGHT_HANDED
		if str(data.get("scheme", "")) == "right"
		else Controls.Scheme.LEFT_HANDED
	)


## Corrects a still-pending default to left-handed once the local player's account name
## turns out to be DoctorDalek. A no-op until the local player exists and has a name
## (set by the server on spawn), and permanently skipped once the player has picked a
## scheme by hand (see `_toggle_scheme`).
func _resolve_default() -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if player == null or player.display_name.is_empty():
		return
	_default_pending = false
	if player.display_name == DOCTOR_DALEK_NAME:
		Controls.apply_scheme(Controls.Scheme.LEFT_HANDED)
		_refresh()
	_save()


func _save() -> void:
	var data := {
		"played_s": played_s,
		"scheme": "right" if Controls.scheme == Controls.Scheme.RIGHT_HANDED else "left",
	}
	_save_value(JSON.stringify(data))


## Small persistent key/value store, mirroring `AccountApi.load_value`/`save_value`:
## localStorage on the web, a ConfigFile natively.
static func _load_value() -> String:
	if OS.has_feature("web"):
		var value: Variant = JavaScriptBridge.eval(
			"window.localStorage.getItem(%s) || ''" % JSON.stringify(STORAGE_KEY)
		)
		return str(value) if value != null else ""
	var config := ConfigFile.new()
	if config.load(NATIVE_STORE) != OK:
		return ""
	return str(config.get_value("handedness", "state", ""))


static func _save_value(value: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval(
			(
				"window.localStorage.setItem(%s, %s)"
				% [JSON.stringify(STORAGE_KEY), JSON.stringify(value)]
			)
		)
		return
	var config := ConfigFile.new()
	config.load(NATIVE_STORE)
	config.set_value("handedness", "state", value)
	config.save(NATIVE_STORE)


func _build() -> void:
	var corner := MarginContainer.new()
	corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_left = -132.0
	corner.offset_top = -60.0
	corner.offset_right = -12.0
	corner.offset_bottom = -12.0
	corner.theme = UI_THEME
	add_child(corner)
	_open_button = Button.new()
	_open_button.text = "Controls"
	_open_button.theme_type_variation = &"SecondaryButton"
	_open_button.pressed.connect(_open)
	corner.add_child(_open_button)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.08, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.theme = UI_THEME
	backdrop.visible = false
	add_child(backdrop)
	_panel = backdrop
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var box_panel := PanelContainer.new()
	box_panel.custom_minimum_size.x = 400.0
	center.add_child(box_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box_panel.add_child(box)
	var heading := Label.new()
	heading.text = "Controls"
	heading.theme_type_variation = &"HeadingLabel"
	box.add_child(heading)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_switch_button = Button.new()
	_switch_button.custom_minimum_size.y = 48
	_switch_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_switch_button.pressed.connect(_toggle_scheme)
	box.add_child(_switch_button)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"SecondaryButton"
	close.custom_minimum_size.y = 40
	close.pressed.connect(_close)
	box.add_child(close)
