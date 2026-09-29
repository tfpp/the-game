extends CasinoPatron
## A patron who follows the mayor instead of walking an independent route.

const PRICE_CENTS := 10000
const FOLLOW_DISTANCE := 1.5
const FOLLOW_SPEED := 1.8

var _leader: CasinoPatron
var _charging: Dictionary[int, bool] = {}


func _ready() -> void:
	super._ready()
	_setup_talk()


func _walk_on(delta: float) -> void:
	if not is_instance_valid(_leader):
		for node: Node in get_parent().get_children():
			if node is CasinoPatron and node.look == PatronModel.MAMDANI_LOOK:
				_leader = node as CasinoPatron
				break
	if not is_instance_valid(_leader) or not _leader.net_alive:
		return
	var offset := _leader.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance <= FOLLOW_DISTANCE:
		return
	var heading := offset / distance
	net_yaw = PatronMath.facing_yaw(heading)
	if not _player_in_the_way(heading):
		_waited = 0.0
	elif _waited < PatronMath.MAX_WAIT_S:
		_waited += delta
		return
	# Collide with world geometry if either patron was knocked off the clear aisle.
	move_and_collide(heading * minf(FOLLOW_SPEED * delta, distance - FOLLOW_DISTANCE))
	_return_to = null


func can_use(player: Player) -> bool:
	return net_alive and not net_ragdoll and _talk != null and _talk.in_range(player)


func interaction_text() -> String:
	return "Talk to Donald Trump (-$100)"


func _apply_talk(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	if _charging.has(peer):
		return false
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null:
		_say(peer, "Wallet unavailable. Try again later.")
		return false
	_charging[peer] = true
	# Launch asynchronous wallet work without yielding the validated apply callback.
	_charge(wallet, peer, player)
	return true


func _charge(wallet: PlayerMoney, peer: int, player: Player) -> void:
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var result: Dictionary = await wallet.charge(peer, id, PRICE_CENTS)
	_charging.erase(peer)
	# Never deliver a delayed reply to a disconnected/replaced player's peer ID.
	if peer != multiplayer.get_unique_id() and not multiplayer.get_peers().has(peer):
		return
	if not is_instance_valid(player) or _talk.player_for_peer(peer) != player:
		return
	if result.has("error"):
		_say(peer, str(result["error"]))
	else:
		_say(peer, "Paid $100.")
