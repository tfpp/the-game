class_name HorseBettingMenu
extends CanvasLayer
## Local, phone-sized ticket form; all requests are revalidated by the server.

var race: HorseBetting
var feedback := ""
var _status: Label
var _tickets: Label
var _horse: OptionButton
var _stake: OptionButton
var _place: Button
var _snapshot: Dictionary = {}
var _backdrop: Control
var _body_font: Font
var _button_font: Font


func _ready() -> void:
	layer = 10
	add_to_group(&"modal_ui")
	Controls.pause()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.04, 0.03, 0.02, 0.96)
	_backdrop = backdrop
	backdrop.theme = preload("res://ui/theme/ui_theme.tres").duplicate() as Theme
	_body_font = backdrop.theme.default_font.duplicate() as Font
	_button_font = backdrop.theme.get_font(&"font", &"Button").duplicate() as Font
	backdrop.theme.default_font = _body_font
	backdrop.theme.set_font(&"font", &"Button", _button_font)
	backdrop.theme.set_font(&"font", &"OptionButton", _button_font)
	backdrop.theme.set_color(&"font_color", &"Label", Color("eedcb2"))
	add_child(backdrop)
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
	var rules := Label.new()
	rules.text = (
		"CROWN TURF CLUB\nFirst ticket starts 15 seconds of betting.\n"
		+ "4 equal chances (25% each). Winner returns 4× stake, including stake.\n"
		+ "One ticket per player. Bets lock when the race starts.\n"
		+ "Wallet charged at result; insufficient funds void the ticket."
	)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(rules)
	_horse = OptionButton.new()
	_horse.custom_minimum_size.y = 48
	for index: int in HorseBetting.HORSES.size():
		_horse.add_item("%d — %s" % [index + 1, HorseBetting.HORSES[index]])
	box.add_child(_horse)
	_stake = OptionButton.new()
	_stake.custom_minimum_size.y = 48
	for cents: int in HorseBetting.STAKES:
		_stake.add_item(PlayerMoney.format_money(cents))
	box.add_child(_stake)
	_place = Button.new()
	_place.text = "Place ticket"
	_place.custom_minimum_size.y = 48
	_place.pressed.connect(_bet)
	box.add_child(_place)
	_tickets = Label.new()
	_tickets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_tickets)
	var done := Button.new()
	done.text = "Close & watch display"
	done.custom_minimum_size.y = 48
	done.pressed.connect(close)
	box.add_child(done)
	_horse.grab_focus()
	get_viewport().size_changed.connect(_resize)
	_resize()
	_process(0.0)


func _process(_delta: float) -> void:
	if not is_instance_valid(race):
		close()
		return
	var phase := str(race.state["phase"])
	_status.text = "Horse racing — " + phase
	if phase == "betting":
		_status.text += " (%ds left)" % race.seconds_left
	if int(race.state["winner"]) >= 0:
		_status.text += "\nWinner: " + HorseBetting.HORSES[int(race.state["winner"])]
	_status.text += "\n" + feedback
	var peer := multiplayer.get_unique_id()
	_place.disabled = (
		phase not in ["idle", "betting"] or (phase == "betting" and race.state["bets"].has(peer))
	)
	if race.state == _snapshot:
		return
	_snapshot = race.state.duplicate(true)
	_tickets.text = "Race tickets:\n"
	for bettor: int in race.state["bets"]:
		var ticket: Dictionary = race.state["bets"][bettor]
		_tickets.text += (
			"%s: #%d %s — %s %s\n"
			% [
				ticket["name"],
				int(ticket["horse"]) + 1,
				HorseBetting.HORSES[int(ticket["horse"])],
				PlayerMoney.format_money(int(ticket["stake"])),
				race.state["results"].get(bettor, "")
			]
		)


func _resize() -> void:
	if not is_inside_tree():
		return
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_body_font.set("oversampling", ui_scale)
	_button_font.set("oversampling", ui_scale)
	_backdrop.size = logical / ui_scale


func _bet() -> void:
	feedback = "Sending ticket…"
	race.entity.request_action(
		&"bet",
		{
			"horse": _horse.selected,
			"stake": HorseBetting.STAKES[_stake.selected],
			"round": race.ticket_round()
		}
	)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if is_in_group(&"modal_ui"):
		remove_from_group(&"modal_ui")
		Controls.start()
	queue_free()
