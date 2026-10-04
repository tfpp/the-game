extends CanvasLayer
## Private storage alongside carried items; click/tap works on every input scheme.

const THEME := preload("res://ui/theme/ui_theme.tres")
var _stash: VanStash
var _root: ColorRect
var _status: Label
var _count: Label
var _stored: Array[Button] = []
var _carried: Array[Button] = []
var _state := ""
var _pending := false
var _stored_box: VBoxContainer
var _carried_box: VBoxContainer
var _store_tab: Button
var _take_tab: Button
var _font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()


func _ready() -> void:
	layer = 22
	_build()
	Controls.menu_requested.connect(func() -> void: close(false))


func open(stash: VanStash) -> void:
	_stash = stash
	_pending = false
	_state = ""
	_root.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	_tab(true)
	_refresh()
	_store_tab.grab_focus()


func close(resume := true) -> void:
	var was_open := _root.visible
	_root.hide()
	_stash = null
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
	if was_open and resume and get_tree().get_first_node_in_group(&"modal_ui") == null:
		Controls.start()


func _input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed(&"release_mouse"):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	if not _root.visible:
		return
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if not is_instance_valid(_stash) or player == null or not _stash.can_use(player):
		close()
		return
	_refresh()


func _refresh() -> void:
	var hand := Hand.for_peer(get_tree(), multiplayer.get_unique_id())
	if hand == null or _stash == null:
		return
	var inventory := hand.inventory()
	var state := str([_stash.contents, _stash.message, _stash.loaded, inventory.snapshot()])
	if state == _state:
		return
	_state = state
	if _stash.message != "Saving transfer…":
		_pending = false
	_status.text = _stash.message
	_count.text = "YOUR VAN STASH   %d / 24" % _stash.contents.size()
	for index: int in 24:
		var id := _stash.contents[index] if index < _stash.contents.size() else ""
		_set_button(_stored[index], id, "STASH %02d" % [index + 1])
		_stored[index].disabled = id.is_empty() or _pending or not inventory.backpack.has("")
	for index: int in 12:
		var slot := index if index < 8 else 7 - index
		var id := inventory.item_at(slot)
		var title: String = (
			"BAG %d" % [slot + 1] if index < 8 else ["HAND", "SHIRT", "PANTS", "HAT"][index - 8]
		)
		_set_button(_carried[index], id, title)
		_carried[index].disabled = (
			id.is_empty() or _pending or not _stash.loaded or _stash.contents.size() >= 24
		)


func _set_button(button: Button, id: String, title: String) -> void:
	var definition := ItemCatalog.find(id)
	var item := definition.display_name if definition != null else "Empty"
	button.text = title + "\n\n" + item
	button.tooltip_text = item
	(button.get_child(0) as InventoryIcon).set_item(id)


func _move(deposit: bool, index: int) -> void:
	var hand := Hand.for_peer(get_tree(), multiplayer.get_unique_id())
	if hand == null or _stash == null or _pending:
		return
	var id := hand.inventory().item_at(index) if deposit else _stash.contents[index]
	_pending = true
	_stash.message = "Saving transfer…"
	_stash.request_transfer(deposit, index, id)
	_state = ""
	_refresh()


func _tab(deposit: bool) -> void:
	_carried_box.visible = deposit
	_stored_box.visible = not deposit
	_store_tab.button_pressed = deposit
	_take_tab.button_pressed = not deposit


func _build() -> void:
	_root = ColorRect.new()
	_root.color = Color(.025, .05, .075, .94)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = THEME
	_root.hide()
	add_child(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	_root.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)
	_count = _label(layout, "YOUR VAN STASH   0 / 24")
	_count.add_theme_font_size_override("font_size", 22)
	_label(layout, "Private to you · saved across restarts")
	_status = _label(layout, "")
	_status.add_theme_font_size_override("font_size", 16)
	var tabs := HBoxContainer.new()
	layout.add_child(tabs)
	_store_tab = _tab_button(tabs, "Store items", _tab.bind(true))
	_take_tab = _tab_button(tabs, "Take items", _tab.bind(false))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_stored_box = VBoxContainer.new()
	box.add_child(_stored_box)
	_label(_stored_box, "Tap a stored item to take it into your backpack.", true)
	var stored := GridContainer.new()
	stored.add_theme_constant_override("h_separation", 8)
	stored.add_theme_constant_override("v_separation", 8)
	_stored_box.add_child(stored)
	for index: int in 24:
		_stored.append(_item_button(stored, _move.bind(false, index)))
	_carried_box = VBoxContainer.new()
	box.add_child(_carried_box)
	_label(_carried_box, "Tap a carried item to store it in the van.", true)
	var carried := GridContainer.new()
	carried.add_theme_constant_override("h_separation", 8)
	carried.add_theme_constant_override("v_separation", 8)
	_carried_box.add_child(carried)
	for index: int in 12:
		_carried.append(_item_button(carried, _move.bind(true, index if index < 8 else 7 - index)))
	var close_button := Button.new()
	close_button.text = "Back to game"
	close_button.custom_minimum_size.y = 52
	close_button.add_theme_font_override("font", _font)
	close_button.pressed.connect(close)
	layout.add_child(close_button)
	get_viewport().size_changed.connect(_resize.bind(stored, carried))
	_resize(stored, carried)


func _resize(stored: GridContainer, carried: GridContainer) -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_font.set("oversampling", ui_scale)
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.size = logical / ui_scale
	var width := _root.size.x - 64
	stored.columns = clampi(int((width + 8) / 138), 2, 6)
	carried.columns = stored.columns


func _label(parent: Node, text: String, on_panel := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_color_override(
		"font_color", Color(.2, .12, .08) if on_panel else Color(.94, .94, .88)
	)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _tab_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", _font)
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 52
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _item_button(parent: Node, callback: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"SecondaryButton"
	button.custom_minimum_size = Vector2(130, 106)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 16)
	button.pressed.connect(callback)
	var icon := InventoryIcon.new()
	icon.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	icon.position = Vector2(-44, 8)
	icon.size = Vector2(36, 36)
	button.add_child(icon)
	parent.add_child(button)
	return button
