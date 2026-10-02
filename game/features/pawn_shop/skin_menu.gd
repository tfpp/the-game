extends CanvasLayer
## Private collection UI. No local purchases, reward rolls or equipment writes.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
var _panel: Control
var _rows: VBoxContainer
var _status: Label
var _data := {}
var _page := "crates"
var _selected := "harbour"
var _revealing := false
var _reveal: PrawnSkinReveal
var _winner := ""

@onready var _owner: PrawnSkins = get_parent()


func _ready() -> void:
	layer = 10
	add_to_group(&"esc_menu_links")
	add_to_group(&"prawn_skin_menu")
	_build()
	Controls.menu_requested.connect(close)
	Network.mode_changed.connect(_session_changed)
	var entity := _owner.get_node("NetworkedEntity") as NetworkedInteraction
	entity.request_finished.connect(_request_finished)


func esc_menu_label() -> String:
	return "Prawn skins"


func esc_menu_open() -> void:
	# Keep a dismissible modal visible even if the server/storage is unavailable.
	receive(
		&"show",
		{
			"revision": -1,
			"document": PrawnSkinCatalog.empty_document(),
			"message": "Refreshing collection…"
		}
	)
	_owner.entity.request_action(&"collection")


func receive(event: StringName, payload: Dictionary) -> void:
	if event != &"show" and event != &"update":
		return
	_data = payload
	if event == &"show":
		_panel.show()
		add_to_group(&"modal_ui")
		Controls.pause()
		GameAudio.play_ui(self, &"open")
	if not _panel.visible:
		return
	var reward := str(payload.get("reward", ""))
	if not reward.is_empty() and PrawnSkinCatalog.SKINS.has(reward):
		_revealing = true
		_rebuild()
		_status.text = "Opening… (reward already saved)"
		_reveal.show()
		var weights: Array[int] = []
		weights.assign(_data.get("odds", PrawnSkinCatalog.DEFAULT_ODDS))
		_reveal.play(reward, weights)
		_winner = reward
	else:
		_rebuild()


func close(resume: bool = true) -> void:
	if not _panel.visible:
		return
	_panel.hide()
	_revealing = false
	_reveal.stop()
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _session_changed(_mode: Network.Mode) -> void:
	close(false)
	_data = {}


func _input(event: InputEvent) -> void:
	if _panel.visible and event.is_action_pressed(&"release_mouse"):
		get_viewport().set_input_as_handled()
		close()


func _request_finished(_action: StringName, result: NetworkedEntity.Result) -> void:
	if _panel.visible and result != NetworkedEntity.Result.ACCEPTED:
		_data["message"] = "Not available: refresh, check your collection or move closer to the crate."
		_rebuild()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(.025, .04, .035, .95)
	backdrop.theme = UI_THEME
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_panel = backdrop
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	backdrop.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_label(box, "RUSTY HOGG'S · PRAWN SKINS", Color("d4b060"))
	_label(box, "Cosmetics only · No keys needed · Buy at the shop, manage anywhere")
	var tabs := HBoxContainer.new()
	box.add_child(tabs)
	_button(tabs, "Crates", _navigate.bind("crates", "harbour"), true)
	_button(tabs, "Collection", _navigate.bind("collection", ""), true)
	_button(tabs, "Refresh", _send.bind("refresh", ""), true)
	_status = _label(box, "Loading collection…")
	_reveal = PrawnSkinReveal.new()
	box.add_child(_reveal)
	_reveal.hide()
	_reveal.finished.connect(_revealed)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)
	_button(box, "Back to game", close, true)
	backdrop.hide()


func _revealed() -> void:
	_revealing = false
	_page = "skin"
	_selected = _winner
	var data: Array = PrawnSkinCatalog.SKINS[_winner]
	var count := int(_data["document"]["skins"].get(_winner, 0))
	_data["message"] = (
		"%s — %s%s"
		% [
			data[0],
			PrawnSkinCatalog.TIERS[data[2]],
			" (duplicate; exchange extra copies below)" if count > 1 else " (new skin)",
		]
	)
	_reveal.hide()
	_rebuild()


func _navigate(page: String, id: String) -> void:
	if _revealing:
		return
	_page = page
	_selected = id
	_rebuild()


func _send(action: String, id: String) -> void:
	if _revealing:
		return
	_owner.entity.request_action(
		&"operate", {"action": action, "id": id, "revision": int(_data.get("revision", -1))}
	)


func _rebuild() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var focus_text := (focus as Button).text if focus is Button else ""
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var balance := int(wallet.balances.get(multiplayer.get_unique_id(), 0)) if wallet else 0
	_status.text = (
		"%s · %s"
		% [
			PlayerMoney.format_money(balance),
			str(_data.get("message", "")),
		]
	)
	if _data.get("pending", false):
		_label(_rows, "An unresolved transaction is locked. Retry it to safely recover.")
		_button(_rows, "Retry saved transaction", _send.bind("retry", ""), true)
		return
	if _data.get("revision", -1) < 0:
		_label(_rows, "Collection unavailable or loading. Use Refresh to retry.")
		return
	if not _data.get("configured", true):
		_label(_rows, "Crate odds are invalid; purchases and opening are disabled.")
	var document: Dictionary = _data["document"]
	match _page:
		"crates":
			_crate_list(document)
		"contents":
			_contents(document)
		"skin":
			_skin_details(document)
		_:
			_collection(document)
	for button: Button in _rows.find_children("*", "Button", true, false):
		if button.text == focus_text:
			button.grab_focus()
			return
	var buttons := _rows.find_children("*", "Button", true, false)
	if not buttons.is_empty():
		(buttons[0] as Button).grab_focus()


