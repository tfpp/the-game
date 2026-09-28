extends GutTest
## `features/control_scheme/input_glyphs.gd` and `Bindings.slot_glyphs`: the Controls
## page's key, mouse and controller glyphs, with a text fallback.

const Glyphs := preload("res://features/control_scheme/input_glyphs.gd")
const Bindings := preload("res://features/control_scheme/input_bindings.gd")
const TEST_ACTION := &"test_input_glyphs_action"


func after_each() -> void:
	if InputMap.has_action(TEST_ACTION):
		InputMap.erase_action(TEST_ACTION)


func test_keys_cut_their_tile_from_the_tilemap() -> void:
	var w := Glyphs.for_event(_key(KEY_W)) as AtlasTexture
	assert_not_null(w)
	# Tile 86: row 2, column 18 of a 34-column sheet of 16px tiles.
	assert_eq(w.region, Rect2(18 * 16, 2 * 16, 16, 16))
	assert_eq(Glyphs.for_event(_key(KEY_SHIFT)).get_size(), Vector2(32, 16), "Shift is wide")
	assert_eq(Glyphs.for_event(_key(KEY_ENTER)).get_size(), Vector2(32, 32), "Enter is 2x2")


func test_glyphs_are_shared() -> void:
	assert_same(Glyphs.for_event(_key(KEY_E)), Glyphs.for_event(_key(KEY_E)))


func test_sided_and_unknown_keys_have_no_glyph() -> void:
	var right_shift := _key(KEY_SHIFT)
	right_shift.location = KEY_LOCATION_RIGHT
	assert_null(Glyphs.for_event(right_shift), "a glyph can't show the side")
	assert_null(Glyphs.for_event(_key(KEY_F13)))


func test_mouse_and_pad_buttons() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	assert_not_null(Glyphs.for_event(click))
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	assert_not_null(Glyphs.for_event(pad))
	assert_not_null(Glyphs.named("Right stick"))
	assert_null(Glyphs.named("Keyboard & mouse"))


func test_slot_glyphs_collapse_the_wheel_like_slot_text() -> void:
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_WHEEL_UP
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	Controls.ensure_action(TEST_ACTION, [_key(KEY_SPACE), up, down])
	var glyphs := Bindings.slot_glyphs(TEST_ACTION, false)
	assert_eq(glyphs, [Glyphs.for_event(_key(KEY_SPACE)), Glyphs.named("Wheel")])
	assert_eq(Bindings.slot_glyphs(TEST_ACTION, true), [] as Array[Texture2D], "no pad binding")


func test_slot_glyphs_fall_back_to_text_when_any_binding_lacks_one() -> void:
	Controls.ensure_action(TEST_ACTION, [_key(KEY_K), _key(KEY_F13)])
	assert_true(Bindings.slot_glyphs(TEST_ACTION, false).is_empty())
	assert_eq(Bindings.slot_text(TEST_ACTION, false), "K / F13")


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
