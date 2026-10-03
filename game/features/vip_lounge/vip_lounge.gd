class_name VipLounge
extends Node3D
## The Mirror Club owns eligibility and VIP records; PlayerMoney owns all currency.

const BOUNDS := AABB(Vector3(24, 4.8, -12), Vector3(8, 4, 24))

@export var profiles: Dictionary = {}
var store := VipStore.new()
var clock := Callable()
var _rows: Dictionary = {}
var _admitted: Dictionary = {}
var _arrival_until: Dictionary = {}
var _pending: Dictionary = {}
var _generation := 0
var _publish_left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"vip_lounge")
	add_to_group(&"vip_drinks")
	store.path = str(Network.args.get("vip-save-path", store.path))
	$NetworkedEntity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(_forget)


func now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())


func wallet() -> PlayerMoney:
	return get_tree().get_first_node_in_group(&"player_money") as PlayerMoney


func eligible(peer: int) -> bool:
	var money := wallet()
	return money != null and int(money.balances.get(peer, 0)) >= VipRules.ENTRY_CENTS


func admitted(peer: int) -> bool:
	return (
		_admitted.has(peer) if multiplayer.is_server() else bool(profile(peer).get("inside", false))
	)


func profile(peer: int) -> Dictionary:
	return profiles.get(peer, {})


func _key(peer: int) -> String:
	var money := wallet()
	var account := money.account_for(peer) if money != null else 0
	return str(account) if account > 0 else "session:%d" % peer


func record(peer: int) -> Dictionary:
	var key := _key(peer)
	if not _rows.has(key):
		store.load_records()
		_rows[key] = store.records.get(key, VipRules.empty_record()).duplicate(true)
	return _rows[key]


func _save(key: String, row: Dictionary) -> bool:
	if key.begins_with("session:"):
		return true
	store.records[key] = row.duplicate(true)
	return store.save()


func enter(player: Player, endpoint: NetworkedInteraction) -> bool:
	if not multiplayer.is_server() or not eligible(player.get_multiplayer_authority()):
		return false
	var peer := player.get_multiplayer_authority()
	var row := record(peer)
	row["discovered"] = true
	row["visits"] = int(row["visits"]) + 1
	_admitted[peer] = true
	_arrival_until[peer] = Time.get_ticks_msec() + 3000
	_save(_key(peer), row)
	_publish()
	endpoint.send_event(&"arrival", {"text": "Welcome upstairs. Keep our little secret."}, peer)
	return true


func leave(peer: int) -> void:
	if multiplayer.is_server():
		_admitted.erase(peer)
		_arrival_until.erase(peer)
		_publish()


func allowed(peer: int, action: String, payload: Dictionary) -> bool:
	if not multiplayer.is_server() or not admitted(peer):
		return false
	var row := record(peer)
	if action == "play":
		return (
			payload.size() == 1
			and payload.get("wager") is int
			and payload["wager"] in VipRules.WAGERS
		)
	if not payload.is_empty():
		return false
	if action in VipRules.DRINKS:
		return VipRules.seconds(row, action + "_ready", now()) == 0
	var permitted := false
	match action:
		"gift":
			permitted = VipRules.seconds(row, "gift_ready", now()) == 0
		"mission":
			permitted = VipRules.mission_ready(row)
		"shirt", "pants":
			permitted = row["mission"] and action not in row["wardrobe"]
		"symbol":
			permitted = not row["symbol"]
	return permitted


func talk(peer: int, host: String, endpoint: NetworkedInteraction) -> bool:
	if not multiplayer.is_server() or not admitted(peer):
		return false
	var row := record(peer)
	if host in ["Scarlett", "Jade", "Valentina"] and host not in row["hosts"]:
		row["hosts"].append(host)
		VipRules.progress(row, 10, now())
		_save(_key(peer), row)
	_publish()
	endpoint.send_event(&"menu", {"host": host}, peer)
	return true


