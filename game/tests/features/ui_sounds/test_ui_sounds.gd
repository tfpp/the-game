extends GutTest
## `features/ui_sounds/`: menu buttons click, toggles switch, hover taps.

const UiSounds := preload("res://features/ui_sounds/ui_sounds.gd")

var _sounds: Node
var _cues: Array[StringName] = []


func before_each() -> void:
	_cues.clear()
	_sounds = UiSounds.new()
	add_child_autofree(_sounds)
	_sounds.played.connect(func(cue: StringName) -> void: _cues.append(cue))


func test_buttons_added_later_click_and_toggles_switch() -> void:
	var button := Button.new()
	add_child_autofree(button)
	var toggle := CheckButton.new()
	add_child_autofree(toggle)
	button.pressed.emit()
	toggle.pressed.emit()
	assert_eq(_cues, [&"click", &"switch"] as Array[StringName])


func test_hover_taps_unless_disabled_or_muted() -> void:
	var button := Button.new()
	add_child_autofree(button)
	button.mouse_entered.emit()
	button.disabled = true
	button.mouse_entered.emit()
	button.disabled = false
	button.set_meta(UiSounds.MUTE_META, true)
	button.mouse_entered.emit()
	button.pressed.emit()
	assert_eq(_cues, [&"hover"] as Array[StringName])


func test_voices_are_capped() -> void:
	for index: int in UiSounds.MAX_VOICES + 3:
		_sounds.play(&"click")
	assert_eq(_sounds.get_child_count(), UiSounds.MAX_VOICES)


func test_buttons_are_hooked_once() -> void:
	var button := Button.new()
	add_child_autofree(button)
	_sounds._hook(button)
	button.pressed.emit()
	assert_eq(_cues.size(), 1)
