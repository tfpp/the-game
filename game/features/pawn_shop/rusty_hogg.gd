extends StationaryPatron
## Repeatable private conversation; inherited StationaryPatron owns life and respawn.

const SPEAKER := "Rusty Hogg"
const LINES: Array[String] = [
	"Don't tell the IRS",
	"Vivienne is hotter than my cousin",
	"Don't point that thing at me",
	"Uncle Sam doesn't have to know about this",
	"No ID? No problem!",
	"Those sissy liberals can't take that away from you!",
	"Cash talks. Receipts snitch.",
	"Everything here has a history. Most of it is inadmissible.",
	"My cousin called this an investment. The judge called it evidence.",
	"That top hat costs ten grand. The bad decisions are complimentary.",
	"I buy low, sell high, and plead the Fifth.",
	"If anyone asks, you won it at bingo.",
]

var _talk: NetworkedInteraction
var _last_line := -1


func _ready() -> void:
	super._ready()
	add_to_group(&"interactables")
	add_to_group(&"pawn_broker")
	_talk = NetworkedInteraction.new()
	_talk.name = "Talk"
	add_child(_talk)
	_talk.register_use(can_use, _apply_talk, 0.5)
	_talk.event_received.connect(_on_talk_event)
	_talk.session_reset.connect(func(_mode: Network.Mode) -> void: _last_line = -1)


func can_use(player: Player) -> bool:
	return net_alive and _talk.in_range(player)


func interaction_text() -> String:
	return "Trade with Rusty Hogg"


func use() -> void:
	_talk.request_use()


func _apply_talk(player: Player) -> bool:
	# Pick from all other lines to avoid repeating the last reply.
	var index := randi_range(0, LINES.size() - (1 if _last_line < 0 else 2))
	if _last_line >= 0 and index >= _last_line:
		index += 1
	_last_line = index
	_talk.send_event(&"say", {"text": LINES[index]}, player.get_multiplayer_authority())
	return true


func _on_talk_event(event: StringName, payload: Dictionary) -> void:
	if event == &"say":
		Subtitles.say(get_tree(), SPEAKER, str(payload.get("text", "")))
		var counter := get_tree().get_first_node_in_group(&"pawn_counter")
		if counter != null:
			counter.get_node("TradeMenu").call("open_menu")