func act(peer: int, action: String, payload: Dictionary, endpoint: NetworkedInteraction) -> bool:
	if not allowed(peer, action, payload):
		return false
	var row := record(peer)
	var key := _key(peer)
	var message := ""
	if action in VipRules.DRINKS:
		var hand := Hand.for_peer(get_tree(), peer)
		if hand == null or not hand.inventory().collect(VipRules.DRINK_ITEMS[action]):
			endpoint.send_event(&"receipt", {"text": "Make room in your inventory first."}, peer)
			return false
		row[action + "_ready"] = now() + VipRules.COOLDOWN_S
		message = (
			"%s added to your inventory. Hold it and use it to drink." % VipRules.DRINKS[action]
		)
		_save(key, row)
	elif action == "symbol":
		row["symbol"] = true
		VipRules.progress(row, 25, now())
		_save(key, row)
		message = "A crown behind the glass. Valentina might know what it means."
	elif action in ["shirt", "pants"]:
		var hand := Hand.for_peer(get_tree(), peer)
		var item := "shirt:7" if action == "shirt" else "pants:1"
		if hand == null or not hand.inventory().collect(item):
			endpoint.send_event(&"receipt", {"text": "Make room in your inventory first."}, peer)
			return false
		row["wardrobe"].append(action)
		_save(key, row)
		message = "Added %s to your wardrobe." % ClothingCatalog.title(item)
	else:
		return _begin_operation(peer, action, payload, endpoint)
	_publish()
	endpoint.send_event(&"receipt", {"text": message}, peer)
	endpoint.send_event(&"clink", {}, peer)
	return true


## The ordinary Hand consumption component calls these only on the server.
## Drinks can travel and be shared; effects belong to whoever finishes drinking.
func can_consume(peer: int, id: String) -> bool:
	var action: String = (
		VipRules.DRINK_ITEMS.find_key(id) if id in VipRules.DRINK_ITEMS.values() else ""
	)
	return (
		multiplayer.is_server()
		and not action.is_empty()
		and _player_for_peer(peer) != null
		and VipRules.seconds(record(peer), action, now()) == 0
	)


func consume(peer: int, id: String) -> bool:
	if not can_consume(peer, id):
		return false
	var action: String = VipRules.DRINK_ITEMS.find_key(id)
	var row := record(peer)
	var previous: Dictionary = row.duplicate(true)
	row["discovered"] = true
	row[action] = now() + (VipRules.LUCK_S if action == "luck" else VipRules.BOOST_S)
	if not _save(_key(peer), row):
		_rows[_key(peer)] = previous
		return false
	_publish()
	return true


func _begin_operation(
	peer: int, kind: String, payload: Dictionary, endpoint: NetworkedInteraction
) -> bool:
	var key := _key(peer)
	if wallet() == null or _pending.has(key):
		return false
	var row := record(peer)
	var tx: Dictionary = row["transaction"]
	if not tx.is_empty() and tx["kind"] != kind:
		endpoint.send_event(
			&"receipt", {"text": "Finish your pending %s first." % tx["kind"]}, peer
		)
		return false
	if tx.is_empty():
		tx = {
			"kind": kind,
			"id": Crypto.new().generate_random_bytes(32).hex_encode(),
			"at": now(),
			"wager": 0,
			"payout": 0,
			"reels": [],
			"collectible": ""
		}
		match kind:
			"play":
				tx["wager"] = payload["wager"]
				tx["reels"] = VipRules.reels(
					_rng.randi_range(0, 124), VipRules.seconds(row, "luck", now()) > 0
				)
				var reels: Array[int] = []
				reels.assign(tx["reels"])
				tx["payout"] = SlotSpinCycle.payout(reels, int(tx["wager"]))
			"gift":
				tx["payout"] = 5000
				var rare := _rng.randf() < VipRules.rare_chance(row, now())
				tx["collectible"] = VipRules.COLLECTION[3 if rare else _rng.randi_range(0, 2)]
			"mission":
				tx["payout"] = 10_000
		row["transaction"] = tx
	# Never submit an account transaction without a durable retry intent.
	if not _save(key, row):
		endpoint.send_event(
			&"receipt", {"text": "The guest book is unavailable. Try again shortly."}, peer
		)
		return false
	_pending[key] = true
	_settle(peer, key, row, tx, endpoint)
	return true


