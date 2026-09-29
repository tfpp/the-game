class_name LootFence
extends CSGBox3D
## Converts carried valuables into the persistent casino wallet. A reserved
## item remains server-side while its idempotent API sale is unresolved.

const USE_RANGE_M := 2.5

var _pending: Dictionary = {}


func _ready() -> void:
	add_to_group(&"interactables")
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)


func interaction_text() -> String:
	return "Cash in valuables"


func can_use(player: Player) -> bool:
	return global_position.distance_to(player.net_position) <= USE_RANGE_M


func use() -> void:
	request_sell.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_sell() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	var hand := Hand.for_peer(get_tree(), peer_id)
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if player == null or hand == null or wallet == null or not can_use(player):
		return
	if not _pending.has(peer_id):
		var id := hand.inventory().take_first_valuable()
		if id.is_empty():
			return
		var def := ItemCatalog.find(id)
		_pending[peer_id] = {
			"item": id,
			"amount": def.sale_value_cents,
			"operation": Crypto.new().generate_random_bytes(32).hex_encode(),
			"busy": false,
		}
	var sale: Dictionary = _pending[peer_id]
	if sale["busy"]:
		return
	sale["busy"] = true
	var result := await wallet.sell_loot(peer_id, sale["operation"], sale["amount"])
	if not _pending.has(peer_id) or _pending[peer_id] != sale:
		return
	if result.has("balance"):
		_pending.erase(peer_id)
	else:
		sale["busy"] = false


func _on_mode_changed(_mode: Network.Mode) -> void:
	_pending.clear()


func _on_peer_disconnected(peer_id: int) -> void:
	_pending.erase(peer_id)


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
