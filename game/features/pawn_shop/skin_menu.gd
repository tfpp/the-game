extends CanvasLayer
## Private collection UI. No local purchases, reward rolls or equipment writes.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const PANEL_ART := preload("res://assets/pawn_shop/ui/case_panel.png")
var _panel: Control
var _frame: PanelContainer
var _tabs: HBoxContainer
var _scroll: ScrollContainer
var _heading: Label
var _rows: VBoxContainer
var _status: Label
var _data := {}
var _page := "crates"
var _selected := "harbour"
var _revealing := false
var _reveal: PrawnSkinReveal
var _winner := ""
var _reward_view := false

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
		_reward_view = false
		_panel.show()
		add_to_group(&"modal_ui")
		Controls.pause()
		GameAudio.play_ui(self, &"open")
	if not _panel.visible:
		return
	var reward := str(payload.get("reward", ""))
	if not reward.is_empty() and PrawnSkinCatalog.SKINS.has(reward):
		_revealing = true
		_reward_view = true
		_rebuild()
		_status.text = "Opening your case…"
		_heading.text = "CASE OPENING"
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
	backdrop.theme = UI_THEME.duplicate() as Theme
	for scroll_style: String in ["scroll", "scroll_focus"]:
		backdrop.theme.set_stylebox(
			scroll_style, "VScrollBar", _scroll_surface(Color("171d17"), Color("353a2e"))
		)
	for grabber_style: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		backdrop.theme.set_stylebox(
			grabber_style, "VScrollBar", _scroll_surface(Color("897447"), Color("bfa367"))
		)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_panel = backdrop
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	_frame = PanelContainer.new()
	center.add_child(_frame)
	_frame.add_theme_stylebox_override("panel", _surface(Color("141914"), Color("74613c")))
	var art := TextureRect.new()
	art.texture = PANEL_ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color(1, 1, 1, 0.65)
	_frame.add_child(art)
	var margin := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 18)
	_frame.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var brand := _label(box, "RUSTY HOGG'S", Color("b5a27a"))
	brand.add_theme_font_size_override("font_size", 13)
	_heading = _label(box, "PRAWN SKINS", Color("f2e8d2"))
	_heading.add_theme_font_size_override("font_size", 28)
	var subtitle := _label(box, "Weapon finishes · No keys needed", Color("aaa99b"))
	subtitle.add_theme_font_size_override("font_size", 13)
	var tabs := HBoxContainer.new()
	_tabs = tabs
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
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)
	_button(box, "Back to game", close, true)
	get_viewport().size_changed.connect(_resize_panel)
	_resize_panel()
	backdrop.hide()


func _resize_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_frame.custom_minimum_size = Vector2(
		minf(940, viewport_size.x - 24), minf(660, viewport_size.y - 24)
	)
	_reveal.custom_minimum_size.y = minf(250, maxf(130, viewport_size.y - 280))


func _surface(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _scroll_surface(fill: Color, border: Color) -> StyleBoxFlat:
	var style := _surface(fill, border)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style


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
	_reward_view = false
	_selected = id
	_rebuild()


func _send(action: String, id: String) -> void:
	if _revealing:
		return
	_owner.entity.request_action(
		&"operate", {"action": action, "id": id, "revision": int(_data.get("revision", -1))}
	)


func _rebuild() -> void:
	_scroll.visible = not _revealing
	_tabs.visible = not _revealing
	_heading.text = (
		"CASE OPENING" if _revealing else ("SKIN UNLOCKED" if _reward_view else "PRAWN SKINS")
	)
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
	if _reward_view:
		_status.text = str(_data.get("message", ""))
	if _revealing:
		return
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
	icon.custom_minimum_size = Vector2(128, 180)
	_rows.add_child(icon)
	var title := _label(_rows, data[0], PrawnSkinCatalog.COLORS[data[2]])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
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
	button.add_theme_font_size_override("font_size", 13 if parent == _tabs else 16)
	button.add_theme_color_override("font_pressed_color", Color("fff0c7"))
	button.add_theme_color_override("font_focus_color", Color("fff0c7"))
	button.add_theme_stylebox_override("normal", _surface(Color("252920"), Color("756441")))
	button.add_theme_stylebox_override("hover", _surface(Color("393929"), Color("d4b060")))
	button.add_theme_stylebox_override("pressed", _surface(Color("151a15"), Color("d4b060")))
	button.add_theme_stylebox_override("disabled", _surface(Color("1a1e19"), Color("3f4439")))
	var focus_style := _surface(Color(0, 0, 0, 0), Color("e5c77c"))
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_color_override("font_color", Color("e9dfc5"))
	button.add_theme_color_override("font_hover_color", Color("fff0c7"))
	button.add_theme_color_override("font_disabled_color", Color("74796b"))
	if _revealing:
		button.disabled = true
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
