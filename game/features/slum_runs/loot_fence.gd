class_name LootFence
extends CSGBox3D
## The pawn shop counter: converts carried valuables into the persistent casino
## wallet. A reserved item remains server-side while its idempotent API sale is
## unresolved. Its storefront decor is built locally and has no collision.

const USE_RANGE_M := 2.5
## Local offsets of the three hanging pawnbroker balls, above the counter top.
const BALL_OFFSETS: Array[Vector3] = [
	Vector3(-0.13, 1.25, 0.0), Vector3(0.13, 1.25, 0.0), Vector3(0.0, 1.03, 0.0)
]
const BALL_RADIUS_M := 0.1

@export var storefront_scene: PackedScene

var _pending: Dictionary = {}
var _trade: NetworkedInteraction


func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"pawn_counter")
	var menu := CanvasLayer.new()
	menu.set_script(preload("res://features/pawn_shop/trade_menu.gd"))
	menu.name = "TradeMenu"
	add_child(menu)
	_trade = NetworkedInteraction.new()
	_trade.name = "CounterTrade"
	add_child(_trade)
	_trade.register_use(can_use, _open_trade)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)
	_build_storefront()


func interaction_text() -> String:
	return "Trade · Buy guns and ammo / sell valuables"


func can_use(player: Player) -> bool:
	if global_position.distance_to(player.net_position) <= USE_RANGE_M:
		return true
	var broker := get_tree().get_first_node_in_group(&"pawn_broker")
	return broker != null and bool(broker.call("can_use", player))


func use() -> void:
	_trade.request_use()


func _open_trade(player: Player) -> bool:
	var menu := get_node("TradeMenu")
	(menu.get("entity") as NetworkedEntity).send_event(
		&"open", {}, player.get_multiplayer_authority()
	)
	return true


## Reuse the fence's idempotent reservation across retries, including API failures.
func sell_selected(peer: int, slot: int, expected_id: String) -> String:
	var player := _player_for_peer(peer)
	var hand := Hand.for_peer(get_tree(), peer)
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if (
		not multiplayer.is_server()
		or player == null
		or hand == null
		or wallet == null
		or not can_use(player)
	):
		return "Stay near the pawn counter."
	if not _pending.has(peer):
		var id := hand.inventory().take_valuable_at(slot, expected_id)
		if id.is_empty():
			return "Item unavailable or not accepted."
		_pending[peer] = {
			"item": id,
			"amount": ItemCatalog.find(id).sale_value_cents,
			"operation": Crypto.new().generate_random_bytes(32).hex_encode(),
			"busy": false
		}
	var sale: Dictionary = _pending[peer]
	if not expected_id.is_empty() and sale["item"] != expected_id:
		return "Sale pending. Retry the reserved item before selling another."
	if sale["busy"]:
		return "A sale is already processing."
	return await _resolve_sale(peer, sale, wallet)


func _resolve_sale(peer: int, sale: Dictionary, wallet: PlayerMoney) -> String:
	sale["busy"] = true
	var result := await wallet.sell_loot(peer, sale["operation"], sale["amount"], "Pawn shop sale")
	if not _pending.has(peer) or _pending[peer] != sale:
		return "Session ended."
	if result.has("balance"):
		_pending.erase(peer)
		return (
			"Sold %s for %s."
			% [
				ItemCatalog.find(sale["item"]).display_name,
				PlayerMoney.format_money(sale["amount"])
			]
		)
	sale["busy"] = false
	return "Sale pending. Use the counter again to retry; your item is reserved."


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
	var result := await wallet.sell_loot(
		peer_id, sale["operation"], sale["amount"], "Sold loot to the fence"
	)
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


func _build_storefront() -> void:
	if storefront_scene != null:
		var storefront := storefront_scene.instantiate() as Node3D
		storefront.position.y = -size.y * 0.5
		add_child(storefront)
		return
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.72, 0.2)
	gold.metallic = 0.9
	gold.roughness = 0.3
	var top := size.y * 0.5
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.6, 0.85, 1.0, 0.25)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var case_mesh := BoxMesh.new()
	case_mesh.size = Vector3(size.x - 0.1, 0.25, size.z - 0.1)
	_add_mesh("DisplayCase", case_mesh, glass, Vector3(0, top + 0.125, 0))
	var bar := BoxMesh.new()
	bar.size = Vector3(0.5, 0.04, 0.3)
	_add_mesh("BallBar", bar, gold, Vector3(0, top + 1.45, _back_z() - 0.12))
	var ball := SphereMesh.new()
	ball.radius = BALL_RADIUS_M
	ball.height = BALL_RADIUS_M * 2.0
	ball.radial_segments = 12
	ball.rings = 6
	for i: int in BALL_OFFSETS.size():
		var offset := BALL_OFFSETS[i] + Vector3(0, top, _back_z() - 0.12)
		_add_mesh("Ball%d" % i, ball, gold, offset)
	var post := BoxMesh.new()
	post.size = Vector3(0.04, 1.2, 0.04)
	_add_mesh("BallPost", post, gold, Vector3(0, top + 0.85, _back_z()))


func _add_mesh(node_name: String, mesh: Mesh, material: Material, at: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## The counter's back edge, towards the lobby wall, where the ball sign mounts.
func _back_z() -> float:
	return size.z * 0.5 - 0.02
