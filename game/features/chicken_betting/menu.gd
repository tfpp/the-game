class_name ChickenBettingMenu
extends CanvasLayer
## Touch/controller-friendly local form. All choices are server-validated.

var book: ChickenBettingBook
var feedback := ""
var _status: Label
var _stats: Label
var _side: OptionButton
var _stake: SpinBox
var _place: Button
var _backdrop: Control
var _body_font: Font
var _button_font: Font


func _ready() -> void:
	layer = 10
	add_to_group(&"modal_ui")
	Controls.pause()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.06, 0.04, 0.03, 0.96)
	backdrop.theme = preload("res://ui/theme/ui_theme.tres").duplicate() as Theme
	_body_font = backdrop.theme.default_font.duplicate() as Font
	_button_font = backdrop.theme.get_font(&"font", &"Button").duplicate() as Font
	backdrop.theme.default_font = _body_font
	for control: StringName in [&"Button", &"OptionButton", &"LineEdit"]:
		backdrop.theme.set_font(&"font", control, _button_font)
	backdrop.theme.set_color(&"font_color", &"Label", Color("eedcb2"))
	add_child(backdrop)
	_backdrop = backdrop
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	backdrop.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_stats)
	var rules := Label.new()
	rules.text = (
		"BACKROOM BOOK\nFirst ticket opens a shared betting window. One ticket per player.\n"
		+ "Wager deducted now. Winning return = stake × displayed odds (includes stake).\n"
		+ "Leaving the room, disconnecting or cancelling before knockout refunds your wager.\n"
		+ "Close this form to watch; use the book again for results."
	)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(rules)
	_side = OptionButton.new()
	_side.add_item("Chicken 1")
	_side.add_item("Chicken 2")
	_side.custom_minimum_size.y = 48
	box.add_child(_side)
	_stake = SpinBox.new()
	_stake.min_value = book.config.min_bet_cents / 100.0
	_stake.max_value = book.config.max_bet_cents / 100.0
	_stake.step = 0.01
	_stake.value = _stake.min_value
	_stake.prefix = "$"
	_stake.get_line_edit().virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_stake.custom_minimum_size.y = 48
	box.add_child(_stake)
	_place = Button.new()
	_place.text = "Place wager"
	_place.custom_minimum_size.y = 48
	_place.pressed.connect(_bet)
	box.add_child(_place)
	var cancel := Button.new()
	cancel.text = "Cancel ticket & refund (before knockout)"
	cancel.custom_minimum_size.y = 48
	cancel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cancel.pressed.connect(func() -> void: book.entity.request_action(&"cancel"))
	box.add_child(cancel)
	var done := Button.new()
	done.text = "Close & watch chickens"
	done.custom_minimum_size.y = 48
	done.pressed.connect(close)
	box.add_child(done)
	_side.grab_focus()
	get_viewport().size_changed.connect(_resize)
	_resize()


func _process(_delta: float) -> void:
	if not is_instance_valid(book):
		close()
		return
	var state := book.state
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var peer := multiplayer.get_unique_id()
	_status.text = "Chicken fight — %s · round %d\n%s" % [state["phase"], state["round"], feedback]
	if state["phase"] == "betting":
		_status.text += "\nBetting closes in %ds" % int(state["seconds"])
	if wallet != null:
		_status.text += "\nBalance: " + PlayerMoney.format_money(wallet.balances.get(peer, 0))
	_stats.text = ""
	for index: int in state["birds"].size():
		var bird: Dictionary = state["birds"][index]
		_stats.text += (
			"%d — %s · %.2f× return\nStrength %d · Speed %d · Stamina %d · Luck %d · HP %d\n"
			% [
				index + 1,
				bird["name"],
				state["odds"][index],
				bird["strength"],
				bird["speed"],
				bird["stamina"],
				bird["luck"],
				state["health"][index]
			]
		)
	if int(state["winner"]) >= 0 and not state["birds"].is_empty():
		_stats.text += "\nWinner: " + str(state["birds"][int(state["winner"])]["name"])
	if state["bets"].has(peer):
		_status.text += "\n" + str(state["bets"][peer]["result"])
	_place.disabled = (
		state["phase"] not in ["preview", "betting"]
		or state["bets"].has(peer)
		or (state["phase"] == "betting" and int(state["seconds"]) == 0)
	)


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_backdrop.size = logical / ui_scale
	_body_font.set("oversampling", ui_scale)
	_button_font.set("oversampling", ui_scale)


func _bet() -> void:
	book.entity.request_action(
		&"bet",
		{
			"side": _side.selected,
			"stake": roundi(_stake.value * 100.0),
			"match": int(book.state["match"])
		}
	)
	feedback = "Sending wager…"


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
		Controls.start()
	queue_free()
