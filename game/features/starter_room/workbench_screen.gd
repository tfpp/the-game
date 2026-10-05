extends CanvasLayer
## Generated blueprint art beneath native, responsive and owner-only controls.

const ART := preload("res://assets/starter_room/workbench_blueprint.png")
const CREAM := Color("e5e9e7")
const MUTED := Color("a1b2ba")
const AMBER := Color("ddad62")
var _font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()
var _bench: GearWorkbench
var _root: Control
var _list: GridContainer
var _status: Label
var _back: Button
var _close: Button
var _fit_size := Vector2.ZERO
var _action: Button
var _body: BoxContainer
var _gear_column: VBoxContainer
var _hero: Control
var _preview: InventoryIcon
var _name: Label
var _grade: Label
var _damage: Label
var _benefit: Label
var _scrap: Label
var _electronics: Label
var _selected_slot := -99


func _ready() -> void:
	layer = 21
	_root = PanelContainer.new()
	var background := _style(Color("0b141b"))
	background.set_content_margin_all(0)
	_root.add_theme_stylebox_override("panel", background)
	add_child(_root)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	_root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	_label(heading, "OPERATIONS GARAGE / PREPARATION", 12, AMBER)
	_label(heading, "Workshop upgrades", 27)
	_close = _button(header, "✕ Close", close)
	_close.size_flags_horizontal = Control.SIZE_SHRINK_END
	_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close.custom_minimum_size = Vector2(96, 48)
	_close.tooltip_text = "Close the workbench"
	_status = _label(column, "Select your gear to inspect a salvage tune.", 14, MUTED)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := BoxContainer.new()
	_body = body
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	_gear_column = VBoxContainer.new()
	_gear_column.add_theme_constant_override("separation", 10)
	body.add_child(_gear_column)
	_label(_gear_column, "YOUR GEAR", 12, MUTED)
	_list = GridContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 10)
	_list.add_theme_constant_override("v_separation", 10)
	_gear_column.add_child(_list)
	_build_details(body)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_action = _button(footer, "Install tune", _install, true)
	_action.custom_minimum_size.y = 60
	_back = _button(footer, "Back to garage", close)
	_back.custom_minimum_size.y = 60
	_root.hide()
	get_viewport().size_changed.connect(_resize)
	Controls.menu_requested.connect(func() -> void: close(false))
	_resize()


func _build_details(parent: Node) -> void:
	var panel := PanelContainer.new()
	_hero = panel
	var painted := StyleBoxTexture.new()
	painted.texture = ART
	for side: int in 4:
		painted.set_content_margin(side, 18)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", painted)
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	_preview = InventoryIcon.new()
	_preview.custom_minimum_size = Vector2(96, 112)
	row.add_child(_preview)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_label(title, "WORKSHOP TUNE", 12, AMBER)
	_name = _label(title, "", 23)
	_grade = _label(title, "", 14, MUTED)
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	column.add_child(stats)
	_damage = _stat(stats, "DAMAGE")
	_benefit = _stat(stats, "IMPROVEMENT")
	_label(column, "SALVAGE REQUIRED · FROM YOUR BACKPACK", 12, MUTED)
	var materials := HBoxContainer.new()
	materials.add_theme_constant_override("separation", 10)
	column.add_child(materials)
	_scrap = _material(materials, "scrap")
	_electronics = _material(materials, "electronics")
	_label(
		column, "One tune per firearm. Normal ammo and handling. Saved with your gear.", 13, MUTED
	)


func _stat(parent: Node, title: String) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color("10232dd9")))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_label(column, title, 11, MUTED)
	return _label(column, "", 19)


func _material(parent: Node, id: String) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color("10232dd9")))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var icon := InventoryIcon.new()
	icon.custom_minimum_size = Vector2(30, 40)
	icon.set_item(id)
	row.add_child(icon)
	var label := _label(row, "", 14)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_font.set("oversampling", ui_scale)
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_fit_size = logical / ui_scale
	_root.size = _fit_size
	var wide := _root.size.x >= 740
	_body.vertical = not wide
	_gear_column.custom_minimum_size.x = 230 if wide else 0
	_gear_column.size_flags_horizontal = Control.SIZE_FILL if wide else Control.SIZE_EXPAND_FILL
	_list.columns = 1 if wide else 2
	_preview.custom_minimum_size.y = 80 if wide else 112


