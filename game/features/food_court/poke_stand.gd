class_name PokeStand
extends Node3D
## Paid food service; balances and delivered items stay owned by existing systems.

const PRICE_CENTS := 2900
const TIPS: Array[int] = [15, 20, 25, 30, 35, 40]

var _busy: Dictionary[int, bool] = {}
var _next_order: Dictionary[int, int] = {}
var _generation := 0

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _open_menu)
	entity.register_action(&"order", _may_order, _order)
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(func(peer: int) -> void: _next_order.erase(peer))


static func total_cents(tip: int) -> int:
	return PRICE_CENTS + PRICE_CENTS * tip / 100


func can_use(player: Player) -> bool:
	return entity.in_range(player) and to_local(player.net_position).z > 0.65


func interaction_text() -> String:
	return "Poke bowl — $29 + tip (15–40%)"


func use() -> void:
	entity.request_use()


func _open_menu(player: Player) -> bool:
	entity.send_event(&"menu", {}, player.get_multiplayer_authority())
	return true


func _may_order(peer: int, payload: Dictionary) -> bool:
	return (
		payload.size() == 1
		and payload.get("tip") is int
		and payload["tip"] in TIPS
		and can_use(entity.player_for_peer(peer))
		and not _busy.has(peer)
		and Time.get_ticks_msec() >= _next_order.get(peer, 0)
	)


func _order(peer: int, payload: Dictionary) -> bool:
	var hand := Hand.for_peer(get_tree(), peer)
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var holdables := get_tree().get_first_node_in_group(&"holdables_root")
	if hand == null or not hand.inventory().can_collect("poke_bowl"):
		_reply(peer, "Make room in your hand or backpack first.")
		return false
	if wallet == null or holdables == null:
		_reply(peer, "Service unavailable. Try again later.")
		return false
	_busy[peer] = true
	_next_order[peer] = Time.get_ticks_msec() + 1000
	_charge(wallet, hand, holdables, peer, int(payload["tip"]))
	return true


func _charge(wallet: PlayerMoney, hand: Hand, holdables: Node, peer: int, tip: int) -> void:
	var generation := _generation
	var player := entity.player_for_peer(peer)
	var total := total_cents(tip)
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var result: Dictionary = await wallet.charge(peer, id, total)
	if generation != _generation or not is_inside_tree():
		return
	_busy.erase(peer)
	var same_player := is_instance_valid(player) and entity.player_for_peer(peer) == player
	if result.has("error"):
		if same_player:
			_reply(peer, str(result["error"]))
		return
	var delivered := false
	if same_player and is_instance_valid(hand) and Hand.for_peer(get_tree(), peer) == hand:
		delivered = hand.inventory().collect("poke_bowl")
	# If the bag filled or the buyer disconnected while paying, leave their paid
	# bowl on the customer side as an ordinary replicated pickup, never charge twice.
	if not delivered and is_instance_valid(holdables):
		var spot := to_global(Vector3(0, 0, 1.25))
		holdables.spawn_thrown_item("poke_bowl", spot + Vector3.UP, spot)
	if same_player:
		var where := (
			"Enjoy your bowl!" if delivered else "Your bowl is on the floor by the counter."
		)
		_reply(peer, "%s paid (%d%% tip). %s" % [PlayerMoney.format_money(total), tip, where])


func _reply(peer: int, message: String) -> void:
	entity.send_event(&"receipt", {"text": message}, peer)


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	_busy.clear()
	_next_order.clear()
