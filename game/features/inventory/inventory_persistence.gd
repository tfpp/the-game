class_name InventoryPersistence
extends Node
## Server-only: keeps signed-in players' inventories in the accounts API's SQLite
## database, so items survive disconnects, server restarts and redeploys. Offline
## play uses a local atomic inventory file after first using the van stash.
## Dev-auth players without an account keep session inventory; saved stash is unavailable.
##
## A new Hand loads its account's saved snapshot before it accepts any change
## (`PlayerInventory.loading`). Afterwards, changes are saved at most once per
## `SAVE_INTERVAL`, plus a final save when the Hand leaves. Each account has at
## most one request in flight, so saves reach the database in order.

const SAVE_INTERVAL := 1.0
const SIGNATURE_DOMAIN := "game-inventory-v1\n"

## Replaced by tests with a fake accounts API: func(payload: Dictionary) -> Dictionary.
var transport: Callable = _http
## Override or disable in tests. Activated when the offline van stash is first used.
var offline_path := "user://offline-inventory.json"
## Hand instance ID -> {hand, account, saved}
var _tracked: Dictionary = {}
## Account ID -> true while a request for it is in flight.
var _busy: Dictionary = {}
## Account ID -> newest snapshot waiting for the in-flight request to finish.
var _pending: Dictionary = {}
var _elapsed := 0.0
var _generation := 0


func _ready() -> void:
	add_to_group(&"inventory_persistence")
	Network.mode_changed.connect(_reset)


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	_tracked.clear()
	_busy.clear()
	_pending.clear()


func _process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	for node: Node in get_tree().get_nodes_in_group(&"hands"):
		var hand := node as Hand
		if hand != null and not _tracked.has(hand.get_instance_id()):
			_track(hand)
	_elapsed += delta
	if _elapsed < SAVE_INTERVAL:
		return
	_elapsed = 0.0
	for key: int in _tracked.keys():
		var entry: Dictionary = _tracked[key]
		var hand := entry["hand"] as Hand
		if is_instance_valid(hand) and not hand.inventory().loading:
			if entry["account"] > 0:
				_save_if_changed(entry, hand.inventory().snapshot())
			elif entry.get("local", false):
				var snapshot := hand.inventory().snapshot()
				if snapshot != entry["saved"] and _write_offline(snapshot):
					entry["saved"] = snapshot


static func account_for(peer: int) -> int:
	var account: Dictionary = Network.peer_accounts.get(peer, {})
	return int(account.get("account_id", 0))


func _track(hand: Hand) -> void:
	var key := hand.get_instance_id()
	var entry := {"hand": hand, "account": account_for(hand.peer_id), "saved": {}}
	_tracked[key] = entry
	hand.tree_exiting.connect(_on_hand_exiting.bind(key), CONNECT_ONE_SHOT)
	if entry["account"] > 0:
		_load(entry)
	elif Network.mode == Network.Mode.OFFLINE and not offline_path.is_empty():
		entry["local"] = FileAccess.file_exists(offline_path)
		if entry["local"]:
			var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(offline_path))
			if saved is Dictionary:
				hand.inventory().restore(saved)
				entry["saved"] = hand.inventory().snapshot()
			else:
				entry["local_failed"] = true
				entry["local"] = false


func _load(entry: Dictionary) -> void:
	var hand := entry["hand"] as Hand
	var inventory := hand.inventory()
	var generation := _generation
	inventory.loading = true
	var result := {}
	# The previous session's final save may still be in flight for this account.
	while _busy.has(entry["account"]):
		await get_tree().process_frame
	_busy[entry["account"]] = true
	for attempt: int in 3:
		result = await transport.call({"account_id": entry["account"], "action": "load"})
		if generation != _generation:
			return
		if result.has("inventory"):
			break
	_finish(entry["account"])
	if not is_instance_valid(hand):
		return
	inventory.loading = false
	var saved: Variant = result.get("inventory")
	if saved is Dictionary:
		inventory.restore(saved)
		entry["saved"] = saved
	elif not result.has("inventory"):
		# The API is unreachable: keep the session playable, but never overwrite the
		# stored items with this session's (probably empty) inventory.
		entry["account"] = 0
		push_warning("Inventory for peer %d could not be loaded; not saving it" % hand.peer_id)


