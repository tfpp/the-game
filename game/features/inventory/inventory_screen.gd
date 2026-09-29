extends CanvasLayer
## Kenney panel/button theme, live avatar preview, keyboard/controller/touch access.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const BASKET_ICON := preload("res://assets/kenney/game-icons/PNG/White/1x/basket.png")
const EQUIP_ICON := preload("res://assets/kenney/game-icons/PNG/White/1x/checkmark.png")
const DROP_ICON := preload("res://assets/kenney/game-icons/PNG/White/1x/down.png")
## Below this window width the action buttons drop their icons to fit.
const ACTION_ICONS_MIN_WIDTH := 500.0

var _body_font: Font = ThemeDB.fallback_font.duplicate()
var _heading_font: Font = preload("res://assets/fonts/exo2/Exo2-Bold.ttf").duplicate()
var _panel: Control
var _preview: InventoryPreview
var _slots: Array[Button] = []
var _equipment: Array[Button] = []
var _selected := -2
var _title: Label
var _description: Label
var _count: Label
var _keys: Label
var _equip: Button
var _stow: Button
var _drop: Button
var _close_button: Button
var _last_state := ""
var _heading: Label
var _character: VBoxContainer
var _wallet: Label
var _inventory: PlayerInventory
var _stash: LootContainer
var _stash_box: VBoxContainer
var _stash_items: VBoxContainer
var _stash_status: Label
var _stash_buttons: Array[Button] = []


func _ready() -> void:
	layer = 9
	add_to_group(&"esc_menu_links")
	add_to_group(&"inventory_screen")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_I
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_BACK
	Controls.ensure_action(&"inventory", [key, pad])
	_build()
	Controls.menu_requested.connect(_dismiss)
	Network.mode_changed.connect(_on_mode_changed)


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	if _stash != null and not is_instance_valid(_stash):
		_close(false)
		return
	_refresh_wallet()
	var hand := Hand.for_peer(get_tree(), multiplayer.get_unique_id())
	var next := hand.inventory() if hand != null else null
	if next != _inventory:
		_last_state = ""
	_inventory = next
	if _inventory == null:
		_close(false)
		return
	var state := str(
		[
			_inventory.backpack,
			_inventory.shirt,
			_inventory.pants,
			_inventory.keys,
			hand.net_item_id,
			_stash.net_searched if _stash != null else false,
			_stash.net_contents if _stash != null else PackedStringArray(),
		]
	)
	if state != _last_state:
		_last_state = state
		_refresh()


func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if (
		_panel.visible
		and (event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"inventory"))
	):
		get_viewport().set_input_as_handled()
		_close(true)
	elif event.is_action_pressed(&"inventory") and Controls.gameplay_active():
		get_viewport().set_input_as_handled()
		esc_menu_open()


func esc_menu_label() -> String:
	return "Inventory"


func esc_menu_icon() -> Texture2D:
	return BASKET_ICON


func esc_menu_open() -> void:
	_stash = null
	_show_inventory()


func open_stash(stash: LootContainer) -> void:
	_stash = stash
	_show_inventory()


func _show_inventory() -> void:
	var hand := Hand.for_peer(get_tree(), multiplayer.get_unique_id())
	if hand == null:
		return
	_inventory = hand.inventory()
	_panel.show()
	GameAudio.play_ui(self, &"open")
	add_to_group(&"modal_ui")
	Controls.pause()
	_last_state = ""
	_refresh()
	_refresh_wallet()
	if _stash == null:
		_equipment[1].grab_focus()


func _close(resume: bool = true) -> void:
	if _panel.visible and resume:
		GameAudio.play_ui(self, &"close")
	_panel.hide()
	_stash = null
	_stash_box.hide()
	_character.show()
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
	_preview.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_viewport().set_input_as_handled()
	if resume:
		Controls.start()


func _select(slot: int) -> void:
	_selected = slot
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_inventory):
		return
	var labels: Array[String] = ["HAND", "SHIRT", "PANTS"]
	for index: int in 3:
		var slot := -1 - index
		_equipment[index].text = "%s\n%s" % [labels[index], _item_name(_inventory.item_at(slot))]
		_equipment[index].button_pressed = _selected == slot
	var filled := 0
	for index: int in PlayerInventory.CAPACITY:
		var id := _inventory.backpack[index]
		if not id.is_empty():
			filled += 1
		_slots[index].text = "\n\n%s" % _item_name(id)
		(_slots[index].get_child(0) as InventoryIcon).set_item(id)
		_slots[index].tooltip_text = "Slot %d: %s" % [index + 1, _item_name(id)]
		_slots[index].button_pressed = _selected == index
	_count.text = "BACKPACK   %d / %d" % [filled, PlayerInventory.CAPACITY]
	var key_names := PackedStringArray()
	for id: String in _inventory.keys:
		key_names.append(_item_name(id))
	_keys.text = "KEY RING: " + ", ".join(key_names)
	_keys.visible = not key_names.is_empty()
	var item := _inventory.item_at(_selected)
	var clothing := not ClothingCatalog.slot(item).is_empty()
	_title.text = _item_name(item)
	_description.text = (
		"Collect other colors around the world to build your outfit."
		if clothing
		else "Equip, store or drop your items here."
	)
	if item.is_empty():
		_description.text = "Find items around the level and press Use to pick them up."
	_equip.disabled = _selected < 0 or item.is_empty()
	_stow.disabled = _selected >= 0 or item.is_empty() or not _inventory.backpack.has("")
	_drop.disabled = item.is_empty()
	_preview.model.set_skin_index(_inventory.hand().skin_tone_index())
	_preview.show_clothing(_inventory.shirt, _inventory.pants)
	_refresh_stash()


