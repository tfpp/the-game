extends CanvasLayer
## Pawn counter presentation. Purchases and reserved sales stay server-owned.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const HEADING_FONT := preload("res://assets/fonts/exo2/Exo2-Bold.ttf")
const PANEL_ART := preload("res://assets/pawn_shop/ui/trade_panel.png")

var entity: NetworkedEntity
var _panel: PanelContainer
var _ours: GridContainer
var _empty_sell: Label
var _theirs: GridContainer
var _wallet: Label
var _status: Label
var _retry: Button
var _pending := false
var _signature := ""
var _ammo := false


func _ready() -> void:
	layer = 10
	entity = NetworkedEntity.new()
	entity.name = "Trade"
	add_child(entity)
	entity.register_action(&"buy", _may_buy, _buy)
	entity.register_action(&"sell", _may_sell, _sell)
	entity.event_received.connect(_event)
	entity.request_finished.connect(_finished)
	Controls.menu_requested.connect(close_menu.bind(false))
	Network.mode_changed.connect(_reset)
	_build()


func _near(peer: int) -> bool:
	var fence := get_parent() as LootFence
	var player := fence._player_for_peer(peer)
	return player != null and fence.can_use(player)


func _may_buy(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 1 or not payload.get("id") is String or not _near(peer):
		return false
	for entry: Dictionary in GunBuyCatalog.entries(0) + GunBuyCatalog.entries(8):
		if entry["id"] == payload["id"]:
			return true
	return false


func _may_sell(peer: int, payload: Dictionary) -> bool:
	return (
		payload.size() == 2
		and payload.get("slot") is int
		and payload.get("id") is String
		and _near(peer)
		and int(payload["slot"]) >= -1
		and int(payload["slot"]) < PlayerInventory.CAPACITY
	)


func _buy(peer: int, payload: Dictionary) -> bool:
	_complete_buy(peer, str(payload["id"]))
	return true


func _complete_buy(peer: int, id: String) -> void:
	var machine := get_tree().get_first_node_in_group(&"gun_machine_root") as GunMachine
	var message := "Shop unavailable."
	if machine != null:
		message = await machine.purchase(peer, id)
		if message == "Session ended":
			return
		if message.is_empty():
			message = "Purchased. Guns include one matching ammo box."
	entity.send_event(&"receipt", {"text": message}, peer)


func _sell(peer: int, payload: Dictionary) -> bool:
	_complete_sell(peer, int(payload["slot"]), str(payload["id"]))
	return true


func _complete_sell(peer: int, slot: int, id: String) -> void:
	var fence := get_parent() as LootFence
	var message: String = await fence.sell_selected(peer, slot, id)
	if message == "Session ended.":
		return
	entity.send_event(&"receipt", {"text": message}, peer)


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"open":
		open_menu()
	elif event == &"receipt":
		_pending = false
		_status.text = str(payload.get("text", ""))
		_retry.visible = _status.text.begins_with("Sale pending")
		_signature = ""


func _finished(action: StringName, result: int) -> void:
	if action in [&"buy", &"sell"] and result != NetworkedEntity.Result.ACCEPTED:
		_pending = false
		_status.text = "Trade denied. Stay near the counter and try again."
		_signature = ""


func open_menu() -> void:
	if get_tree().get_first_node_in_group(&"modal_ui") != null:
		return
	add_to_group(&"modal_ui")
	Controls.pause()
	_panel.show()
	_signature = ""


func close_menu(resume: bool = true) -> void:
	if _panel == null or not _panel.visible:
		return
	_panel.hide()
	remove_from_group(&"modal_ui")
	if resume and get_tree().get_first_node_in_group(&"modal_ui") == null:
		Controls.start()


func _input(event: InputEvent) -> void:
	if _panel.visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close_menu()


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	_resize()
	var peer := multiplayer.get_unique_id()
	if not _near(peer):
		close_menu()
		return
	var hand := Hand.for_peer(get_tree(), peer)
	if hand == null:
		close_menu()
		return
	var money := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var balance := int(money.balances.get(peer, 0)) if money != null else 0
	_wallet.text = "WALLET  " + PlayerMoney.format_money(balance)
	var signature := (
		str(hand.inventory().backpack)
		+ hand.net_item_id
		+ str(balance)
		+ str(_pending)
		+ str(_ammo)
	)
	if signature == _signature:
		return
	_signature = signature
	_refresh(hand.inventory(), balance)


func _refresh(inventory: PlayerInventory, balance: int) -> void:
	for box: GridContainer in [_ours, _theirs]:
		for child: Node in box.get_children():
			box.remove_child(child)
			child.queue_free()
	var count := 0
	for slot: int in range(-1, PlayerInventory.CAPACITY):
		var id := inventory.item_at(slot)
		var definition := ItemCatalog.find(id)
		if definition == null:
			continue
		var accepted := definition.sale_value_cents > 0
		if accepted:
			count += 1
		var text := (
			"Sell · " + PlayerMoney.format_money(definition.sale_value_cents)
			if accepted
			else "Not accepted"
		)
		_row(
			_ours,
			id,
			definition.display_name,
			"In hand" if slot == -1 else "Backpack %d" % (slot + 1),
			text,
			_request.bind(&"sell", {"slot": slot, "id": id}),
			_pending or not accepted
		)
	_empty_sell.visible = count == 0
	(_ours.get_parent() as ScrollContainer).visible = count > 0
	for entry: Dictionary in GunBuyCatalog.entries(8 if _ammo else 0):
		var id: String = entry["id"]
		_row(
			_theirs,
			id,
			entry["name"],
			"Ammunition pack" if _ammo else "Includes 1 ammo box",
			"Buy · " + PlayerMoney.format_money(entry["price"]),
			_request.bind(&"buy", {"id": id}),
			_pending or balance < int(entry["price"])
		)


func _request(action: StringName, payload: Dictionary) -> void:
	if _pending:
		return
	_pending = true
	_status.text = "Processing trade…"
	entity.request_action(action, payload)


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.theme = UI_THEME
	_panel.hide()
	add_child(_panel)
	var style := StyleBoxTexture.new()
	style.texture = PANEL_ART
	style.texture_margin_left = 72
	style.texture_margin_top = 104
	style.texture_margin_right = 112
	style.texture_margin_bottom = 72
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	_panel.add_child(body)
	var heading := _label(body, "RUSTY HOGG’S PAWN SHOP")
	heading.add_theme_font_size_override("font_size", 26)
	_wallet = _label(body, "WALLET")
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)
	_ours = _column(columns, "YOUR ITEMS", "Sell pawnable materials and valuables")
	_empty_sell = _label(_ours.get_parent().get_parent(), "Nothing to sell")
	_empty_sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_sell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_sell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_sell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_sell.hide()
	_theirs = _column(columns, "SHOP STOCK", "Buy guns and matching ammunition")
	var tabs := HBoxContainer.new()
	var stock_column := _theirs.get_parent().get_parent()
	stock_column.add_child(tabs)
	stock_column.move_child(tabs, 2)
	_button(tabs, "Guns", func() -> void: _ammo = false)
	_button(tabs, "Ammunition", func() -> void: _ammo = true)
	_status = _label(body, "Select Buy or Sell. Weapons, clothing and ammo cannot be pawned.")
	_retry = _button(body, "Retry pending sale", _request.bind(&"sell", {"slot": -1, "id": ""}))
	_retry.hide()
	_button(body, "Close · Esc", close_menu)
	get_viewport().size_changed.connect(_resize)
	_resize()


