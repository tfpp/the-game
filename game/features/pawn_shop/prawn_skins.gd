class_name PrawnSkins
extends Node3D
## Sole collection owner. Wallet/API atomically save a planned mutation and money.
## Public equipment replicates; private collections are sent only to their owner.

@export var odds: Array[int] = [6000, 2500, 1000, 400, 100]
@export var duplicate_cents: Array[int] = [50, 100, 200, 500, 1000]
@export var net_equipped: Dictionary = {}

var _collections: Dictionary = {}
var _peers: Dictionary = {}
var _players: Dictionary = {}
var _busy: Dictionary = {}
var _pending: Dictionary = {}
var _generation := 0
var _elapsed := 0.0

@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var menu: CanvasLayer = $Menu


func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"prawn_skins")
	entity.register_use(can_use, _use)
	entity.register_action(&"collection", _may_show, _show)
	entity.register_action(&"operate", _may_operate, _operate)
	entity.event_received.connect(menu.receive)
	entity.session_reset.connect(_reset)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .2:
		return
	_elapsed = 0.0
	_apply_appearance()
	if not multiplayer.is_server():
		return
	var present := {}
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		var peer := player.get_multiplayer_authority()
		present[peer] = true
		if _players.get(peer, 0) != player.get_instance_id():
			_players[peer] = player.get_instance_id()
			_peers[peer] = _key(peer)
			_load(peer, _peers[peer])
	for peer: int in _peers.keys():
		if present.has(peer):
			continue
		var key: String = _peers[peer]
		_peers.erase(peer)
		_players.erase(peer)
		net_equipped = net_equipped.duplicate(true)
		net_equipped.erase(peer)
		if key.begins_with("temporary:"):
			_collections.erase(key)
			_pending.erase(key)
		elif not _busy.has(key) and not _pending.has(key):
			_collections.erase(key)


func _key(peer: int) -> String:
	var account := InventoryPersistence.account_for(peer)
	return "account:%d" % account if account > 0 else "temporary:%d" % peer


func _wallet() -> PlayerMoney:
	return get_tree().get_first_node_in_group(&"player_money") as PlayerMoney


func can_use(player: Player) -> bool:
	return entity.in_range(player)


func interaction_text() -> String:
	return "Prawn skin crates — inspect odds & collection"


func use() -> void:
	entity.request_use()


func _use(player: Player) -> bool:
	return _show(player.get_multiplayer_authority(), {})


func _may_show(peer: int, payload: Dictionary) -> bool:
	return payload.is_empty() and entity.player_for_peer(peer) != null


func _show(peer: int, _payload: Dictionary) -> bool:
	entity.send_event(&"show", _snapshot(peer), peer)
	return true


func _snapshot(peer: int, message: String = "", reward: String = "") -> Dictionary:
	var key := _key(peer)
	var record: Dictionary = _collections.get(key, {})
	return {
		"revision": record.get("revision", -1),
		"document": record.get("document", PrawnSkinCatalog.empty_document()),
		"odds": odds,
		"refunds": duplicate_cents,
		"pending": _pending.has(key),
		"busy": _busy.has(key),
		"message": message,
		"reward": reward,
		"at_shop": can_use(entity.player_for_peer(peer)),
		"configured": _configured(),
	}


func _load(peer: int, key: String, message: String = "") -> void:
	var generation := _generation
	var player_id: int = _players.get(peer, 0)
	while _busy.has(key):
		await get_tree().process_frame
		if generation != _generation:
			return
	_busy[key] = true
	var result: Dictionary
	if key.begins_with("temporary:"):
		result = _collections.get(
			key, {"revision": 0, "document": PrawnSkinCatalog.empty_document()}
		)
	else:
		var wallet := _wallet()
		result = await wallet.cosmetics(peer, "", 0, {}, 0, true) if wallet != null else {}
	if generation != _generation:
		return
	_busy.erase(key)
	if _players.get(peer, 0) != player_id or _key(peer) != key:
		return
	if result.has("document"):
		_collections[key] = {
			"revision": int(result["revision"]),
			"document": PrawnSkinCatalog.clean(result["document"]),
		}
		_publish(peer)
		_update(peer, message)
	else:
		_collections.erase(key)
		_update(peer, "Collection unavailable. Refresh to retry; nothing was charged.")