func _crate_list(document: Dictionary) -> void:
	_label(_rows, "Every outcome and its exact odds are shown before you buy.")
	for id: String in PrawnSkinCatalog.CRATES:
		var crate: Dictionary = PrawnSkinCatalog.CRATES[id]
		_label(
			_rows,
			(
				"%s · %s · Owned: %d"
				% [
					crate["name"],
					PlayerMoney.format_money(crate["price"]),
					document["crates"].get(id, 0),
				]
			)
		)
		_button(_rows, "Inspect " + crate["name"], _navigate.bind("contents", id), true)
		if document["crates"].get(id, 0) > 0:
			_button(_rows, "Open " + crate["name"], _send.bind("open", id))


func _contents(document: Dictionary) -> void:
	var crate: Dictionary = PrawnSkinCatalog.CRATES[_selected]
	_label(_rows, crate["name"] + " · One skin per crate · Total odds: 100%")
	if not _data.get("configured", true):
		_label(_rows, "Configuration unavailable; ask the server operator to fix the odds/refunds.")
		return
	for tier: int in 5:
		var id: String = crate["skins"][tier]
		var data: Array = PrawnSkinCatalog.SKINS[id]
		var row := HBoxContainer.new()
		_rows.add_child(row)
		var icon := PrawnSkinIcon.new()
		icon.skin = id
		row.add_child(icon)
		var chance := float(_data.get("odds", PrawnSkinCatalog.DEFAULT_ODDS)[tier]) / 100.0
		_label(
			row,
			(
				"%s · %s\n%s · %.2f%%"
				% [
					data[0],
					ItemCatalog.find(data[1]).display_name,
					PrawnSkinCatalog.TIERS[tier],
					chance,
				]
			),
			PrawnSkinCatalog.COLORS[tier]
		)
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	var at_shop := _owner.can_use(player)
	_button(
		_rows,
		"Buy sealed crate — " + PlayerMoney.format_money(crate["price"]),
		_send.bind("buy", _selected),
		at_shop and _available()
	)
	if not at_shop:
		_label(_rows, "Visit the crate beside the gun wall at Rusty Hogg's to buy.")
	if document["crates"].get(_selected, 0) > 0:
		_button(_rows, "Open owned crate (no extra cost)", _send.bind("open", _selected))


func _collection(document: Dictionary) -> void:
	if document["skins"].is_empty() and document["crates"].is_empty():
		_label(_rows, "No skins yet. Inspect a crate's contents, then buy one at the shop.")
	_crate_list(document)
	for id: String in PrawnSkinCatalog.SKINS:
		var count := int(document["skins"].get(id, 0))
		if count <= 0:
			continue
		var data: Array = PrawnSkinCatalog.SKINS[id]
		_button(
			_rows,
			(
				"%s · %s · x%d%s"
				% [
					data[0],
					PrawnSkinCatalog.TIERS[data[2]],
					count,
					" · Equipped" if document["equipped"].get(data[1], "") == id else "",
				]
			),
			_navigate.bind("skin", id),
			true
		)


func _skin_details(document: Dictionary) -> void:
	var data: Array = PrawnSkinCatalog.SKINS[_selected]
	var count := int(document["skins"].get(_selected, 0))
	var icon := PrawnSkinIcon.new()
	icon.skin = _selected
	icon.custom_minimum_size = Vector2(128, 128)
	_rows.add_child(icon)
	_label(
		_rows,
		(
			"%s · %s · %s · x%d"
			% [
				data[0],
				PrawnSkinCatalog.TIERS[data[2]],
				ItemCatalog.find(data[1]).display_name,
				count,
			]
		),
		PrawnSkinCatalog.COLORS[data[2]]
	)
	var equipped: bool = document["equipped"].get(data[1], "") == _selected
	_button(
		_rows,
		"Unequip skin" if equipped else "Equip on every " + data[1],
		_send.bind("unequip" if equipped else "equip", data[1] if equipped else _selected)
	)
	var refunds: Array = _data.get("refunds", [50, 100, 200, 500, 1000])
	if refunds.size() != 5:
		refunds = [0, 0, 0, 0, 0]
	_button(
		_rows,
		"Exchange ONE duplicate — " + PlayerMoney.format_money(refunds[data[2]]),
		_send.bind("exchange", _selected),
		count > 1 and _available()
	)
	_label(_rows, "Exchange keeps your last copy and equipped skin. Weapons/ammo sold separately.")


func _available() -> bool:
	return not _revealing and not _data.get("busy", false) and _data.get("configured", true)


func _label(parent: Node, text: String, color: Color = Color("ddd4bd")) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, callback: Callable, enabled: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = not enabled or _data.get("busy", false)
	if _revealing:
		button.disabled = true
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