func _column(parent: Node, title: String, subtitle: String) -> GridContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.0
	parent.add_child(column)
	_label(column, title).add_theme_font_size_override("font_size", 20)
	_label(column, subtitle)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows := GridContainer.new()
	rows.columns = 2
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("h_separation", 10)
	rows.add_theme_constant_override("v_separation", 10)
	scroll.add_child(rows)
	return rows


func _row(
	parent: Node,
	id: String,
	title: String,
	subtitle: String,
	action: String,
	callback: Callable,
	disabled: bool
) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(130, 238)
	card.tooltip_text = ItemCatalog.find(id).loot_details()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c2933")
	style.border_color = Color("455663")
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var icon := InventoryIcon.new()
	icon.custom_minimum_size.y = 112
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.set_item(id)
	box.add_child(icon)
	var name_label := _label(box, title)
	name_label.add_theme_font_override("font", HEADING_FONT)
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.custom_minimum_size.y = 44
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var detail := _label(box, subtitle)
	detail.add_theme_font_size_override("font_size", 13)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_color_override("font_color", Color("9aa9b3"))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_button(box, action, callback).disabled = disabled


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", ThemeDB.fallback_font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("e8dfc9"))
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("25313a") if state == "normal" else Color("3a463e")
		if state == "disabled":
			style.bg_color = Color("192025")
		style.border_color = Color("8c7950")
		style.set_border_width_all(1 if state != "disabled" else 0)
		style.set_content_margin_all(8)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _resize() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_panel.size = Vector2(minf(1000, viewport_size.x - 24), minf(720, viewport_size.y - 24))
	_panel.position = (viewport_size - _panel.size) * 0.5
	if _ours != null:
		var columns := 2 if viewport_size.x >= 850 else 1
		_ours.columns = columns
		_theirs.columns = columns


func _reset(_mode: Network.Mode) -> void:
	close_menu(false)
	_pending = false
	_signature = ""
	_retry.hide()
