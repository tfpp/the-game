class_name PlayerMoney
extends Node
## Server-owned wallets. Online balances live in the accounts API's SQLite DB;
## offline/dev wallets are temporary and never cross into authenticated accounts.

const COIN_CREDIT_CENTS := 1000
const DEFAULT_INCOME_CENTS := 500
const GIRL_INCOME_CENTS := 425
const INCOME_REASON := "Income for time connected"
## Temporary (offline / dev-auth) wallets start with this: $20.
const STARTING_CENTS := 2000
## Local development only: $100,000 when running the project from the Godot editor
## binary with a window (see `local_dev()`). Exported builds and headless checks
## keep STARTING_CENTS; real accounts are never affected.
const DEV_STARTING_CENTS := 100_000_00

@export var balances: Dictionary = {}
var _busy: Dictionary = {}
var _animated_spins: Dictionary = {}
var _generation := 0
var _poll_elapsed := 5.0
var _unresolved: Dictionary = {}
var _cosmetic_results: Dictionary = {}
var _temporary_seconds: Dictionary = {}
var _temporary_income_units: Dictionary = {}
var _starting_cents := DEV_STARTING_CENTS if local_dev() else STARTING_CENTS


func _ready() -> void:
	add_to_group(&"player_money")
	Network.mode_changed.connect(_reset)


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	balances = {}
	_busy.clear()
	_animated_spins.clear()
	_temporary_seconds.clear()
	_temporary_income_units.clear()
	_unresolved.clear()
	_cosmetic_results.clear()
	_poll_elapsed = 5.0


func _process(delta: float) -> void:
	_poll_elapsed += delta
	var poorest := poorest_peers(balances)
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		var peer := player.get_multiplayer_authority()
		if multiplayer.is_server() and _temporary() and _account(peer) <= 0:
			var seconds := float(_temporary_seconds.get(peer, 0.0)) + delta
			var units := float(_temporary_income_units.get(peer, 0.0)) + delta * _income_cents(peer)
			while seconds >= 60.0:
				var minute_units := roundi(units * 60.0 / seconds)
				var balance := int(balances.get(peer, _starting_cents))
				var prize := mini(_roll_income(minute_units), IncomeRoll.MAX_CENTS - balance)
				_set_balance(peer, balance + prize)
				announce_gain(peer, prize, INCOME_REASON)
				units -= units * 60.0 / seconds
				seconds -= 60.0
			_temporary_seconds[peer] = seconds
			_temporary_income_units[peer] = units
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
		var flies := player.get_node_or_null("PovertyFlies") as PovertyFlies
		if poorest.has(peer):
			if flies == null:
				flies = PovertyFlies.new()
				flies.name = "PovertyFlies"
				flies.position.y = player.movement.hull_height_m() * 0.5 + 0.65
				player.add_child(flies)
		elif flies != null:
			flies.queue_free()
	if _poll_elapsed >= 5.0:
		_poll_elapsed = 0.0
		if multiplayer.is_server():
			for peer: int in balances.keys():
				if peer != 1 and not Network.peer_accounts.has(peer):
					balances = balances.duplicate()
					balances.erase(peer)
					_temporary_seconds.erase(peer)
					_temporary_income_units.erase(peer)


func _set_balance(peer: int, cents: int) -> void:
	var previous: Variant = balances.get(peer)
	balances = balances.duplicate()
	balances[peer] = cents
	if multiplayer.is_server() and lands_on_six_seven(previous, cents):
		var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
		if models != null:
			models.emote_everyone()


## True when a wallet newly reads $67 in whole dollars (cents ignored: $67.00-$67.99).
static func lands_on_six_seven(previous: Variant, cents: int) -> bool:
	return _is_six_seven(cents) and not (previous is int and _is_six_seven(previous))


static func _is_six_seven(cents: int) -> bool:
	return cents >= 6700 and cents < 6800


## Server-only: tells `peer` in their chat log that they received `cents` and why.
## Every payout path calls this; features paying out another way should too.
func announce_gain(peer: int, cents: int, reason: String) -> void:
	if not multiplayer.is_server() or cents <= 0:
		return
	var chat := get_tree().get_first_node_in_group(&"chat_box")
	if chat != null:
		chat.send_notice(peer, gain_text(cents, reason))