func open(bench: GearWorkbench) -> void:
	_bench = bench
	_selected_slot = -99
	if not bench.changed.is_connected(_refresh):
		bench.changed.connect(_refresh)
	_root.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	_refresh()
	_back.grab_focus()


func close(resume := true) -> void:
	var was_open := _root.visible
	_root.hide()
	if is_instance_valid(_bench) and _bench.changed.is_connected(_refresh):
		_bench.changed.disconnect(_refresh)
	_bench = null
	remove_from_group(&"modal_ui")
	if was_open and resume and get_tree().get_first_node_in_group(&"modal_ui") == null:
		Controls.start()


func _fit() -> void:
	# Refreshed content can grow the panel past the screen; keep the buttons visible.
	if _root.visible and _root.size != _fit_size:
		_root.size = _fit_size


func _process(_delta: float) -> void:
	_fit()
	if _root.visible and is_instance_valid(_bench):
		var player := _bench.entity.player_for_peer(multiplayer.get_unique_id())
		if player != null and not _bench.can_use(player):
			close()


func _input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _selected() -> Dictionary:
	for item: Dictionary in _bench.items:
		if item["slot"] == _selected_slot:
			return item
	return _bench.items[0] if not _bench.items.is_empty() else {}


func _select(slot: int) -> void:
	_selected_slot = slot
	_refresh()
	if not _action.disabled:
		_action.grab_focus()


func _install() -> void:
	var item := _selected()
	if not item.is_empty() and item["available"] and not _bench.busy:
		_bench.request_upgrade(item["slot"], item["id"])


func _refresh() -> void:
	if _bench == null:
		return
	_fit.call_deferred()
	_status.text = _bench.message
	for node: Node in _list.get_children():
		_list.remove_child(node)
		node.queue_free()
	var selected := _selected()
	_hero.visible = not selected.is_empty()
	_action.disabled = selected.is_empty() or _bench.busy or not selected["available"]
	if selected.is_empty():
		_label(
			_list,
			"Bring a stock firearm to see its upgrade.\nCost: 2 Scrap + 1 Electronics.",
			16,
			MUTED
		)
		_action.text = "Bring your gear"
		return
	_selected_slot = selected["slot"]
	for item: Dictionary in _bench.items:
		var definition := ItemCatalog.find(item["id"])
		var button := _button(_list, definition.display_name, _select.bind(int(item["slot"])))
		button.custom_minimum_size.y = 106
		button.disabled = _bench.busy
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			var card := _style(
				Color("24404f") if item["slot"] == _selected_slot else Color("14242e")
			)
			card.set_content_margin(SIDE_TOP, 46)
			card.set_content_margin(SIDE_BOTTOM, 8)
			button.add_theme_stylebox_override(state, card)
		var icon := InventoryIcon.new()
		icon.set_item(item["id"])
		icon.custom_minimum_size = Vector2(36, 36)
		button.add_child(icon)
		icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		icon.position = Vector2(-18, 8)
		icon.size = Vector2(36, 36)
	var id: String = selected["id"]
	var gear := ItemCatalog.find(id)
	var tuned := id.begins_with("tuned:")
	_preview.set_item(id)
	_name.text = gear.display_name
	_grade.text = "Workshop grade · installed" if tuned else "Stock grade → Workshop grade"
	_damage.text = (
		"%.2f" % gear.damage if tuned else "%.2f → %.2f" % [gear.damage, gear.damage * 1.15]
	)
	_benefit.text = "Installed" if tuned else "+15%"
	_scrap.text = "Scrap\n%d / 2" % _bench.materials.get("scrap", 0)
	_electronics.text = "Electronics\n%d / 1" % _bench.materials.get("electronics", 0)
	_action.text = (
		"Saving…"
		if _bench.busy
		else (
			"Already tuned"
			if tuned
			else "Install tune" if selected["available"] else "Missing salvage"
		)
	)


func _label(parent: Node, text: String, font_size: int, color := CREAM) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("101a21") if primary else CREAM)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _style(AMBER if primary else Color("14242e")))
	button.add_theme_stylebox_override(
		"hover", _style(Color("edc58c") if primary else Color("284655"))
	)
	button.add_theme_stylebox_override(
		"pressed", _style(Color("bf9558") if primary else Color("284655"))
	)
	button.add_theme_stylebox_override("disabled", _style(Color("1b2930")))
	var focus := _style(Color("00000000"))
	focus.set_border_width_all(2)
	focus.border_color = AMBER
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	return style
