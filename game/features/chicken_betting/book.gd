class_name ChickenBettingBook
extends StaticBody3D
## Sole owner of the communal book, rounds and immutable wallet operations.

@export var config: ChickenFightConfig = ChickenFightConfig.new()
@export var state: Dictionary = {
	"phase": "idle",
	"match": 0,
	"birds": [],
	"odds": [],
	"health": [],
	"round": 0,
	"attack": {},
	"winner": -1,
	"bets": {},
	"seconds": 0
}

var _tickets: Dictionary = {}
var _journal := ChickenBetJournal.new()
var _rng := RandomNumberGenerator.new()
var _elapsed := 0.0
var _poll := 0.0
var _generation := 0
var _recovery_started := false
var _menu: ChickenBettingMenu

@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var room: StreamedRoom = get_parent() as StreamedRoom


func _ready() -> void:
	add_to_group(&"interactables")
	_rng.randomize()
	entity.register_use(can_use, _open)
	entity.register_action(&"bet", _may_bet, _bet)
	entity.register_action(&"cancel", _may_cancel, _cancel)
	entity.event_received.connect(_event)
	entity.request_finished.connect(_feedback)
	Network.mode_changed.connect(_reset)


func interaction_point() -> Vector3:
	return to_global(Vector3(0, 1.15, 0.3))


func can_use(player: Player) -> bool:
	if not entity.in_range(player) or not room.contains(player.net_position):
		return false
	var eye := player.net_position + Vector3.UP * 0.5
	var offset := interaction_point() - eye
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	if offset.length() < 0.01 or look.dot(offset.normalized()) < 0.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, interaction_point(), 1, [player.get_rid()])
	var collider := get_world_3d().direct_space_state.intersect_ray(query).get("collider") as Node
	return collider != null and (collider == self or is_ancestor_of(collider))


func interaction_text() -> String:
	return "Chicken book — stats, odds & tickets"


func use() -> void:
	entity.request_use()


func _open(player: Player) -> bool:
	if state["phase"] == "idle" and _tickets.is_empty():
		_prepare()
	entity.send_event(&"menu", {}, player.get_multiplayer_authority())
	return true


func _event(event: StringName, _payload: Dictionary) -> void:
	if event == &"menu" and not is_instance_valid(_menu):
		_menu = ChickenBettingMenu.new()
		_menu.book = self
		add_child(_menu)


func _feedback(action: StringName, result: NetworkedEntity.Result) -> void:
	if action == &"bet" and is_instance_valid(_menu):
		_menu.feedback = (
			"Ticket requested — waiting for wallet."
			if result == NetworkedEntity.Result.ACCEPTED
			else "Refused: check balance, distance, limits or match status."
		)


func _prepare() -> void:
	var birds: Array = [
		ChickenFightSimulation.generate(_rng, config), ChickenFightSimulation.generate(_rng, config)
	]
	if birds[0]["name"] == birds[1]["name"]:
		birds[1]["name"] += " II"
	var next := state.duplicate(true)
	next.merge(
		{
			"phase": "preview",
			"match": int(state["match"]) + 1,
			"birds": birds,
			"odds": ChickenFightSimulation.odds(birds, config),
			"health": [birds[0]["health"], birds[1]["health"]],
			"round": 0,
			"attack": {},
			"winner": -1,
			"bets": {},
			"seconds": 0
		},
		true
	)
	state = next


