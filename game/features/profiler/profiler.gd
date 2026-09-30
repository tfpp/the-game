extends CanvasLayer
## Local-only diagnostics; never requests or changes shared gameplay state.

const Capture := preload("res://features/profiler/frame_capture.gd")
const Graph := preload("res://features/profiler/frame_graph.gd")

var capture := Capture.new()
var graph: Graph
var panel: PanelContainer
var rows: ItemList
var details: RichTextLabel
var status: Label
var selected_trace: Dictionary = {}
var _listed: Array[Dictionary] = []
var _refresh_elapsed := 0.0


func _ready() -> void:
	layer = 11
	add_to_group(&"frame_profiler")
	add_to_group(&"esc_menu_links")
	_build()
	Controls.menu_requested.connect(_menu_requested)
	set_process(false)


func _exit_tree() -> void:
	_disconnect_capture()
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
		Controls.start()


func set_enabled(value: bool) -> void:
	if capture.enabled == value:
		return
	capture.enabled = value
	capture.restart_interval()
	graph.visible = value
	set_process(value)
	if value:
		get_tree().process_frame.connect(_boundary)
		get_tree().physics_frame.connect(_physics)
		RenderingServer.frame_pre_draw.connect(_pre_draw)
		RenderingServer.frame_post_draw.connect(_post_draw)
	else:
		_disconnect_capture()
	_refresh()


func set_budget(value: float) -> bool:
	if not is_finite(value) or value < 1.0 or value > 1000.0:
		return false
	capture.budget_ms = value
	# Do not classify an in-flight interval against a newly changed budget.
	capture.restart_interval()
	_refresh()
	return true


func clear_capture() -> void:
	capture.reset()
	selected_trace.clear()
	details.text = "Select a missed frame to inspect its captured trace."
	_refresh()


func esc_menu_label() -> String:
	return "Profiler"


func esc_menu_open() -> void:
	panel.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	_refresh()
	rows.grab_focus()


func close(resume: bool = true) -> void:
	panel.hide()
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func select_frame(index: int) -> void:
	if index < 0 or index >= _listed.size():
		return
	# Pin the data, not a live ring-buffer index, while new misses arrive.
	selected_trace = _listed[index].duplicate(true)
	details.text = Capture.trace_text(selected_trace)


func _input(event: InputEvent) -> void:
	if panel.visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _menu_requested() -> void:
	if panel.visible:
		close(false)


func _process(delta: float) -> void:
	_refresh_elapsed += delta
	if _refresh_elapsed >= 0.25:
		_refresh_elapsed = 0.0
		_refresh()


func _boundary() -> void:
	capture.boundary(Time.get_ticks_usec(), Engine.get_process_frames())


func _physics() -> void:
	capture.mark("Physics tick begins", Time.get_ticks_usec())


func _pre_draw() -> void:
	capture.mark("RenderingServer pre-draw", Time.get_ticks_usec())


func _post_draw() -> void:
	capture.mark(
		"RenderingServer post-draw (CPU submission, not GPU completion)", Time.get_ticks_usec()
	)


func _disconnect_capture() -> void:
	if get_tree() == null:
		return
	for pair: Array in [
		[get_tree().process_frame, _boundary],
		[get_tree().physics_frame, _physics],
		[RenderingServer.frame_pre_draw, _pre_draw],
		[RenderingServer.frame_post_draw, _post_draw],
	]:
		var source: Signal = pair[0]
		var callback: Callable = pair[1]
		if source.is_connected(callback):
			source.disconnect(callback)


func _refresh() -> void:
	graph.samples = capture.frames
	graph.budget_ms = capture.budget_ms
	graph.queue_redraw()
	status.text = (
		"%s | %.2f ms budget | %d misses (latest %d retained)"
		% [
			"Recording" if capture.enabled else "Disabled",
			capture.budget_ms,
			capture.total_misses,
			capture.misses.size()
		]
	)
	if not panel.visible:
		return
	_listed = capture.misses.duplicate()
	_listed.reverse()
	var scroll := rows.get_v_scroll_bar().value
	rows.clear()
	for frame: Dictionary in _listed:
		rows.add_item(
			(
				"#%d: %.3f ms (+%.3f ms)"
				% [
					frame["id"],
					frame["duration_ms"],
					float(frame["duration_ms"]) - float(frame["budget_ms"])
				]
			)
		)
		if not selected_trace.is_empty() and frame["id"] == selected_trace["id"]:
			rows.select(rows.item_count - 1)
	rows.get_v_scroll_bar().value = scroll


func _build() -> void:
	graph = Graph.new()
	graph.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	graph.offset_left = -268
	graph.offset_right = -8
	graph.offset_top = 90
	graph.offset_bottom = 190
	graph.hide()
	add_child(graph)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 8
	panel.offset_right = -8
	panel.offset_top = 8
	panel.offset_bottom = -8
	panel.theme = preload("res://ui/theme/ui_theme.tres")
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var help := Label.new()
	help.text = (
		"Console: profiler 1 / 0; profiler_budget <ms>; profiler_clear.\n"
		+ "Select a miss below. Trace gaps include pacing; render markers may be absent."
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	rows = ItemList.new()
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.size_flags_stretch_ratio = 0.6
	rows.item_selected.connect(select_frame)
	box.add_child(rows)
	details = RichTextLabel.new()
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.selection_enabled = true
	details.text = "Select a missed frame to inspect its captured trace."
	box.add_child(details)
	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(clear_capture)
	buttons.add_child(clear)
	var done := Button.new()
	done.text = "Close"
	done.pressed.connect(close)
	buttons.add_child(done)
	panel.hide()
	_refresh()