func _settle(
	peer: int, key: String, row: Dictionary, tx: Dictionary, endpoint: NetworkedInteraction
) -> void:
	var generation := _generation
	var money := wallet()
	var account := money.account_for(peer)
	var result: Dictionary
	if tx["kind"] == "play":
		result = await money.settle_roulette(
			peer, account, tx["id"], int(tx["wager"]), int(tx["payout"])
		)
	else:
		result = await money.adjust_account(
			peer, account, tx["id"], int(tx["payout"]), "Mirror Club " + str(tx["kind"])
		)
	if generation != _generation or not is_inside_tree():
		return
	_pending.erase(key)
	var message := str(result.get("error", ""))
	if result.has("balance"):
		match tx["kind"]:
			"play":
				row["played"] = true
				VipRules.progress(row, 10, int(tx["at"]))
				message = (
					"%s — %s"
					% [
						str(tx["reels"]),
						(
							"Won " + PlayerMoney.format_money(int(tx["payout"]))
							if int(tx["payout"]) > 0
							else "No match. Try your luck again."
						)
					]
				)
				if int(tx["payout"]) > 0:
					money.announce_gain(peer, int(tx["payout"]), "Mirror Club private table")
			"gift":
				row["gift_ready"] = VipRules.next_day(int(tx["at"]))
				if tx["collectible"] not in row["collection"]:
					row["collection"].append(tx["collectible"])
				message = "A $50 gift and %s for your collection." % tx["collectible"]
			"mission":
				row["mission"] = true
				VipRules.progress(row, 100, int(tx["at"]))
				message = (
					"House Favorite unlocked. Your $100 tip and evening outfit are ready. "
					+ "The crown's owner? Even we don't ask."
				)
		row["transaction"] = {}
	elif result.get("rejected", false):
		row["transaction"] = {}
	else:
		message += " Use the same service to retry your saved transaction."
	_save(key, row)
	_publish()
	if is_instance_valid(endpoint) and _key(peer) == key and endpoint.player_for_peer(peer) != null:
		endpoint.send_event(&"receipt", {"text": message}, peer)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	# Leaving via another system or dying ends this visit; a lower wallet does not.
	for peer: int in _admitted.keys():
		var player := _player_for_peer(peer)
		if Time.get_ticks_msec() < int(_arrival_until.get(peer, 0)):
			continue
		if player == null or not BOUNDS.grow(0.5).has_point(player.net_position):
			_admitted.erase(peer)
	_publish_left -= delta
	if _publish_left <= 0.0:
		_publish()


func _publish() -> void:
	_publish_left = 1.0
	var next := {}
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		var peer := player.get_multiplayer_authority()
		var row := record(peer)
		if not row["discovered"]:
			continue
		var summary := row.duplicate(true)
		summary.erase("transaction")
		for field: String in [
			"luck", "golden", "velvet", "luck_ready", "golden_ready", "velvet_ready", "gift_ready"
		]:
			summary[field] = VipRules.seconds(row, field, now())
		summary["inside"] = admitted(peer)
		summary["pending"] = not (row["transaction"] as Dictionary).is_empty()
		next[peer] = summary
	profiles = next


func _player_for_peer(peer: int) -> Player:
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		if player.get_multiplayer_authority() == peer:
			return player
	return null


func _forget(peer: int) -> void:
	if multiplayer.is_server():
		_admitted.erase(peer)
		_arrival_until.erase(peer)
		_rows.erase("session:%d" % peer)
		profiles.erase(peer)


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	_rows.clear()
	_admitted.clear()
	_arrival_until.clear()
	_pending.clear()
	profiles = {}