static func gain_text(cents: int, reason: String) -> String:
	return "+%s: %s" % [format_money(cents), reason]


## "$1,234,567.89", "-$5.00". Integer maths, so large balances never round.
static func format_money(cents: int) -> String:
	var whole := str(absi(cents) / 100)
	var grouped := ""
	while whole.length() > 3:
		grouped = "," + whole.right(3) + grouped
		whole = whole.left(whole.length() - 3)
	var sign := "-" if cents < 0 else ""
	return "%s$%s%s.%02d" % [sign, whole, grouped, absi(cents) % 100]


## Peers in the poorest 80% by wallet balance (rounded down), poorest first. A lone
## wallet is never "poorer" than anyone, so it takes at least two known balances
## before anyone is flagged. Ties break on peer ID so every client agrees.
static func poorest_peers(all_balances: Dictionary) -> Dictionary:
	var peers: Array[int] = []
	for peer: int in all_balances.keys():
		peers.append(peer)
	peers.sort_custom(
		func(a: int, b: int) -> bool:
			var balance_a: int = all_balances[a]
			var balance_b: int = all_balances[b]
			return balance_a < balance_b if balance_a != balance_b else a < b
	)
	var result := {}
	for i in (peers.size() * 4) / 5:
		result[peers[i]] = true
	return result


## Server-only: the accounts API ID behind `peer`, or 0 for temporary wallets.
func account_for(peer: int) -> int:
	return _account(peer)


## True when running the project locally from the editor binary with a window. Exported
## web/server builds lack the "editor" feature; GUT and the smoke tests run headless.
static func local_dev() -> bool:
	return OS.has_feature("editor") and DisplayServer.get_name() != "headless"


func _account(peer: int) -> int:
	var account: Dictionary = Network.peer_accounts.get(peer, {})
	return int(account.get("account_id", 0))


func _temporary() -> bool:
	return Network.mode == Network.Mode.OFFLINE or Network.insecure_auth


func _roll_income(units: int) -> int:
	return IncomeRoll.sample(units, func(bound: int) -> int: return randi_range(0, bound - 1))


func _income_cents(peer: int) -> int:
	var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
	return (
		GIRL_INCOME_CENTS
		if models != null and models.type_for(peer) == "girl"
		else DEFAULT_INCOME_CENTS
	)


func _refresh(peer: int) -> void:
	_busy[peer] = true
	var generation := _generation
	var account := _account(peer)
	if _temporary() and account <= 0:
		if not balances.has(peer):
			_set_balance(peer, _starting_cents)
	else:
		var result: Dictionary = await _request(
			account, "balance", "", {"income_cents": _income_cents(peer)}
		)
		if generation != _generation:
			return
		if _account(peer) == account and result.has("balance"):
			var previous := int(balances.get(peer, -1))
			_set_balance(peer, int(result["balance"]))
			# Every other change settles through its own call, so a heartbeat
			# that raises a known balance is minute income.
			if previous >= 0 and int(result["balance"]) > previous:
				announce_gain(peer, int(result["balance"]) - previous, INCOME_REASON)
	_busy.erase(peer)


## wager_cents lets each slot machine set its own buy-in (default $1).
## `rerolls` retains temporary-wallet extra rolls; `blessings` applies exact Kaaba odds.
## Both temporary wallets and the accounts API apply +200% base win chance per stack.
func spin(
	peer: int, id: String, wager_cents: int = 100, rerolls: int = 0, blessings: int = 0
) -> Dictionary:
	if not multiplayer.is_server() or _busy.has(peer):
		return {"error": "Wallet loading — try again"}
	_busy[peer] = true
	var generation := _generation
	var account := _account(peer)
	var result: Dictionary
	if _temporary() and account <= 0:
		var balance := int(balances.get(peer, _starting_cents))
		if balance < wager_cents:
			result = {"error": "You need %s to spin" % format_money(wager_cents)}
		else:
			var cycle := SlotSpinCycle.new()
			var reels := cycle.blessed_result(blessings)
			for attempt: int in maxi(rerolls, 0):
				if SlotSpinCycle.is_win(reels):
					break
				reels = cycle.next_result()
			var payout := SlotSpinCycle.payout(reels, wager_cents)
			result = {"reels": reels, "payout": payout, "balance": balance - wager_cents + payout}
	else:
		if not _unresolved.has(account):
			_unresolved[account] = id
		result = await _request(
			account,
			"spin",
			str(_unresolved[account]),
			{"wager_cents": wager_cents, "blessings": clampi(blessings, 0, 5)}
		)
		if generation == _generation and (result.has("balance") or result.has("rejected")):
			_unresolved.erase(account)
	if generation != _generation:
		return {"error": "Session changed"}
	if _account(peer) == account and result.has("balance"):
		var held := int(result.get("payout", 0)) if _animated_spins.has(peer) else 0
		_set_balance(peer, int(result["balance"]) - held)
		if _animated_spins.has(peer):
			_animated_spins[peer]["payout"] = held
			_animated_spins[peer]["account"] = account
			return result  # Keep refreshes and other transactions locked until reveal.
	_animated_spins.erase(peer)
	_busy.erase(peer)
	return result