func _on_hand_exiting(key: int) -> void:
	var entry: Dictionary = _tracked.get(key, {})
	_tracked.erase(key)
	var hand := entry.get("hand") as Hand
	if entry.get("account", 0) > 0 and is_instance_valid(hand) and not hand.inventory().loading:
		_save_if_changed(entry, hand.inventory().snapshot())
	elif entry.get("local", false) and is_instance_valid(hand) and not hand.inventory().loading:
		_write_offline(hand.inventory().snapshot())


func _save_if_changed(entry: Dictionary, snapshot: Dictionary) -> void:
	if snapshot == entry["saved"]:
		return
	if await _save(entry["account"], snapshot):
		entry["saved"] = snapshot


func _save(account: int, snapshot: Dictionary, warn_on_failure := true) -> bool:
	if _busy.has(account):
		_pending[account] = snapshot
		return false
	_busy[account] = true
	var generation := _generation
	var result := {}
	for attempt: int in 3:
		result = await transport.call(
			{"account_id": account, "action": "save", "inventory": snapshot}
		)
		if generation != _generation:
			return false
		if result.has("saved"):
			break
	if not result.has("saved") and warn_on_failure:
		push_warning("Inventory save for account %d failed: %s" % [account, result])
	_finish(account)
	return result.get("saved", false) == true


func _finish(account: int) -> void:
	_busy.erase(account)
	if _pending.has(account):
		var next: Dictionary = _pending[account]
		_pending.erase(account)
		_save(account, next)


func _http(payload: Dictionary) -> Dictionary:
	if Network.ticket_key.is_empty():
		return {"error": "Inventory storage unavailable"}
	payload["timestamp"] = int(Time.get_unix_time_from_system())
	var body := JSON.stringify(payload)
	var signature := (
		Crypto
		. new()
		. hmac_digest(
			HashingContext.HASH_SHA256,
			Network.ticket_key,
			(SIGNATURE_DOMAIN + body).to_utf8_buffer()
		)
		. hex_encode()
	)
	var request := HTTPRequest.new()
	request.timeout = 5.0
	add_child(request)
	var error := request.request(
		Network.resolve_api_url() + "/game/inventory",
		["Content-Type: application/json", "X-Game-Signature: " + signature],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		request.queue_free()
		return {"error": "Inventory storage unavailable"}
	var response: Array = await request.request_completed
	request.queue_free()
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if int(response[0]) == HTTPRequest.RESULT_SUCCESS and int(response[1]) == 200:
		if parsed is Dictionary:
			return parsed
	return {"error": "Inventory storage unavailable"}


## A van transfer commits carried items and stash together before acknowledging it.
## Callers hold inventory.loading until this finishes, preventing concurrent changes.
func commit_inventory(hand: Hand, snapshot: Dictionary) -> bool:
	var entry: Dictionary = _tracked.get(hand.get_instance_id(), {})
	if not multiplayer.is_server() or entry.is_empty():
		return false
	if entry["account"] > 0:
		var generation := _generation
		while _busy.has(entry["account"]):
			await get_tree().process_frame
			if generation != _generation:
				return false
		if not await _save(entry["account"], snapshot, false):
			return await _resolve_commit(entry, snapshot)
		entry["saved"] = snapshot
		return true
	if (
		Network.mode != Network.Mode.OFFLINE
		or entry.get("local_failed", false)
		or not _write_offline(snapshot)
	):
		return false
	entry["local"] = true
	entry["saved"] = snapshot
	return true


func can_commit(hand: Hand) -> bool:
	var entry: Dictionary = _tracked.get(hand.get_instance_id(), {})
	return (
		not entry.is_empty()
		and not entry.get("uncertain", false)
		and (
			entry["account"] > 0
			or (
				Network.mode == Network.Mode.OFFLINE
				and not offline_path.is_empty()
				and not entry.get("local_failed", false)
			)
		)
	)


func _write_offline(snapshot: Dictionary) -> bool:
	if offline_path.is_empty():
		return false
	var file := FileAccess.open(offline_path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(snapshot))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(offline_path + ".tmp", offline_path) == OK


## A lost HTTP response may hide a completed write. Read back before unlocking;
## if storage remains unreachable, keep this session locked rather than duplicate.
func _resolve_commit(entry: Dictionary, snapshot: Dictionary) -> bool:
	var account: int = entry["account"]
	var generation := _generation
	_busy[account] = true
	var result: Dictionary = await transport.call({"account_id": account, "action": "load"})
	if generation != _generation:
		return false
	_finish(account)
	if not result.has("inventory"):
		entry["uncertain"] = true
		return false
	if result.get("inventory") == snapshot:
		entry["saved"] = snapshot
		return true
	return false