# gdlint: disable=max-returns
func _may_operate(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 3 or not payload.get("action") is String:
		return false
	if not payload.get("id") is String or not payload.get("revision") is int:
		return false
	if entity.player_for_peer(peer) == null or _wallet() == null:
		return false
	var key := _key(peer)
	if _busy.has(key):
		return false
	var action: String = payload["action"]
	if action == "refresh":
		return payload["id"] == "" and not _pending.has(key)
	if _pending.has(key):
		return action == "retry" and payload["id"] == ""
	var record: Dictionary = _collections.get(key, {})
	if record.is_empty() or payload["revision"] != record["revision"]:
		return false
	if action == "buy" and not can_use(entity.player_for_peer(peer)):
		return false
	if not _configured():
		return false
	return not (
		PrawnSkinCatalog
		. change(record["document"], action, payload["id"], odds, duplicate_cents)
		. is_empty()
	)


func _operate(peer: int, payload: Dictionary) -> bool:
	var key := _key(peer)
	if payload["action"] == "refresh":
		_load(peer, key)
		return true
	if not _pending.has(key):
		var record: Dictionary = _collections[key]
		var plan := PrawnSkinCatalog.change(
			record["document"],
			payload["action"],
			payload["id"],
			odds,
			duplicate_cents,
			randi_range(0, 9999)
		)
		if plan.is_empty():
			return false
		plan["id"] = Crypto.new().generate_random_bytes(32).hex_encode()
		plan["revision"] = record["revision"]
		_pending[key] = plan
	_busy[key] = true
	_update(peer, "Saving transaction…")
	_commit(peer, key)
	return true


func _commit(peer: int, key: String) -> void:
	var player_id: int = _players.get(peer, 0)
	var generation := _generation
	var plan: Dictionary = _pending[key]
	var wallet := _wallet()
	var result: Dictionary = await wallet.cosmetics(
		peer, plan["id"], plan["revision"], plan["document"], plan["delta"]
	)
	if generation != _generation:
		return
	_busy.erase(key)
	if key.begins_with("temporary:") and _players.get(peer, 0) != player_id:
		_pending.erase(key)
		_collections.erase(key)
		return
	if result.has("document"):
		_collections[key] = {
			"revision": int(result["revision"]),
			"document": PrawnSkinCatalog.clean(result["document"]),
		}
		_pending.erase(key)
		if _peers.get(peer, "") == key and _key(peer) == key:
			_publish(peer)
			_update(peer, "Saved.", plan["reward"])
	elif result.get("rejected", false):
		_pending.erase(key)
		if _peers.get(peer, "") == key and _key(peer) == key:
			_update(peer, str(result.get("error", "Purchase rejected")))
			# A revision conflict can mean another server/session updated the account.
			_load(peer, key, str(result.get("error", "Purchase rejected")))
	else:
		# Do not allow a fresh purchase or roll until this exact transaction resolves.
		_update(peer, "Storage unavailable. Retry the saved transaction; do not buy again.")


func _publish(peer: int) -> void:
	net_equipped = net_equipped.duplicate(true)
	net_equipped[peer] = _collections[_key(peer)]["document"]["equipped"].duplicate()


func _update(peer: int, message: String = "", reward: String = "") -> void:
	if entity.player_for_peer(peer) != null and _peers.get(peer, "") == _key(peer):
		entity.send_event(&"update", _snapshot(peer, message, reward), peer)


func _apply_appearance() -> void:
	for hand: Hand in get_tree().get_nodes_in_group(&"hands"):
		var view := hand.held_view()
		if view == null:
			continue
		var equipped: Dictionary = net_equipped.get(hand.peer_id, {})
		var skin: String = str(equipped.get(hand.net_item_id, ""))
		PrawnSkinAppearance.apply(view, skin)


func _configured() -> bool:
	return PrawnSkinCatalog.valid_odds(odds) and PrawnSkinCatalog.valid_refunds(duplicate_cents)


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	net_equipped = {}
	_collections.clear()
	_peers.clear()
	_players.clear()
	_busy.clear()
	_pending.clear()
