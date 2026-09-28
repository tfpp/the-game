class_name PlayerMoney
extends Node
## Server-owned wallets. Online balances live in the accounts API's SQLite DB;
## offline/dev wallets are temporary and never cross into authenticated accounts.

const COIN_CREDIT_CENTS := 1000

@export var balances: Dictionary = {}
var _busy: Dictionary = {}
var _generation := 0
var _poll_elapsed := 5.0
var _unresolved: Dictionary = {}
var _temporary_seconds: Dictionary = {}


func _ready() -> void:
	add_to_group(&"player_money")
	Network.mode_changed.connect(_reset)


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	balances = {}
	_busy.clear()
	_temporary_seconds.clear()
	_unresolved.clear()
	_poll_elapsed = 5.0


func _process(delta: float) -> void:
	_poll_elapsed += delta
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		var peer := player.get_multiplayer_authority()
		if multiplayer.is_server() and _temporary() and _account(peer) <= 0:
			var seconds := float(_temporary_seconds.get(peer, 0.0)) + delta
			if seconds >= 60.0:
				_set_balance(peer, int(balances.get(peer, 2000)) + 500)
				seconds -= 60.0
			_temporary_seconds[peer] = seconds
		if multiplayer.is_server() and _poll_elapsed >= 5.0 and not _busy.has(peer):
			_refresh(peer)
		if player.is_local():
			continue
		var label := player.get_node_or_null("MoneyLabel") as Label3D
		if label == null:
			label = Label3D.new()
			label.name = "MoneyLabel"
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.fixed_size = true
			label.pixel_size = 0.0015
			label.font_size = 20
			label.outline_size = 6
			label.no_depth_test = true
			label.modulate = Color("83e59b")
			# Same anchor as the name; a pixel offset keeps the two lines
			# separated even when fixed-size labels are viewed from far away.
			label.position.y = player.movement.hull_height_m() * 0.5 + 0.35
			label.offset.y = -26.0
			player.add_child(label)
		label.text = format_money(int(balances[peer])) if balances.has(peer) else "…"
	if _poll_elapsed >= 5.0:
		_poll_elapsed = 0.0
		if multiplayer.is_server():
			for peer: int in balances.keys():
				if peer != 1 and not Network.peer_accounts.has(peer):
					balances = balances.duplicate()
					balances.erase(peer)
					_temporary_seconds.erase(peer)


func _set_balance(peer: int, cents: int) -> void:
	balances = balances.duplicate()
	balances[peer] = cents


static func format_money(cents: int) -> String:
	return "$%.2f" % (float(cents) / 100.0)


func _account(peer: int) -> int:
	var account: Dictionary = Network.peer_accounts.get(peer, {})
	return int(account.get("account_id", 0))


func _temporary() -> bool:
	return Network.mode == Network.Mode.OFFLINE or Network.insecure_auth


func _refresh(peer: int) -> void:
	_busy[peer] = true
	var generation := _generation
	var account := _account(peer)
	if _temporary() and account <= 0:
		if not balances.has(peer):
			_set_balance(peer, 2000)
	else:
		var result: Dictionary = await _request(account, "balance", "")
		if generation != _generation:
			return
		if _account(peer) == account and result.has("balance"):
			_set_balance(peer, int(result["balance"]))
	_busy.erase(peer)


func spin(peer: int, id: String) -> Dictionary:
	if not multiplayer.is_server() or _busy.has(peer):
		return {"error": "Wallet loading — try again"}
	_busy[peer] = true
	var generation := _generation
	var account := _account(peer)
	var result: Dictionary
	if _temporary() and account <= 0:
		var balance := int(balances.get(peer, 2000))
		if balance < 100:
			result = {"error": "You need $1 to spin"}
		else:
			var reels := SlotSpinCycle.new().next_result()
			var payout := SlotSpinCycle.payout(reels)
			result = {"reels": reels, "payout": payout, "balance": balance - 100 + payout}
	else:
		if not _unresolved.has(account):
			_unresolved[account] = id
		result = await _request(account, "spin", str(_unresolved[account]))
		if generation == _generation and (result.has("balance") or result.has("rejected")):
			_unresolved.erase(account)
	if generation != _generation:
		return {"error": "Session changed"}
	if _account(peer) == account and result.has("balance"):
		_set_balance(peer, int(result["balance"]))
	_busy.erase(peer)
	return result


