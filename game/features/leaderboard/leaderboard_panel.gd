class_name LeaderboardPanel
extends CanvasLayer
## The "Leaderboard" entry in the Esc menu: tabs for money, jumps and kills, each
## ranking every currently connected player highest-first. Reads
## `features/money`'s `PlayerMoney.balances`, this feature's own `Leaderboard.jumps`
## (see leaderboard.gd) and `features/combat`'s `Combat.kills` — nothing here owns
## any of that state, it only displays it.

enum Tab { MONEY, JUMPS, KILLS }

const MODAL_GROUP := &"modal_ui"
## Nodes in this group get a link in the Esc menu (`ui/login/login_screen.gd`).
const ESC_MENU_GROUP := &"esc_menu_links"
const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const PANEL_WIDTH := 460.0
const ROWS_HEIGHT := 320.0
const TABS: Array[Dictionary] = [
	{"id": Tab.MONEY, "label": "Money"},
	{"id": Tab.JUMPS, "label": "Jumps"},
	{"id": Tab.KILLS, "label": "Kills"},
]

var _backdrop: Control
var _rows: VBoxContainer
var _tab_buttons: Dictionary = {}
var _tab: int = Tab.MONEY


func _ready() -> void:
	layer = 9
	add_to_group(ESC_MENU_GROUP)
	_build()


func _process(_delta: float) -> void:
	if _backdrop.visible:
		_refresh()


func _input(event: InputEvent) -> void:
	if not _backdrop.visible:
		return
	if event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func esc_menu_label() -> String:
	return "Leaderboard"


func esc_menu_icon() -> Texture2D:
	return preload("res://assets/kenney/game-icons/PNG/White/1x/trophy.png")


func esc_menu_open() -> void:
	_backdrop.visible = true
	add_to_group(MODAL_GROUP)
	Controls.pause()
	_refresh()


## `peer_ids`, highest value first; ties break on peer id so every client agrees
## (the same tie-break `features/money`'s `poorest_peers` uses).
static func ranked_peer_ids(peer_ids: Array[int], values: Dictionary) -> Array[int]:
	var order := peer_ids.duplicate()
	order.sort_custom(
		func(a: int, b: int) -> bool:
			var value_a := int(values.get(a, 0))
			var value_b := int(values.get(b, 0))
			return value_a > value_b if value_a != value_b else a < b
	)
	return order


## The display name for a row, falling back to "Player <id>" the same way
## features/roulette and features/slot_machine label an unnamed operator.
static func player_label(display_name: String, peer_id: int) -> String:
	return display_name if display_name else "Player %d" % peer_id


## The right-hand column's text for `tab`: dollars for money, a plain count for
## jumps and kills.
static func value_text(tab: int, value: int) -> String:
	return PlayerMoney.format_money(value) if tab == Tab.MONEY else str(value)


func _select_tab(tab: int) -> void:
	_tab = tab
	_refresh()


func _close() -> void:
	_backdrop.visible = false
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	Controls.start()


func _refresh() -> void:
	for tab_id: int in _tab_buttons:
		(_tab_buttons[tab_id] as Button).button_pressed = tab_id == _tab
	var peer_ids := _peer_ids()
	var values := _values(_tab, peer_ids)
	var order := ranked_peer_ids(peer_ids, values)
	for child: Node in _rows.get_children():
		child.queue_free()
	if order.is_empty():
		var empty := Label.new()
		empty.text = "Nobody's here yet."
		_rows.add_child(empty)
		return
	var local_peer := multiplayer.get_unique_id()
	for rank: int in order.size():
		var peer_id: int = order[rank]
		_add_row(
			rank + 1,
			player_label(_name_for(peer_id), peer_id),
			value_text(_tab, int(values.get(peer_id, 0))),
			peer_id == local_peer
		)


func _peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null:
			peer_ids.append(player.get_multiplayer_authority())
	return peer_ids


func _values(tab: int, peer_ids: Array[int]) -> Dictionary:
	var values := {}
	match tab:
		Tab.MONEY:
			var money := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
			for peer_id: int in peer_ids:
				values[peer_id] = int(money.balances.get(peer_id, 0)) if money != null else 0
		Tab.JUMPS:
			var board := get_tree().get_first_node_in_group(&"leaderboard") as Leaderboard
			for peer_id: int in peer_ids:
				values[peer_id] = board.jumps_for(peer_id) if board != null else 0
		Tab.KILLS:
			var combat := get_tree().get_first_node_in_group(&"combat") as Combat
			for peer_id: int in peer_ids:
				values[peer_id] = combat.kills_for(peer_id) if combat != null else 0
	return values


func _name_for(peer_id: int) -> String:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player.display_name
	return ""


func _add_row(rank: int, player_name: String, value: String, is_local: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_rows.add_child(row)

	var rank_label := Label.new()
	rank_label.text = "#%d" % rank
	rank_label.custom_minimum_size.x = 36.0
	row.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = player_name + (" (you)" if is_local else "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	if is_local:
		for label: Label in [rank_label, name_label, value_label]:
			label.add_theme_color_override("font_color", Color("36bdf7"))


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.05, 0.06, 0.08, 0.6)
	_backdrop.visible = false
	_backdrop.theme = UI_THEME
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var heading := Label.new()
	heading.text = "Leaderboard"
	heading.theme_type_variation = &"HeadingLabel"
	box.add_child(heading)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for tab_def: Dictionary in TABS:
		var button := Button.new()
		button.text = tab_def["label"]
		button.theme_type_variation = &"SecondaryButton"
		button.toggle_mode = true
		button.button_group = group
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		button.custom_minimum_size.y = 40
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select_tab.bind(tab_def["id"]))
		tabs.add_child(button)
		_tab_buttons[tab_def["id"]] = button

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH, ROWS_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rows)

	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"SecondaryButton"
	close.custom_minimum_size.y = 40
	close.pressed.connect(_close)
	box.add_child(close)