## Slots alone use this wrapper. The API still commits atomically for crash safety,
## but replicated/spendable winnings wait for the server's animation completion.
func spin_animated(
	peer: int, id: String, wager_cents: int = 100, rerolls: int = 0, blessings: int = 0
) -> Dictionary:
	if not multiplayer.is_server() or _busy.has(peer):
		return {"error": "Wallet loading — try again"}
	_animated_spins[peer] = {"id": id}
	return await spin(peer, id, wager_cents, rerolls, blessings)


## Server-only and idempotent. Never restores an old absolute balance over income.
func reveal_spin(peer: int, id: String) -> void:
	if not multiplayer.is_server() or not _animated_spins.has(peer):
		return
	var held: Dictionary = _animated_spins[peer]
	if held["id"] != id or not held.has("payout"):
		return
	_animated_spins.erase(peer)
	_busy.erase(peer)
	if _account(peer) == int(held["account"]) and balances.has(peer):
		_set_balance(peer, int(balances[peer]) + int(held["payout"]))


## Server-only: pays a fixed $10 reward for a map coin pickup into `peer`'s wallet,
## the same persisted, idempotent-retry path `spin()` uses for paid spins.
## `reason` is shown to the player in the chat log ("+$10.00 — reason").
func credit_coin(peer: int, id: String, reason: String) -> Dictionary:
	if not multiplayer.is_server() or _busy.has(peer):
		return {"error": "Wallet loading — try again"}
	_busy[peer] = true
	var generation := _generation
	var account := _account(peer)
	var result: Dictionary
	if _temporary() and account <= 0:
		var balance := int(balances.get(peer, _starting_cents)) + COIN_CREDIT_CENTS
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
		announce_gain(peer, COIN_CREDIT_CENTS, reason)
	_busy.erase(peer)
	return result


## Server-only: settles one valuable at its catalog price. The caller holds the
## item while awaiting the result and retries the same operation ID if the API
## response is lost. The API records the amount and rejects altered retries.
func sell_loot(peer: int, id: String, amount_cents: int, reason: String) -> Dictionary:
	if not multiplayer.is_server() or _busy.has(peer) or amount_cents <= 0:
		return {"error": "Wallet loading — try again"}
	_busy[peer] = true
	var generation := _generation
	var account := _account(peer)
	var result: Dictionary
	if _temporary() and account <= 0:
		result = {"balance": int(balances.get(peer, _starting_cents)) + amount_cents}
	else:
		result = await _request(account, "sell", id, {"amount_cents": amount_cents})
	if generation != _generation:
		return {"error": "Session changed"}
	if _account(peer) == account and result.has("balance"):
		_set_balance(peer, int(result["balance"]))
		announce_gain(peer, amount_cents, reason)
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
		var balance := int(balances.get(peer, _starting_cents))
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


