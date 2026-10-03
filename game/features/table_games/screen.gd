# gdlint: disable=max-line-length
extends CanvasLayer
## Local accessible controls; all buttons request server-validated actions.

const HELP := {
	"blackjack":
	"Get closer to 21 than the dealer without going over. Dealer stands on soft 17. Natural pays 3:2. Hit or stand; no splits, insurance or doubles.",
	"poker":
	"Texas Hold'em · 2–4 players · $1 ante · $0.50 fixed bets · one raise per street · $5 reserved. Check/call, bet/raise or fold. Ties split the pot. 25 seconds per action; timeout folds.",
	"baccarat":
	"Choose Player (1:1), Banker (0.95:1 after commission) or Tie (8:1). Player and Banker bets push on a tie. Closest to nine wins; dealer draws automatically.",
	"craps":
	"Pass line pays 1:1. Come-out: 7/11 wins, 2/3/12 loses. Other rolls set the point; roll that number before seven. First player is the shooter; automatic rolls on timeout.",
	"video_poker":
	"Crown draw poker · $1 per hand · hold any cards, then draw once. Gross payouts: royal 36x, straight flush 25x, four 25x, full house 9x, flush 6x, straight 4x, three 3x, two pair 2x, jacks-or-better pair 1x. Custom Crown paytable."
}
var table: CrownGameTable
var _text: Label
var _actions: HFlowContainer
var _holds: HBoxContainer
var _hold_buttons: Array[Button] = []
var _buttons: Dictionary = {}
var _last := ""
var _closed := false
var _notice: Label
var _join_button: Button
var _stand_button: Button


func _ready() -> void:
	layer = 9
	add_to_group(&"modal_ui")
	Controls.pause()
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-320, -220)
	panel.size = Vector2(640, 440)
	root.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title := Label.new()
	title.text = table.game.replace("_", " ").to_upper()
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color("dcc28a")
	box.add_child(title)
	var help := Label.new()
	help.text = HELP[table.game]
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_text)
	_holds = HBoxContainer.new()
	box.add_child(_holds)
	for i: int in 5:
		var button := _button(_holds, "Hold %d" % (i + 1), func() -> void: pass)
		button.toggle_mode = true
		_hold_buttons.append(button)
	_actions = HFlowContainer.new()
	box.add_child(_actions)
	for action: String in [
		"hit",
		"stand",
		"check",
		"call",
		"bet",
		"raise",
		"fold",
		"player",
		"banker",
		"tie",
		"roll",
		"draw"
	]:
		_buttons[action] = _button(_actions, action.capitalize(), _move.bind(action))
	var bottom := HBoxContainer.new()
	box.add_child(bottom)
	_join_button = _button(bottom, "Join / play again", table.use)
	_button(bottom, "Cancel before deal", func() -> void: table.entity.request_action(&"leave"))
	_stand_button = _button(bottom, "Stand up", _stand_up)
	_button(bottom, "Back to room", close)
	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_notice)
	table.entity.request_finished.connect(_result)
	_join_button.grab_focus()
	_refresh()
	for button: Button in _buttons.values():
		if button.visible:
			button.grab_focus()
			break


func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(70, 40)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var seats := table.get_node("Seats") as CrownTableSeating
	var snapshot := JSON.stringify(table.state) + str(table.private_hand) + str(seats.net_seats)
	if snapshot == _last:
		return
	_last = snapshot
	var peer := multiplayer.get_unique_id()
	_stand_button.visible = seats.is_seated(peer)
	var entry: Dictionary = table.state["players"].get(peer, {})
	var parts := PackedStringArray(
		["%s · %ds" % [str(table.state["phase"]).capitalize(), int(table.state["seconds"])]]
	)
	if not str(table.state["message"]).is_empty():
		parts.append(str(table.state["message"]))
	if not table.state["board"].is_empty():
		parts.append(
			(
				("Player: " if table.game == "baccarat" else "Board: ")
				+ CasinoCards.labels(table.state["board"])
			)
		)
	if not table.state["dealer"].is_empty():
		parts.append(
			(
				("Banker: " if table.game == "baccarat" else "Dealer: ")
				+ CasinoCards.labels(table.state["dealer"])
			)
		)
	if not table.state["dice"].is_empty():
		parts.append("Dice: %d + %d" % [table.state["dice"][0], table.state["dice"][1]])
	for other: int in table.state["players"]:
		var p: Dictionary = table.state["players"][other]
		var hand: Array = p.get("cards", [])
		parts.append(
			(
				"%s%s · %s · %s %s"
				% [
					str(p["name"]),
					" (turn)" if int(table.state["turn"]) == other else "",
					PlayerMoney.format_money(int(p["stake"])),
					"Folded" if bool(p["folded"]) else str(p["status"]),
					CasinoCards.labels(hand)
				]
			)
		)
	if (
		not entry.is_empty()
		and not table.private_hand.is_empty()
		and table.state["phase"] == "playing"
		and ["poker", "video_poker"].has(table.game)
	):
		parts.append("Your cards: " + CasinoCards.labels(table.private_hand))
	if not entry.is_empty() and table.game == "baccarat":
		parts.append("Your bet: " + str(entry["choice"]).capitalize())
	_text.text = "\n".join(parts)
	var allowed := table.moves(peer)
	for action: String in _buttons:
		(_buttons[action] as Button).visible = allowed.has(action)
	_holds.visible = table.game == "video_poker" and allowed.has("draw")
	for i: int in 5:
		if table.private_hand.size() == 5:
			_hold_buttons[i].text = CasinoCards.label(int(table.private_hand[i])) + " / HOLD"
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not focused.is_visible_in_tree():
		if allowed.is_empty():
			_join_button.grab_focus()
		else:
			(_buttons[allowed[0]] as Button).grab_focus()


func _move(action: String) -> void:
	var mask := 0
	if table.game == "video_poker":
		for i: int in 5:
			if _hold_buttons[i].button_pressed:
				mask |= 1 << i
	table.entity.request_action(&"move", {"move": action, "hold": mask})


func _result(_action: StringName, result: NetworkedEntity.Result) -> void:
	if result != NetworkedEntity.Result.ACCEPTED:
		_notice.text = "Request refused. Check your balance, table phase and distance."
	else:
		_notice.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _closed:
		return
	_closed = true
	Controls.start()
	queue_free()


func _exit_tree() -> void:
	if not _closed:
		Controls.start()


func _stand_up() -> void:
	var seats := table.get_node("Seats") as CrownTableSeating
	seats.request_stand()
	close()
