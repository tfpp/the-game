extends GutTest

const Console := preload("res://features/console/console.gd")
var console: Console
var saved_device: int


func before_each() -> void:
	saved_device = Controls.device
	Controls.device = Controls.Device.TOUCH
	Controls.start()
	console = Console.new()
	add_child_autofree(console)


func after_each() -> void:
	Controls.pause()
	Controls.device = saved_device


func test_modal_blocks_gameplay_and_closes_cleanly() -> void:
	console.esc_menu_open()
	assert_false(Controls.gameplay_active())
	assert_true(console.is_in_group(&"modal_ui"))
	console.close()
	assert_false(console.is_in_group(&"modal_ui"))
	assert_true(Controls.gameplay_active())


func test_completion_history_draft_and_clear() -> void:
	console.esc_menu_open()
	console.entry.text = "sens"
	console._suggest("sens")
	console._complete()
	assert_eq(console.entry.text, "sensitivity ")
	console._submit("help")
	console.entry.text = "draft"
	console._recall(-1)
	assert_eq(console.entry.text, "help")
	console._recall(1)
	assert_eq(console.entry.text, "draft")
	console._submit("clear")
	assert_eq(console.output.text, "")


func test_console_does_not_open_over_other_modal_or_repeat_key() -> void:
	var modal := Node.new()
	add_child_autofree(modal)
	modal.add_to_group(&"modal_ui")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_QUOTELEFT
	key.pressed = true
	console._input(key)
	assert_false(console.panel.visible)
	modal.remove_from_group(&"modal_ui")
	console._input(key)
	assert_true(console.panel.visible)
	key.echo = true
	console._input(key)
	assert_true(console.panel.visible)
	Controls.menu_requested.emit()
	assert_false(console.panel.visible)