## Server-only: settles one player's whole roulette round in a single atomic,
## idempotent operation: deducts `wager_cents` and pays `payout_cents` (winnings plus
## returned stakes). `account` is the account captured when the bets locked, so a
## disconnect mid-spin still settles the bet. Rejects everything, including a win,
## if the wallet can't cover the wager. Retry with the same `id` after an error.
func settle_roulette(
	peer: int, account: int, id: String, wager_cents: int, payout_cents: int
) -> Dictionary:
	if not multiplayer.is_server() or _busy.has(peer) or wager_cents <= 0 or payout_cents < 0:
		return {"error": "Wallet loading — try again"}
	_busy[peer] = true
	var generation := _generation
	var result: Dictionary
	if account <= 0:
		var balance := int(balances.get(peer, -1))
		if not _temporary() or balance < 0:
			result = {"error": "Wallet unavailable", "rejected": true}
		elif balance < wager_cents:
			result = {"error": "You can't cover that bet", "rejected": true}
		else:
			result = {"balance": balance - wager_cents + payout_cents}
	else:
		result = await _request(
			account, "roulette", id, {"wager_cents": wager_cents, "payout_cents": payout_cents}
		)
	if generation != _generation:
		return {"error": "Session changed", "rejected": true}
	if _account(peer) == account and result.has("balance"):
		_set_balance(peer, int(result["balance"]))
	_busy.erase(peer)
	return result


## Godot JSON numbers are floats. Read the trusted API's integer balance token
## directly so jackpots above 2^53 cents retain cents and cannot wrap at int64 max.
static func parse_response(body: String) -> Variant:
	var json := JSON.new()
	if json.parse(body) != OK:
		return null
	var parsed: Variant = json.data
	if parsed is Dictionary and parsed.has("balance"):
		var token := RegEx.new()
		token.compile('"balance"[[:space:]]*:[[:space:]]*(-?[0-9]+)')
		var found := token.search(body)
		if found != null:
			parsed["balance"] = found.get_string(1).to_int()
	return parsed


## Server-only atomic wallet + cosmetic-document transaction. The pawn shop owns
## collection rules and retains the exact ID/document for unresolved retries.
## Load never changes the document. Real accounts commit both sides in SQLite.
func cosmetics(
	peer: int, id: String, revision: int, document: Dictionary, delta: int, load: bool = false
) -> Dictionary:
	if not multiplayer.is_server():
		return {"error": "Wallet unavailable"}
	var generation := _generation
	var account := _account(peer)
	# Initial account loads often overlap the first wallet heartbeat. Wait instead
	# of leaving a persisted equipped skin unloaded until a manual menu refresh.
	while load and _busy.has(peer):
		await get_tree().process_frame
		if generation != _generation or _account(peer) != account:
			return {"error": "Session changed"}
	if _busy.has(peer):
		return {"error": "Wallet loading — try again"}
	_busy[peer] = true
	var result: Dictionary
	var replayed := false
	if _temporary() and account <= 0:
		if _cosmetic_results.has(id):
			var receipt: Dictionary = _cosmetic_results[id]
			if (
				receipt["peer"] != peer
				or receipt["revision"] != revision
				or receipt["delta"] != delta
				or receipt["document"] != document
			):
				result = {"error": "Cosmetic transaction changed", "rejected": true}
			else:
				replayed = true
				result = receipt["result"].duplicate(true)
				# Income and other purchases since settlement remain additive.
				result["balance"] = int(balances.get(peer, _starting_cents))
		else:
			var balance := int(balances.get(peer, _starting_cents))
			if load:
				result = {"revision": 0, "document": {}, "balance": balance}
			elif balance + delta < 0:
				result = {"error": "You can't afford that crate", "rejected": true}
			else:
				result = {
					"revision": revision + 1, "document": document, "balance": balance + delta
				}
				_cosmetic_results[id] = {
					"peer": peer,
					"revision": revision,
					"delta": delta,
					"document": document.duplicate(true),
					"result": result.duplicate(true),
				}
	else:
		var action := "cosmetics_load" if load else "cosmetics"
		result = await _request(
			account, action, id, {"revision": revision, "document": document, "delta": delta}
		)
	if generation != _generation:
		return {"error": "Session changed"}
	if _account(peer) == account and result.has("balance"):
		_set_balance(peer, int(result["balance"]))
		if delta > 0 and not load and not replayed:
			announce_gain(peer, delta, "Duplicate prawn skin exchange")
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
		var parsed: Variant = parse_response(bytes.get_string_from_utf8())
		if int(response[1]) == 200 and parsed is Dictionary:
			return parsed as Dictionary
		if int(response[1]) == 409 and parsed is Dictionary:
			return {"error": str(parsed.get("message", "Spin rejected")), "rejected": true}
	return {"error": "Wallet unavailable — try again"}