func _may_bet(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 3:
		return false
	for field: String in ["side", "stake", "match"]:
		if not payload.get(field) is int:
			return false
	var player := entity.player_for_peer(peer)
	var wallet := _wallet()
	return (
		player != null
		and can_use(player)
		and wallet != null
		and state["phase"] in ["preview", "betting"]
		and (state["phase"] == "preview" or _elapsed < config.betting_seconds)
		and int(payload["match"]) == int(state["match"])
		and not state["bets"].has(peer)
		and int(payload["side"]) in [0, 1]
		and int(payload["stake"]) >= config.min_bet_cents
		and int(payload["stake"]) <= config.max_bet_cents
		and int(wallet.balances.get(peer, 0)) >= int(payload["stake"])
	)


func _bet(peer: int, payload: Dictionary) -> bool:
	var account := _wallet().account_for(peer)
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var ticket := {
		"peer": peer,
		"account": account,
		"id": id,
		"stake": int(payload["stake"]),
		"credit": int(payload["stake"]),
		"side": int(payload["side"])
	}
	# Default credit is a refund until the finished outcome is durable.
	if account > 0 and not _journal.store(id, ticket):
		return false
	ticket["owner"] = weakref(entity.player_for_peer(peer))
	ticket["paid"] = false
	ticket["cancelled"] = false
	ticket["settling"] = false
	_tickets[peer] = ticket
	var next := state.duplicate(true)
	next["bets"][peer] = {
		"side": ticket["side"],
		"stake": ticket["stake"],
		"name": entity.player_for_peer(peer).display_name,
		"result": "Charging…"
	}
	if state["phase"] == "preview":
		next["phase"] = "betting"
		next["seconds"] = ceili(config.betting_seconds)
		_elapsed = 0.0
	state = next
	_debit(peer, ticket)
	return true


func _debit(peer: int, ticket: Dictionary) -> void:
	var generation := _generation
	var result := await _transaction(ticket, -int(ticket["stake"]), str(ticket["id"]), "")
	if generation != _generation:
		return
	if not result.has("balance"):
		_message(peer, "Void — no charge")
		if int(ticket["account"]) > 0:
			_journal.erase(str(ticket["id"]))
		_tickets.erase(peer)
		return
	ticket["paid"] = true
	_message(peer, "Wager deducted")
	if ticket["cancelled"]:
		_settle(peer, ticket, "Refunded")


func _process(delta: float) -> void:
	if not entity.is_authority():
		return
	if not _recovery_started and Network.mode == Network.Mode.SERVER and _wallet() != null:
		_recovery_started = true
		_journal.load_entries()
		for id: String in _journal.entries.keys():
			_recover(_journal.entries[id].duplicate(true))
	_poll += delta
	if _poll >= config.refund_poll_seconds:
		_poll = 0.0
		for peer: int in _tickets.keys():
			var ticket: Dictionary = _tickets[peer]
			var owner: Player = ticket["owner"].get_ref() as Player
			if (
				state["phase"] in ["betting", "fighting"]
				and (
					owner == null
					or entity.player_for_peer(peer) != owner
					or not room.contains(owner.net_position)
				)
			):
				ticket["cancelled"] = true
				if ticket["paid"]:
					_settle(peer, ticket, "Refunded")
	_elapsed += delta
	match str(state["phase"]):
		"betting":
			var next := state.duplicate(true)
			next["seconds"] = maxi(0, ceili(config.betting_seconds - _elapsed))
			state = next
			if _elapsed >= config.betting_seconds and _all_paid():
				_elapsed = 0.0
				_set_phase("fighting" if not _tickets.is_empty() else "result")
		"fighting":
			if _tickets.is_empty():
				_set_phase("result")
				_elapsed = 0.0
			elif _elapsed >= config.round_seconds:
				_elapsed = 0.0
				_round()
		"finishing":
			_finish()
		"result":
			if _elapsed >= config.result_seconds and _tickets.is_empty():
				var next := state.duplicate(true)
				next["phase"] = "idle"
				next["birds"] = []
				state = next


func _may_cancel(peer: int, payload: Dictionary) -> bool:
	return payload.is_empty() and _tickets.has(peer) and state["phase"] in ["betting", "fighting"]


func _cancel(peer: int, _payload: Dictionary) -> bool:
	var ticket: Dictionary = _tickets[peer]
	ticket["cancelled"] = true
	if ticket["paid"]:
		_settle(peer, ticket, "Refunded")
	return true


func _all_paid() -> bool:
	for ticket: Dictionary in _tickets.values():
		if not ticket["paid"] or ticket["cancelled"]:
			return false
	return true


func _round() -> void:
	var result := ChickenFightSimulation.round_result(state["birds"], state["health"], _rng, config)
	var next := state.duplicate(true)
	next["health"] = result["health"]
	next["attack"] = result
	next["round"] = int(state["round"]) + 1
	next["winner"] = result["winner"]
	if int(result["winner"]) >= 0:
		next["phase"] = "finishing"
	state = next
	if int(result["winner"]) >= 0:
		_finish()


func _finish() -> void:
	# Write every final intent before starting any credit operation.
	for peer: int in _tickets:
		var ticket: Dictionary = _tickets[peer]
		if ticket["cancelled"]:
			continue
		ticket["credit"] = (
			ChickenFightSimulation.payout(ticket["stake"], state["odds"][ticket["side"]])
			if int(ticket["side"]) == int(state["winner"])
			else 0
		)
		if int(ticket["account"]) > 0:
			var record := _record(ticket)
			if not _journal.store(str(ticket["id"]), record):
				return
	_set_phase("result")
	_elapsed = 0.0
	for peer: int in _tickets.keys():
		_settle(peer, _tickets[peer], "Won" if int(_tickets[peer]["credit"]) > 0 else "Lost")


func _record(ticket: Dictionary) -> Dictionary:
	var result := ticket.duplicate(true)
	for field: String in ["owner", "paid", "cancelled", "settling"]:
		result.erase(field)
	return result


func _settle(peer: int, ticket: Dictionary, label: String) -> void:
	if ticket["settling"]:
		return
	ticket["settling"] = true
	var generation := _generation
	var credit := int(ticket["credit"])
	var result: Dictionary = {}
	if credit > 0:
		_message(peer, label + " — settling…")
		result = await _transaction(
			ticket, credit, (str(ticket["id"]) + "-return").sha256_text(), "Chicken book: " + label
		)
	if generation != _generation:
		return
	if credit > 0 and not result.has("balance"):
		if int(ticket["account"]) > 0:
			_message(peer, "Settlement needs account recovery; ticket retained")
			return
		_message(peer, "Void — temporary wallet ended")
		_tickets.erase(peer)
		return
	var wallet := _wallet()
	var balance := int(result.get("balance", wallet.balances.get(peer, 0)))
	var message := (
		"%s %s · Balance %s"
		% [label, PlayerMoney.format_money(credit), PlayerMoney.format_money(balance)]
	)
	_message(peer, message)
	var chat := get_tree().get_first_node_in_group(&"chat_box")
	var owner: Player = ticket["owner"].get_ref() as Player
	if chat != null and owner != null and entity.player_for_peer(peer) == owner:
		chat.send_notice(peer, "Chicken book: " + message)
	if int(ticket["account"]) > 0:
		_journal.erase(str(ticket["id"]))
	_tickets.erase(peer)


func _transaction(ticket: Dictionary, delta: int, id: String, reason: String) -> Dictionary:
	var generation := _generation
	var delay := 0.5
	while generation == _generation and is_inside_tree():
		if int(ticket["account"]) == 0 and ticket.has("owner"):
			var owner: Player = ticket["owner"].get_ref() as Player
			if owner == null or entity.player_for_peer(ticket["peer"]) != owner:
				return {"rejected": true}
		var wallet := _wallet()
		if wallet != null:
			var result := await wallet.adjust_account(
				ticket["peer"], ticket["account"], id, delta, reason
			)
			if result.has("balance") or result.has("rejected"):
				return result
		await get_tree().create_timer(delay).timeout
		delay = minf(10.0, delay * 2.0)
	return {"error": "Session changed"}


func _recover(ticket: Dictionary) -> void:
	var generation := _generation
	# Peer 0 cannot accidentally update a newly connected player's HUD.
	ticket["peer"] = 0
	var result := await _transaction(ticket, -int(ticket["stake"]), ticket["id"], "")
	if generation != _generation:
		return
	if result.has("rejected"):
		_journal.erase(ticket["id"])
		return  # Definitive debit refusal: nothing was deducted, so no refund is due.
	if result.has("balance") and int(ticket["credit"]) > 0:
		result = await _transaction(
			ticket,
			int(ticket["credit"]),
			(str(ticket["id"]) + "-return").sha256_text(),
			"Chicken refund"
		)
	if generation == _generation and (result.has("balance") or int(ticket["credit"]) == 0):
		_journal.erase(ticket["id"])


func _message(peer: int, message: String) -> void:
	var next := state.duplicate(true)
	if next["bets"].has(peer):
		next["bets"][peer]["result"] = message
		state = next


func _set_phase(phase: String) -> void:
	var next := state.duplicate(true)
	next["phase"] = phase
	state = next


func _wallet() -> PlayerMoney:
	return get_tree().get_first_node_in_group(&"player_money") as PlayerMoney


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	_tickets.clear()
	_recovery_started = false
	_elapsed = 0.0
	var next := state.duplicate(true)
	next.merge({"phase": "idle", "birds": [], "bets": {}, "attack": {}, "winner": -1}, true)
	state = next
	if is_instance_valid(_menu):
		_menu.close()
