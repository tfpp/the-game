extends GutTest

const Profiler := preload("res://features/profiler/profiler.gd")
const Commands := preload("res://features/console/commands.gd")
const Console := preload("res://features/console/console.gd")

var profiler: Profiler
var commands: Commands
var saved_device: int


func before_each() -> void:
	saved_device = Controls.device
	Controls.device = Controls.Device.TOUCH
	Controls.start()
	profiler = preload("res://features/profiler/feature.tscn").instantiate()
	add_child_autofree(profiler)
	commands = Commands.new(get_tree())


func after_each() -> void:
	profiler.set_enabled(false)
	profiler.close(false)
	Controls.pause()
	Controls.device = saved_device


func test_console_enable_disable_query_help_and_suggestions() -> void:
	assert_false(profiler.capture.enabled)
	assert_false(profiler.is_processing())
	assert_string_contains(commands.execute("help profiler"), "profiler_budget")
	assert_has(commands.suggestions("profiler "), "profiler 1")
	assert_has(commands.suggestions("profiler "), "profiler 0")
	commands.execute("PROFILER 1")
	assert_true(profiler.capture.enabled)
	assert_true(profiler.graph.visible)
	assert_true(get_tree().process_frame.is_connected(profiler._boundary))
	assert_string_contains(commands.execute("profiler"), "profiler 1")
	commands.execute("profiler 1")
	commands.execute("profiler 0")
	assert_false(profiler.capture.enabled)
	assert_false(profiler.graph.visible)
	assert_false(profiler.is_processing())
	assert_false(get_tree().process_frame.is_connected(profiler._boundary))
	assert_false(get_tree().physics_frame.is_connected(profiler._physics))
	assert_false(RenderingServer.frame_pre_draw.is_connected(profiler._pre_draw))
	assert_false(RenderingServer.frame_post_draw.is_connected(profiler._post_draw))


func test_commands_reject_invalid_values_without_mutating_state() -> void:
	for value: String in ["2", "-1", "on", "1 0", "nan"]:
		commands.execute("profiler " + value)
		assert_false(profiler.capture.enabled)
	for value: String in ["0", "-2", "1001", "NaN", "inf", "abc", "1 2"]:
		commands.execute("profiler_budget " + value)
		assert_almost_eq(profiler.capture.budget_ms, 1000.0 / 60.0, 0.0001)
	commands.execute("profiler_budget 8.333")
	assert_eq(profiler.capture.budget_ms, 8.333)
	assert_string_contains(commands.execute("profiler_budget"), "8.333")
	commands.execute("profiler_clear unexpected")
	assert_string_contains(commands.execute("profiler_budget 1000"), "1000.000")


func test_live_boundary_records_wall_time_and_disable_stops_sampling() -> void:
	commands.execute("profiler 1")
	# Supply an actual wall-clock start older than the budget; no game-time waits.
	profiler.capture.boundary(Time.get_ticks_usec() - 50000, 123)
	profiler._physics()
	profiler._pre_draw()
	profiler._post_draw()
	profiler._boundary()
	assert_eq(profiler.capture.misses.size(), 1)
	assert_eq(profiler.capture.misses[0]["id"], 123)
	assert_eq(profiler.capture.misses[0]["events"].size(), 4)
	commands.execute("profiler 0")
	var count := profiler.capture.frames.size()
	profiler._boundary()
	assert_eq(profiler.capture.frames.size(), count)


func test_real_process_signal_and_free_disconnect_capture() -> void:
	profiler.set_enabled(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_gt(profiler.capture.frames.size(), 0)
	profiler.set_enabled(false)
	var count := profiler.capture.frames.size()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(profiler.capture.frames.size(), count)
	var temporary := Profiler.new()
	add_child(temporary)
	temporary.set_enabled(true)
	var callback := Callable(temporary, "_boundary")
	assert_true(get_tree().process_frame.is_connected(callback))
	temporary.free()
	assert_false(get_tree().process_frame.is_connected(callback))


func test_inspector_pins_selected_trace_across_new_misses_and_eviction() -> void:
	profiler.capture.enabled = true
	profiler.capture.budget_ms = 1.0
	profiler.capture.boundary(0, 10)
	profiler.capture.mark("measured landmark", 500)
	profiler.capture.boundary(2000, 11)
	profiler.esc_menu_open()
	assert_true(profiler.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	# Same signal used by pointer taps and controller list selection.
	profiler.rows.item_selected.emit(0)
	var trace := profiler.details.text
	assert_string_contains(trace, "measured landmark")
	for frame: int in range(12, 150):
		profiler.capture.boundary(frame * 2000, frame)
	profiler._refresh()
	assert_eq(profiler.selected_trace["id"], 10)
	assert_eq(profiler.details.text, trace)
	assert_eq(profiler.rows.item_count, profiler.capture.MISS_LIMIT)
	commands.execute("profiler_clear")
	assert_true(profiler.capture.frames.is_empty())
	assert_true(profiler.capture.misses.is_empty())
	assert_true(profiler.selected_trace.is_empty())
	assert_eq(profiler.rows.item_count, 0)
	profiler.close()
	assert_false(profiler.is_in_group(&"modal_ui"))
	assert_true(Controls.gameplay_active())


func test_console_and_inspector_use_existing_modal_lifecycle() -> void:
	var console := Console.new()
	add_child_autofree(console)
	console.esc_menu_open()
	console._submit("profiler 1")
	assert_true(profiler.capture.enabled)
	assert_true(console.panel.visible)
	assert_false(profiler.panel.visible)
	console.close()
	assert_true(Controls.gameplay_active())
	assert_eq(profiler.graph.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	profiler.esc_menu_open()
	Controls.menu_requested.emit()
	assert_false(profiler.panel.visible)
	assert_false(profiler.is_in_group(&"modal_ui"))
	profiler.esc_menu_open()
	var event := InputEventAction.new()
	event.action = &"ui_cancel"
	event.pressed = true
	profiler._input(event)
	assert_false(profiler.panel.visible)
	assert_true(Controls.gameplay_active())
