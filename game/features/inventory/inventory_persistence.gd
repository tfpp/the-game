class_name InventoryPersistence
extends Node
## Server-only: keeps signed-in players' inventories in the accounts API's SQLite
## database, so items survive disconnects, server restarts and redeploys. Offline
## and dev-auth players (no account ID) keep the in-memory behavior.
##
## A new Hand loads its account's saved snapshot before it accepts any change
## (`PlayerInventory.loading`). Afterwards, changes are saved at most once per
## `SAVE_INTERVAL`, plus a final save when the Hand leaves. Each account has at
## most one request in flight, so saves reach the database in order.

const SAVE_INTERVAL := 1.0
const SIGNATURE_DOMAIN := "game-inventory-v1\n"

## Replaced by tests with a fake accounts API: func(payload: Dictionary) -> Dictionary.
var transport: Callable = _http
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
		if entry["account"] > 0 and is_instance_valid(hand) and not hand.inventory().loading:
			_save_if_changed(entry, hand.inventory().snapshot())


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


func _save_if_changed(entry: Dictionary, snapshot: Dictionary) -> void:
	if snapshot == entry["saved"]:
		return
	entry["saved"] = snapshot
	_save(entry["account"], snapshot)


func _save(account: int, snapshot: Dictionary) -> void:
	if _busy.has(account):
		_pending[account] = snapshot
		return
	_busy[account] = true
	var generation := _generation
	var result := {}
	for attempt: int in 3:
		result = await transport.call(
			{"account_id": account, "action": "save", "inventory": snapshot}
		)
		if generation != _generation:
			return
		if result.has("saved"):
			break
	if not result.has("saved"):
		push_warning("Inventory save for account %d failed: %s" % [account, result])
	_finish(account)


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
