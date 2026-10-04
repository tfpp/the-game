extends GutTest
## ui/npc_dialogue/npc_dialogue.gd: the reusable portrait + line + actions panel.

var _saved_device: int


func before_each() -> void:
	_saved_device = Controls.device
	Controls.device = Controls.Device.TOUCH


func after_each() -> void:
	await wait_process_frames(2)
	Controls.pause()
	Controls.device = _saved_device


func test_open_shows_speaker_line_and_actions_and_pauses() -> void:
	var dialogue := NpcDialogue.new()
	add_child_autofree(dialogue)
	var log: Array[String] = []
	dialogue.open(
		"Rusty",
		"Looking to trade?",
		[
			{"label": "Browse", "action": func() -> void: log.append("browse")},
			{"label": "Leave", "action": Callable(), "close": true},
		]
	)
	assert_true(dialogue.is_open())
	assert_true(dialogue.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_eq(dialogue.action_labels(), PackedStringArray(["Browse", "Leave"]))
	assert_eq((dialogue.find_child("Speaker", true, false) as Label).text, "Rusty")
	assert_eq(dialogue._monogram.text, "R", "No portrait shows the initial")
	(dialogue.find_child("Browse", true, false) as Button).pressed.emit()
	assert_eq(log, ["browse"])
	assert_true(dialogue.is_open())
	(dialogue.find_child("Leave", true, false) as Button).pressed.emit()
	assert_false(dialogue.is_open())
	assert_false(dialogue.is_in_group(&"modal_ui"))
	assert_true(Controls.gameplay_active())


func test_cancel_and_start_close_it() -> void:
	var dialogue := NpcDialogue.new()
	add_child_autofree(dialogue)
	dialogue.open("Bartender", "Hi.", [{"label": "Ask", "action": Callable()}])
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	dialogue._input(cancel)
	assert_false(dialogue.is_open())
	dialogue.open("Bartender", "Hi.", [{"label": "Ask", "action": Callable()}])
	Controls.menu_requested.emit()
	assert_false(dialogue.is_open())
	assert_false(Controls.gameplay_active(), "Start hands over to the pause menu")


func test_narrow_rule() -> void:
	assert_true(NpcDialogue.is_narrow(360, 640), "Phone portrait stacks")
	assert_true(NpcDialogue.is_narrow(560, 320))
	assert_false(NpcDialogue.is_narrow(1280, 720))
	assert_false(NpcDialogue.is_narrow(1024, 768), "4:3 tablet keeps the row")


func test_every_screen_keeps_the_panel_on_screen_with_44px_targets() -> void:
	for dimensions: Vector2i in [
		Vector2i(1920, 1080),
		Vector2i(2560, 1080),
		Vector2i(1024, 768),
		Vector2i(1366, 768),
		Vector2i(360, 640),
		Vector2i(640, 360),
	]:
		var window := Window.new()
		window.size = dimensions
		window.content_scale_size = Vector2i(1280, 720)
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		add_child_autofree(window)
		var dialogue := NpcDialogue.new()
		window.add_child(dialogue)
		var actions: Array = []
		for label: String in ["Buy", "Browse", "Ask", "Leave"]:
			actions.append({"label": label, "action": Callable()})
		dialogue.open("Bartender", "Evening. What'll it be?", actions)
		await wait_process_frames(4)
		var scale := window.get_stretch_transform().get_scale().x
		var canvas := window.get_visible_rect().size
		var rect := dialogue._panel.get_global_rect()
		assert_true(
			Rect2(Vector2.ZERO, canvas).grow(1.0).encloses(rect), "%s fits %s" % [rect, dimensions]
		)
		var narrow := NpcDialogue.is_narrow(dimensions.x, dimensions.y)
		assert_eq(dialogue._actions.columns, 1 if narrow else 4, str(dimensions))
		for button: Button in dialogue._actions.get_children():
			assert_gte(button.size.y * scale, 44.0, "%s target on %s" % [button.text, dimensions])
		dialogue.close(false)
