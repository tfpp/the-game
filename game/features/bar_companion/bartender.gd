extends Node3D
## Use at the bar counter to buy a drink through the shared wallet. Each drink raises
## intoxication in BarCompanion: the first few add charisma, more take it away.

const RANGE := 2.6
const STOCK := {"drink": CharmMath.DRINK_CENTS, "beer": CharmMath.DRINK_CENTS, "cigarette": 200}

var _generation := 0

var _pending: Dictionary[int, bool] = {}
var _speech_left := 0.0

@onready var _companion := get_parent() as BarCompanion
@onready var _talk: NetworkedInteraction = $NetworkedEntity
@onready var _speech: Label3D = $Speech


func _ready() -> void:
	add_to_group(&"interactables")
	_talk.interaction_range = RANGE
	_talk.register_use(can_use, _open_shop, 0.5)
	_talk.register_action(&"order", _may_order, _order)
	_talk.session_reset.connect(_reset)
	_talk.event_received.connect(_on_event)


func interaction_text() -> String:
	return "Bar shop — beer $5 / cigarette $2 / drink $5"


func can_use(player: Player) -> bool:
	return _talk.in_range(player)


func use() -> void:
	_talk.request_use()


func _open_shop(player: Player) -> bool:
	_talk.send_event(&"menu", {}, player.get_multiplayer_authority())
	return true


func _may_order(peer: int, payload: Dictionary) -> bool:
	return (
		payload.size() == 1
		and payload.get("item") is String
		and STOCK.has(payload["item"])
		and can_use(_talk.player_for_peer(peer))
		and not _pending.has(peer)
	)


func _order(peer: int, payload: Dictionary) -> bool:
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var item: String = payload["item"]
	var hand := Hand.for_peer(get_tree(), peer)
	if wallet == null:
		return false
	if item != "drink":
		if hand == null or not hand.inventory().can_collect(item):
			_talk.send_event(&"receipt", {"text": "Make room in your inventory first."}, peer)
			return false
		if get_tree().get_first_node_in_group(&"holdables_root") == null:
			return false
	_pending[peer] = true
	_serve(wallet, peer, item, hand)
	return true


func _serve(wallet: PlayerMoney, peer: int, item: String, hand: Hand) -> void:
	var generation := _generation
	var player := _talk.player_for_peer(peer)
	var holdables := get_tree().get_first_node_in_group(&"holdables_root")
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var result: Dictionary = await wallet.charge(peer, id, int(STOCK[item]))
	if not is_inside_tree() or generation != _generation:
		return
	_pending.erase(peer)
	var same_player := is_instance_valid(player) and _talk.player_for_peer(peer) == player
	if result.has("error"):
		if same_player:
			_talk.send_event(&"receipt", {"text": str(result["error"])}, peer)
		return
	var message := "Here you go."
	if item == "drink":
		if same_player:
			_companion.add_drink(peer)
			if _companion.intoxication_for(peer) > CharmMath.TIPSY_DRINKS:
				message = "Easy there — you're slurring."
	else:
		var delivered := false
		if same_player and is_instance_valid(hand) and Hand.for_peer(get_tree(), peer) == hand:
			delivered = hand.inventory().collect(item)
		if not delivered and is_instance_valid(holdables):
			# Drop to the gaming floor on the customer side, in front of z=-9.4.
			var spot := global_position + Vector3(0, -1.1, 1.25)
			holdables.spawn_thrown_item(item, spot + Vector3.UP, spot)
		message = (
			"Added to inventory." if delivered else "Your item is on the floor at the counter."
		)
	if same_player:
		_talk.send_event(&"say", {"text": message}, peer)
		_talk.send_event(&"receipt", {"text": message}, peer)
		_talk.send_event(&"clink")


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	_pending.clear()


func _on_event(event: StringName, payload: Dictionary) -> void:
	if event == &"say":
		_speech.text = str(payload.get("text", ""))
		_speech.visible = true
		_speech_left = 3.0
	elif event == &"clink" and Network.mode != Network.Mode.SERVER:
		GameAudio.play_at(self, &"pickup", global_position)


func _process(delta: float) -> void:
	if _speech.visible:
		_speech_left -= delta
		_speech.visible = _speech_left > 0.0
