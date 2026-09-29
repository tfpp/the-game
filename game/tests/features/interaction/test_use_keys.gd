extends GutTest

const Interaction := preload("res://features/interaction/interaction.gd")


func test_end_and_e_trigger_use() -> void:
	var interaction: Node = autofree(Interaction.new())
	add_child(interaction)
	for code: Key in [KEY_E, KEY_END]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.pressed = true
		assert_true(ev.is_action_pressed(&"use"), "key %s should Use" % code)
