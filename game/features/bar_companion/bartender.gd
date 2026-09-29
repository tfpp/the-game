extends Node3D
## Use at the bar counter to buy a drink through the shared wallet. Each drink raises
## intoxication in BarCompanion: the first few add charisma, more take it away.

const RANGE := 2.6

var _pending: Dictionary[int, bool] = {}
var _speech_left := 0.0

@onready var _companion := get_parent() as BarCompanion
@onready var _talk: NetworkedInteraction = $NetworkedEntity
@onready var _speech: Label3D = $Speech


func _ready() -> void:
	add_to_group(&"interactables")
	_talk.interaction_range = RANGE
	_talk.register_use(can_use, _apply_use, 0.5)
	_talk.event_received.connect(_on_event)


func interaction_text() -> String:
	var peer := multiplayer.get_unique_id()
	return (
		"Buy a drink (-%s) — charisma %d, %s"
		% [
			PlayerMoney.format_money(CharmMath.DRINK_CENTS),
			_companion.charisma_for(peer),
			CharmMath.mood(_companion.intoxication_for(peer)),
		]
	)


func can_use(player: Player) -> bool:
	return _talk.in_range(player)


func use() -> void:
	_talk.request_use()


func _apply_use(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if _pending.has(peer) or wallet == null:
		return false
	_pending[peer] = true
	_serve(wallet, peer)
	return true


func _serve(wallet: PlayerMoney, peer: int) -> void:
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var result: Dictionary = await wallet.charge(peer, id, CharmMath.DRINK_CENTS)
	_pending.erase(peer)
	if not is_inside_tree() or _talk.player_for_peer(peer) == null:
		return
	if result.has("error"):
		_talk.send_event(&"say", {"text": str(result["error"])}, peer)
		return
	_companion.add_drink(peer)
	var text := "Here you go."
	if _companion.intoxication_for(peer) > CharmMath.TIPSY_DRINKS:
		text = "Easy there — you're slurring."
	_talk.send_event(&"say", {"text": text}, peer)
	_talk.send_event(&"clink")


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