func _refresh_stash() -> void:
	_stash_box.visible = _stash != null
	_character.visible = _stash == null
	if _stash == null:
		return
	for button: Button in _stash_buttons:
		_stash_items.remove_child(button)
		button.queue_free()
	_stash_buttons.clear()
	if not _stash.net_searched:
		_stash_status.text = "Searching…"
		return
	if _stash.net_contents.is_empty():
		_stash_status.text = "Nothing left in this stash."
		return
	_stash_status.text = "Drag items into an empty backpack slot. Tap to take the next free slot."
	for index: int in _stash.net_contents.size():
		var id := _stash.net_contents[index]
		var button := _button(_stash_items, _item_name(id), _take_stash_item.bind(index))
		button.custom_minimum_size.y = 52
		button.set_drag_forwarding(_drag_stash.bind(index), Callable(), Callable())
		_stash_buttons.append(button)


func _drag_stash(_at: Vector2, index: int) -> Variant:
	if _stash == null or index >= _stash.net_contents.size():
		return null
	var id := _stash.net_contents[index]
	var preview := Label.new()
	preview.text = _item_name(id)
	preview.add_theme_font_override("font", _body_font)
	_stash_buttons[index].set_drag_preview(preview)
	return {"stash": _stash, "index": index, "id": id}


func _can_drop_on_bag(_at: Vector2, data: Variant, slot: int) -> bool:
	if not data is Dictionary or _stash == null or not is_instance_valid(_inventory):
		return false
	var claim := data as Dictionary
	var index := int(claim.get("index", -1))
	return (
		claim.get("stash") == _stash
		and index >= 0
		and index < _stash.net_contents.size()
		and _stash.net_contents[index] == str(claim.get("id", ""))
		and _inventory.backpack[slot].is_empty()
	)


func _drop_on_bag(_at: Vector2, data: Variant, slot: int) -> void:
	if not _can_drop_on_bag(Vector2.ZERO, data, slot):
		return
	var claim := data as Dictionary
	_stash.request_take(int(claim["index"]), slot, str(claim["id"]))


func _take_stash_item(index: int) -> void:
	if _stash == null or not is_instance_valid(_inventory):
		return
	var slot := _inventory.backpack.find("")
	if slot < 0:
		_stash_status.text = "Backpack full. Free a slot first."
		return
	if index < _stash.net_contents.size():
		_stash.request_take(index, slot, _stash.net_contents[index])


func _item_name(id: String) -> String:
	var item := ItemCatalog.find(id)
	return item.display_name if item != null else "Empty"


func _action(action: String) -> void:
	if not is_instance_valid(_inventory):
		return
	match action:
		"equip":
			_inventory.request_equip.rpc_id(1, _selected)
		"stow":
			_inventory.request_stow.rpc_id(1, _selected)
		"drop":
			_inventory.request_drop.rpc_id(1, _selected)
	_refresh()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.05, 0.075, 0.8)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.theme = UI_THEME
	backdrop.hide()
	add_child(backdrop)
	_panel = backdrop
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	backdrop.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	_heading = _label(header, "INVENTORY", true)
	_heading.add_theme_font_size_override("font_size", 22)
	var coin := InventoryIcon.new()
	coin.custom_minimum_size = Vector2(26, 32)
	coin.set_item("wallet")
	header.add_child(coin)
	_wallet = _label(header, "…")
	_wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wallet.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_wallet.clip_text = true
	_wallet.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_wallet.add_theme_font_size_override("font_size", 18)
	var hint := _label(box, "I / View for inventory  •  E / Use to search stashes")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var columns := HFlowContainer.new()
	columns.add_theme_constant_override("h_separation", 22)
	columns.add_theme_constant_override("v_separation", 14)
	scroll.add_child(columns)
	_character = VBoxContainer.new()
	var character := _character
	columns.add_child(character)
	_stash_box = VBoxContainer.new()
	_stash_box.custom_minimum_size.x = 240
	_stash_box.hide()
	columns.add_child(_stash_box)
	_label(_stash_box, "STASH", true).add_theme_font_size_override("font_size", 18)
	_stash_status = _label(_stash_box, "")
	_stash_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stash_scroll := ScrollContainer.new()
	stash_scroll.custom_minimum_size = Vector2(240, 250)
	_stash_box.add_child(stash_scroll)
	_stash_items = VBoxContainer.new()
	stash_scroll.add_child(_stash_items)
	_preview = InventoryPreview.new()
	character.add_child(_preview)
	_label(character, "YOUR CHARACTER", true).add_theme_font_size_override("font_size", 17)
	var outfit_hint := _label(character, "Find clothing to complete your outfit.")
	outfit_hint.add_theme_font_size_override("font_size", 14)
	outfit_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	for index: int in 3:
		var button := _button(character, "", _select.bind(-1 - index))
		button.toggle_mode = true
		button.custom_minimum_size.y = 54
		_equipment.append(button)
	var bag := VBoxContainer.new()
	bag.custom_minimum_size.x = 380
	bag.add_theme_constant_override("separation", 10)
	columns.add_child(bag)
	_count = _label(bag, "BACKPACK", true)
	_count.add_theme_font_size_override("font_size", 18)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	bag.add_child(grid)
	for index: int in PlayerInventory.CAPACITY:
		var button := _button(grid, "", _select.bind(index))
		button.custom_minimum_size = Vector2(89, 100)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var icon := InventoryIcon.new()
		icon.position = Vector2(10, 8)
		icon.size = Vector2(64, 34)
		button.add_child(icon)
		button.set_drag_forwarding(
			Callable(), _can_drop_on_bag.bind(index), _drop_on_bag.bind(index)
		)
		_slots.append(button)
	_keys = _label(bag, "")
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title = _label(bag, "", true)
	_title.add_theme_font_size_override("font_size", 20)
	_description = _label(bag, "")
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.y = 46
	var actions := HBoxContainer.new()
	bag.add_child(actions)
	_equip = _button(actions, "Equip", _action.bind("equip"))
	_stow = _button(actions, "Store", _action.bind("stow"))
	_drop = _button(actions, "Drop", _action.bind("drop"))
	_close_button = _button(box, "Back to game", _close)
	_close_button.theme_type_variation = &"Button"
	get_viewport().size_changed.connect(_resize.bind(panel, scroll, columns, bag))
	_resize(panel, scroll, columns, bag)


