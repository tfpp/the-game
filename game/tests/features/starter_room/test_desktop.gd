extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
var _feature: Node3D
var _panel: GarageJobPanel
var _desktop: GarageDesktop


func before_each() -> void:
	_feature = FEATURE.instantiate()
	add_child_autofree(_feature)
	_panel = _feature.get_node("JobPanel")
	_panel.set_process(false)
	_desktop = _panel.desktop


func after_each() -> void:
	_panel.close(false)


func test_launch_switch_minimize_and_close_preserve_running_apps() -> void:
	_panel.open(_feature.get_node("Room/JobTerminal"))
	assert_eq(_desktop.active_app, "")
	_desktop._launchers["Notes"].pressed.emit()
	assert_eq(_desktop.active_app, "Notes")
	_desktop.launch_app("Calculator")
	assert_eq(_desktop.running, ["Notes", "Calculator"])
	assert_true(_desktop._windows["Notes"].visible)
	assert_true(_desktop._windows["Calculator"].visible)
	_desktop.minimize("Calculator")
	assert_eq(_desktop.active_app, "Notes")
	assert_true(_desktop._windows["Notes"].visible)
	assert_false(_desktop._windows["Calculator"].visible)
	assert_true(_desktop._tasks["Notes"].visible)
	_desktop._tasks["Notes"].pressed.emit()
	assert_eq(_desktop.active_app, "Notes")
	_desktop.close_app("Notes")
	assert_false(_desktop._tasks["Notes"].visible)
	assert_eq(_desktop.running, ["Calculator"])
	_desktop.launch_app("unknown")
	assert_eq(_desktop.active_app, "")
	assert_false(Controls.gameplay_active())


func test_documents_save_open_overwrite_delete_and_enforce_limits() -> void:
	assert_false(_desktop.save_file(" ", "hello"))
	assert_false(_desktop.save_file("x".repeat(33), "hello"))
	assert_false(_desktop.save_file("big", "x".repeat(4097)))
	_desktop.launch_app("Notes")
	_desktop._filename.text = "Plan"
	_desktop._editor.text = "Meet at the van"
	_desktop._save_note()
	assert_eq(_desktop.files["Plan"], "Meet at the van")
	_desktop._new_note()
	assert_eq(_desktop._editor.text, "")
	_desktop.launch_app("Files")
	_desktop.open_file("Plan")
	assert_eq(_desktop.active_app, "Notes")
	assert_eq(_desktop._editor.text, "Meet at the van")
	assert_true(_desktop.save_file("Plan", "Revised"))
	for i: int in 11:
		assert_true(_desktop.save_file(str(i), "note"))
	assert_false(_desktop.save_file("Full", "note"))
	assert_true(_desktop.save_file("Plan", "Still editable"))
	_desktop.delete_file("Plan")
	assert_false(_desktop.files.has("Plan"))
	assert_true(_desktop.save_file("New", "note"))
	assert_true(_feature.get_node("Room/JobTerminal").records.is_empty())


func test_logoff_preserves_private_files_but_session_change_clears_them() -> void:
	_desktop.save_file("Private", "local text")
	_panel.open(_feature.get_node("Room/JobTerminal"))
	_desktop.exit_requested.emit()
	assert_false(_panel.is_open())
	assert_false(_panel.is_in_group("modal_ui"))
	_panel.open(_feature.get_node("Room/JobTerminal"))
	assert_eq(_desktop.files["Private"], "local text")
	_panel._session_changed(Network.Mode.OFFLINE)
	assert_true(_desktop.files.is_empty())
	assert_true(_desktop.running.is_empty())
	assert_false(_panel.is_open())
	assert_eq(_desktop._editor.text, "")


func test_calculator_arithmetic_chaining_decimal_clear_and_zero_division() -> void:
	for key: String in ["1", "2", "+", "3", "*", "2", "="]:
		_desktop.calculator_key(key)
	assert_eq(_desktop._display.text.to_float(), 30.0)
	for key: String in ["C", "5", ".", ".", "5", "-", "2", "="]:
		_desktop.calculator_key(key)
	assert_eq(_desktop._display.text.to_float(), 3.5)
	for key: String in ["/", "0", "="]:
		_desktop.calculator_key(key)
	assert_eq(_desktop._display.text, "Cannot divide by zero")
	_desktop.calculator_key("4")
	assert_eq(_desktop._display.text, "4")
	for key: String in ["/", "2", "="]:
		_desktop.calculator_key(key)
	assert_eq(_desktop._display.text.to_float(), 2.0)


func test_existing_jobs_ui_is_inside_desktop_and_still_sends_validated_requests() -> void:
	var terminal := _feature.get_node("Room/JobTerminal") as GarageJobTerminal
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	player.name = "1"
	player.position = terminal.to_global(Vector3(0, 0, .8))
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	terminal.use()
	assert_true(_panel.is_open())
	_desktop.launch_app("Jobs")
	assert_true(_desktop._windows["Jobs"].is_ancestor_of(_panel._buttons[0]))
	_panel._buttons[0].pressed.emit()
	assert_eq(terminal.record(1)["job"], 0)
	_desktop.close_app("Jobs")
	assert_eq(terminal.record(1)["job"], 0)
	_desktop.launch_app("Files")
	_panel.close()
	_panel._update()
	assert_true(_panel._pin.visible)
	assert_eq(terminal.record(1)["xp"], 0)