## Server-only: pays a fixed $10 reward for a map coin pickup into `peer`'s wallet,
## the same persisted, idempotent-retry path `spin()` uses for paid spins.
func credit_coin(peer: int, id: String) -> Dictionary:
	if not multiplayer.is_server() or _busy.has(peer):
		return {"error": "Wallet loading — try again"}
	_busy[peer] = true
	var generation := _generation
	var account := _account(peer)
	var result: Dictionary
	if _temporary() and account <= 0:
		var balance := int(balances.get(peer, 2000)) + COIN_CREDIT_CENTS
		result = {"balance": balance}
	else:
		if not _unresolved.has(account):
			_unresolved[account] = id
		result = await _request(account, "credit", str(_unresolved[account]))
		if generation == _generation and result.has("balance"):
			_unresolved.erase(account)
	if generation != _generation:
		return {"error": "Session changed"}
	if _account(peer) == account and result.has("balance"):
		_set_balance(peer, int(result["balance"]))
	_busy.erase(peer)
	return result


## Server-only: deducts a flat, feature-chosen price from `peer`'s wallet — the same
## persisted, idempotent-retry path `credit_coin()` uses in the other direction.
## Rejects (without spending anything) if the wallet can't cover `amount_cents`.
## Used by paid one-off purchases like features/gun_machine's machine.
func charge(peer: int, id: String, amount_cents: int) -> Dictionary:
	if not multiplayer.is_server() or _busy.has(peer):
		return {"error": "Wallet loading — try again"}
	_busy[peer] = true
	var generation := _generation
	var account := _account(peer)
	var result: Dictionary
	if _temporary() and account <= 0:
		var balance := int(balances.get(peer, 2000))
		if balance < amount_cents:
			result = {"error": "You can't afford that"}
		else:
			result = {"balance": balance - amount_cents}
	else:
		if not _unresolved.has(account):
			_unresolved[account] = id
		result = await _request(
			account, "charge", str(_unresolved[account]), {"amount_cents": amount_cents}
		)
		if generation == _generation and (result.has("balance") or result.has("rejected")):
			_unresolved.erase(account)
	if generation != _generation:
		return {"error": "Session changed"}
	if _account(peer) == account and result.has("balance"):
		_set_balance(peer, int(result["balance"]))
	_busy.erase(peer)
	return result


func _request(account: int, action: String, id: String, extra: Dictionary = {}) -> Dictionary:
	if account <= 0 or Network.ticket_key.is_empty():
		return {"error": "Wallet unavailable"}
	var generation := _generation
	# Retries reuse the operation ID; the database charges each spin only once.
	for attempt: int in 3:
		if generation != _generation:
			return {"error": "Session changed"}
		var payload := {
			"account_id": account,
			"action": action,
			"id": id,
			"timestamp": int(Time.get_unix_time_from_system())
		}
		for key: String in extra:
			payload[key] = extra[key]
		var body := JSON.stringify(payload)
		var signature := (
			Crypto
			. new()
			. hmac_digest(
				HashingContext.HASH_SHA256,
				Network.ticket_key,
				("game-money-v1\n" + body).to_utf8_buffer()
			)
			. hex_encode()
		)
		var request := HTTPRequest.new()
		request.timeout = 5.0
		add_child(request)
		var error := request.request(
			Network.resolve_api_url() + "/game/money",
			["Content-Type: application/json", "X-Game-Signature: " + signature],
			HTTPClient.METHOD_POST,
			body
		)
		if error != OK:
			request.queue_free()
			continue
		var response: Array = await request.request_completed
		request.queue_free()
		if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
			continue
		var bytes: PackedByteArray = response[3]
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if int(response[1]) == 200 and parsed is Dictionary:
			return parsed as Dictionary
		if int(response[1]) == 409 and parsed is Dictionary:
			return {"error": str(parsed.get("message", "Spin rejected")), "rejected": true}
	return {"error": "Wallet unavailable — try again"}