func _resize(
	panel: PanelContainer, scroll: ScrollContainer, columns: HFlowContainer, bag: VBoxContainer
) -> void:
	# A window can emit size_changed while its children are leaving the tree.
	if not is_inside_tree():
		return
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_body_font.set("oversampling", ui_scale)
	_heading_font.set("oversampling", ui_scale)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.size = logical / ui_scale
	var available := _panel.size - Vector2(36, 36)
	panel.custom_minimum_size.x = minf(available.x, 760)
	scroll.custom_minimum_size = Vector2(0, minf(available.y - 180, 535))
	columns.custom_minimum_size.x = maxf(210, panel.custom_minimum_size.x - 68)
	_character.custom_minimum_size.x = minf(260, columns.custom_minimum_size.x)
	_heading.add_theme_font_size_override("font_size", 18 if physical.x < 500 else 22)
	_preview.custom_minimum_size.y = 260 if physical.x >= 700 else 170
	bag.custom_minimum_size.x = minf(380, columns.custom_minimum_size.x)
	var icons := physical.x >= ACTION_ICONS_MIN_WIDTH
	_equip.icon = EQUIP_ICON if icons else null
	_stow.icon = BASKET_ICON if icons else null
	_drop.icon = DROP_ICON if icons else null
	var grid := _slots[0].get_parent() as GridContainer
	grid.columns = clampi(int((bag.custom_minimum_size.x + 6.0) / 95.0), 2, 4)


func _label(parent: Node, text: String, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _heading_font if heading else _body_font)
	if heading:
		label.theme_type_variation = &"HeadingLabel"
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"SecondaryButton"
	button.add_theme_font_override("font", _body_font)
	button.add_theme_font_size_override("font_size", 14)
	button.custom_minimum_size.y = 38
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _refresh_wallet() -> void:
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var peer := multiplayer.get_unique_id()
	var full := "…"
	var display := full
	if wallet != null and wallet.balances.has(peer):
		var cents := int(wallet.balances[peer])
		full = PlayerMoney.format_money(cents)
		display = full
		var width := _body_font.get_string_size(full, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		if _wallet.size.x > 0 and width > _wallet.size.x:
			# Keep the unit visible instead of clipping a number into a smaller amount.
			if absi(cents) >= 100000:
				display = compact_money(cents)
	var display_width := _body_font.get_string_size(display, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var font_size := clampi(int(18.0 * _wallet.size.x / maxf(display_width, 1.0)), 12, 18)
	_wallet.add_theme_font_size_override("font_size", font_size)

	_wallet.text = display
	_wallet.tooltip_text = "Wallet: " + full


func _dismiss() -> void:
	if _panel.visible:
		_close(false)


func _on_mode_changed(_mode: Network.Mode) -> void:
	_dismiss()
	_inventory = null
	_last_state = ""


static func compact_money(cents: int) -> String:
	var amount := float(cents) / 100.0
	var units: Array[String] = ["", "k", "M", "B", "T", "Q"]
	var unit := 0
	while absf(amount) >= 999.5 and unit < units.size() - 1:
		amount /= 1000.0
		unit += 1
	var format := "$%.0f%s" if absf(amount) >= 100.0 else "$%.1f%s"
	if absf(amount) < 10.0:
		format = "$%.2f%s"
	return format % [amount, units[unit]]
