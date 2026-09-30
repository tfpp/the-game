class_name RouletteTable
extends StaticBody3D
## Server-authoritative multiplayer roulette. Up to three players take fixed seats;
## the first one to sit opens a 20-second betting round. Seated players place chips
## on the layout (any mix, up to their balance), then the wheel spins and every bet
## settles in one atomic wallet operation per player. Clients only send requests
## through the NetworkedInteraction component; the replicated `state` is the truth.

const USE_RANGE := 3.5
const SEAT_COUNT := 3
## Default betting window: the first player to sit starts this clock.
const BETTING_S := 20.0
const SPIN_DURATION_S := 3.0
## How long the result stays up before seated players are released.
const RESULT_S := 5.0
## A seated player whose position drifts this far from their seat has left it.
const SEAT_LEAVE_M := 1.2
## Settlement retries back off from SETTLE_RETRY_S to SETTLE_RETRY_MAX_S and never
## give up while the session lasts: the API may already have applied a bet whose
## reply was lost, so the same operation ID is retried until it answers.
const SETTLE_RETRY_S := 0.5
const SETTLE_RETRY_MAX_S := 10.0
## Per-player bet-editing allowance (bet/remove/undo/clear): bursts up to
## EDIT_BURST requests, refilling EDIT_RATE per second. Each accepted edit resends
## the table state to every peer, so sustained spam is refused.
const EDIT_BURST := 10.0
const EDIT_RATE := 8.0
## A standing player this close (horizontally) to a seat is moved aside when
## someone sits there, and how far back from the seat they are moved.
const SEAT_CLEAR_M := 0.7
const SEAT_NUDGE_M := 1.0
const PHASE_IDLE := "idle"
const PHASE_BETTING := "betting"
const PHASE_SPINNING := "spinning"
const PHASE_RESULT := "result"

## Table-local player positions (hull centre) along the players' long side, which
## faces the dealer across the layout. Players face +Z, towards the table.
const SEATS: Array[Vector3] = [
	Vector3(-0.2, 0.9144, -1.1), Vector3(0.65, 0.9144, -1.1), Vector3(1.5, 0.9144, -1.1)
]

## Seconds of betting per round. Every peer loads the same scene value; only the
## server's copy matters.
@export var betting_seconds := BETTING_S
@export var state: Dictionary = initial_state()
## Whole seconds until betting closes; replicated separately so the countdown does
## not resend every bet each second.
@export var net_seconds_left := 0

var _wheel := RouletteWheel.new()
var _result := 0
var _elapsed := 0.0
var _generation := 0
## peer -> {"account": int, "placements": Array}, captured when betting closes.
var _locked: Dictionary = {}
## peer -> true once the player has reached their seat after the teleport.
var _arrived: Dictionary = {}
## peer -> {"tokens": float, "at": float} for the bet-editing allowance.
var _edit_budget: Dictionary = {}
## Server clock (seconds of _process time) for the edit allowance.
var _clock_s := 0.0

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _seat)
	entity.register_action(&"bet", _may_bet, _metered(_bet))
	entity.register_action(&"remove", _may_remove, _metered(_remove))
	entity.register_action(&"undo", _may_edit, _metered(_undo))
	entity.register_action(&"clear", _may_edit, _metered(_clear))
	entity.register_action(&"leave", _may_leave, _leave)
	entity.session_reset.connect(_on_session_reset)
	entity.request_finished.connect(_on_request_finished)
	Network.mode_changed.connect(_on_mode_changed)


static func initial_state() -> Dictionary:
	return {
		"phase": PHASE_IDLE,
		"round": 0,
		"seats": [0, 0, 0],
		"names": ["", "", ""],
		"bets": {},
		"results": {},
		"spin": 0,
		"spinning": false,
		"number": 0,
		"color": "",
		"message": "",
	}


func phase() -> String:
	return str(state["phase"])


## Seat index of `peer`, or -1.
func seat_of(peer: int) -> int:
	return (state["seats"] as Array).find(peer)


func placements_for(peer: int) -> Array:
	return (state["bets"] as Dictionary).get(peer, [])


func interaction_text() -> String:
	var free := (state["seats"] as Array).count(0)
	if phase() == PHASE_BETTING:
		return (
			"Join roulette — %d/%d seats, bets close in %ds"
			% [SEAT_COUNT - free, SEAT_COUNT, net_seconds_left]
		)
	return "Play roulette"


func interaction_point() -> Vector3:
	return to_global(Vector3(0, 0.9, 0))


func seat_position(seat: int) -> Vector3:
	return to_global(SEATS[seat])


## Global yaw that faces a seated player towards the table.
func seat_yaw() -> float:
	return global_rotation.y + PI


func can_use(player: Player) -> bool:
	if phase() != PHASE_IDLE and phase() != PHASE_BETTING:
		return false
	var seats := state["seats"] as Array
	if not seats.has(0) or seats.has(player.get_multiplayer_authority()):
		return false
	var eye := (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5)
	)
	var center := interaction_point()
	var offset := center - eye
	if offset.length() > USE_RANGE or offset.length() < 0.05:
		return false
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	if look.dot(offset.normalized()) < 0.6:
		return false
	# Seated players must not block others from joining, so only geometry counts.
	var ignore: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node is CollisionObject3D:
			ignore.append((node as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(eye, center, 1, ignore)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == self


func use() -> void:
	entity.request_use()


## Client helpers: all validation happens again on the server.
func request_bet(spot: String, cents: int) -> void:
	entity.request_action(&"bet", {"spot": spot, "cents": cents})


func request_remove(spot: String) -> void:
	entity.request_action(&"remove", {"spot": spot})


func request_undo() -> void:
	entity.request_action(&"undo")


func request_clear() -> void:
	entity.request_action(&"clear")


func request_leave() -> void:
	entity.request_action(&"leave")


## Whether `peer` may stand up now: any time before the wheel spins, or during the
## spin when they have nothing riding on it.
func may_leave(peer: int) -> bool:
	if seat_of(peer) < 0:
		return false
	return phase() != PHASE_SPINNING or not _locked.has(peer)


func _process(delta: float) -> void:
	_clock_s += delta
	if not entity.is_authority():
		return
	_watch_seats()
	if phase() == PHASE_IDLE:
		return
	_elapsed += delta
	match phase():
		PHASE_BETTING:
			var left := maxi(0, ceili(betting_seconds - _elapsed))
			if left != net_seconds_left:
				net_seconds_left = left
			if _elapsed >= betting_seconds:
				_close_betting()
		PHASE_SPINNING:
			if _elapsed >= SPIN_DURATION_S:
				_finish_spin()
		PHASE_RESULT:
			if _elapsed >= RESULT_S:
				_end_round()


func _seat(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var seats := state["seats"] as Array
	var seat := seats.find(0)
	if seat < 0 or seats.has(peer):
		return false
	var next := state.duplicate(true)
	if phase() == PHASE_IDLE:
		next = _open_round(next)
	next["seats"][seat] = peer
	next["names"][seat] = player.display_name if player.display_name else "Player %d" % peer
	state = next
	_arrived.erase(peer)
	_clear_seat(seat, player)
	_teleport(player, seat)
	return true


## Moves any standing (unseated) player off `seat` so the new occupant doesn't land
## inside them. Movement is client-owned, so the server asks their peer to move.
## Returns peer -> target position for everyone asked to move.
func _clear_seat(seat: int, sitter: Player) -> Dictionary:
	var moved := {}
	var spot := seat_position(seat)
	var away := -global_basis.z.normalized()
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as Player
		if other == null or other == sitter:
			continue
		var peer := other.get_multiplayer_authority()
		if seat_of(peer) >= 0:
			continue
		var offset := other.net_position - spot
		offset.y = 0.0
		if offset.length() >= SEAT_CLEAR_M:
			continue
		var target := spot + away * SEAT_NUDGE_M
		target.y = other.net_position.y
		moved[peer] = target
		if peer == multiplayer.get_unique_id() or multiplayer.get_peers().has(peer):
			other.server_teleport.rpc_id(peer, target)
	return moved


func _open_round(from: Dictionary) -> Dictionary:
	var next := from.duplicate(true)
	next["phase"] = PHASE_BETTING
	next["round"] = int(from["round"]) + 1
	next["bets"] = {}
	next["results"] = {}
	next["message"] = ""
	_elapsed = 0.0
	_locked.clear()
	net_seconds_left = ceili(betting_seconds)
	return next


func _teleport(player: Player, seat: int) -> void:
	var peer := player.get_multiplayer_authority()
	if peer == multiplayer.get_unique_id() or multiplayer.get_peers().has(peer):
		player.server_teleport.rpc_id(peer, seat_position(seat), seat_yaw())


func _may_bet(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 2 or not payload.get("spot") is String or not payload.get("cents") is int:
		return false
	var spot := str(payload["spot"])
	var cents := int(payload["cents"])
	if phase() != PHASE_BETTING or seat_of(peer) < 0 or not RouletteBets.is_valid(spot):
		return false
	if not RouletteBets.DENOMINATIONS.has(cents):
		return false
	var placements := placements_for(peer)
	if placements.size() >= RouletteBets.MAX_PLACEMENTS or not _has_edit_budget(peer):
		return false
	return RouletteBets.total(placements) + cents <= _balance(peer)


func _bet(peer: int, payload: Dictionary) -> bool:
	var next := state.duplicate(true)
	var placements: Array = (next["bets"] as Dictionary).get(peer, [])
	placements.append([str(payload["spot"]), int(payload["cents"])])
	next["bets"][peer] = placements
	state = next
	return true


func _may_remove(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 1 or not payload.get("spot") is String:
		return false
	return _may_edit(peer, {}) and RouletteBets.by_spot(placements_for(peer)).has(payload["spot"])


func _remove(peer: int, payload: Dictionary) -> bool:
	var kept := placements_for(peer).filter(
		func(placement: Array) -> bool: return placement[0] != payload["spot"]
	)
	_set_placements(peer, kept)
	return true


func _has_bets(peer: int, payload: Dictionary) -> bool:
	return payload.is_empty() and phase() == PHASE_BETTING and not placements_for(peer).is_empty()


func _may_edit(peer: int, payload: Dictionary) -> bool:
	return _has_bets(peer, payload) and _has_edit_budget(peer)


## True if `peer` may make another bet edit now. Read-only; `_metered` spends it.
func _has_edit_budget(peer: int) -> bool:
	return _edit_tokens(peer) >= 1.0


func _edit_tokens(peer: int) -> float:
	var budget: Dictionary = _edit_budget.get(peer, {})
	if budget.is_empty():
		return EDIT_BURST
	var seconds := _clock_s - float(budget["at"])
	return minf(EDIT_BURST, float(budget["tokens"]) + seconds * EDIT_RATE)


## Wraps an apply callback so each accepted edit spends one unit of the allowance.
func _metered(apply: Callable) -> Callable:
	return func(peer: int, payload: Dictionary) -> bool:
		if not apply.call(peer, payload):
			return false
		_edit_budget[peer] = {"tokens": _edit_tokens(peer) - 1.0, "at": _clock_s}
		return true


func _undo(peer: int, _payload: Dictionary) -> bool:
	var placements := placements_for(peer).duplicate(true)
	placements.pop_back()
	_set_placements(peer, placements)
	return true


func _clear(peer: int, _payload: Dictionary) -> bool:
	_set_placements(peer, [])
	return true


func _set_placements(peer: int, placements: Array) -> void:
	var next := state.duplicate(true)
	if placements.is_empty():
		(next["bets"] as Dictionary).erase(peer)
	else:
		next["bets"][peer] = placements
	state = next


func _may_leave(peer: int, payload: Dictionary) -> bool:
	return payload.is_empty() and may_leave(peer)


func _leave(peer: int, _payload: Dictionary) -> bool:
	_unseat(peer)
	return true


## Frees `peer`'s seat. Unplaced (betting-phase) chips go back; locked bets still settle.
func _unseat(peer: int) -> void:
	var seat := seat_of(peer)
	if seat < 0:
		return
	var next := state.duplicate(true)
	next["seats"][seat] = 0
	next["names"][seat] = ""
	if phase() == PHASE_BETTING:
		(next["bets"] as Dictionary).erase(peer)
	_arrived.erase(peer)
	state = next
	if (
		phase() == PHASE_BETTING
		and not (state["seats"] as Array).any(func(p: int) -> bool: return p != 0)
	):
		_end_round()


## Seated players who disconnect or end up away from their seat (respawn, elevator,
## a client ignoring the lock) lose the seat.
func _watch_seats() -> void:
	for seat: int in SEAT_COUNT:
		var peer := int(state["seats"][seat])
		if peer == 0:
			continue
		var player := entity.player_for_peer(peer)
		if player == null:
			_unseat(peer)
			continue
		var offset := player.net_position - seat_position(seat)
		offset.y = 0.0
		if offset.length() < SEAT_LEAVE_M * 0.5:
			_arrived[peer] = true
		elif _arrived.has(peer) and offset.length() > SEAT_LEAVE_M:
			_unseat(peer)


func _close_betting() -> void:
	var bets := state["bets"] as Dictionary
	if bets.is_empty():
		var closed := state.duplicate(true)
		closed["message"] = "No bets placed"
		state = closed
		_end_round()
		return
	var wallet := _wallet()
	_locked.clear()
	var trimmed := state.duplicate(true)
	for peer: int in bets:
		var kept := affordable(bets[peer], _balance(peer))
		var returned := RouletteBets.total(bets[peer]) - RouletteBets.total(kept)
		if returned > 0:
			_notify(
				peer,
				(
					"Roulette: %s of chips returned, your balance no longer covers them"
					% PlayerMoney.format_money(returned)
				)
			)
		if kept.is_empty():
			(trimmed["bets"] as Dictionary).erase(peer)
			continue
		trimmed["bets"][peer] = kept
		_locked[peer] = {
			"account": wallet.account_for(peer) if wallet != null else 0,
			"placements": kept.duplicate(true),
		}
	state = trimmed
	if _locked.is_empty():
		var closed := state.duplicate(true)
		closed["message"] = "No bets placed"
		state = closed
		_end_round()
		return
	_result = _wheel.next_result()
	_elapsed = 0.0
	net_seconds_left = 0
	var next := state.duplicate(true)
	next["phase"] = PHASE_SPINNING
	next["spin"] = int(state["spin"]) + 1
	next["spinning"] = true
	next["number"] = 0
	next["color"] = ""
	state = next


func _finish_spin() -> void:
	_elapsed = 0.0
	var next := state.duplicate(true)
	next["phase"] = PHASE_RESULT
	next["spinning"] = false
	next["number"] = _result
	next["color"] = RouletteWheel.color_for(_result)
	var results := {}
	for peer: int in _locked:
		var totals := RouletteBets.settle(_locked[peer]["placements"], _result)
		totals["status"] = "settling"
		results[peer] = totals
	next["results"] = results
	state = next
	for peer: int in _locked:
		_settle(peer, _locked[peer], int(state["round"]), _result)
	_locked.clear()


func _settle(peer: int, locked: Dictionary, round_id: int, number: int) -> void:
	var generation := _generation
	var wallet := _wallet()
	var totals := RouletteBets.settle(locked["placements"], number)
	var wager := int(totals["wager"])
	var payout := int(totals["payout"])
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var result := {"error": "Wallet unavailable"}
	var delay := SETTLE_RETRY_S
	while wallet != null and is_instance_valid(wallet):
		result = await wallet.settle_roulette(peer, int(locked["account"]), id, wager, payout)
		if generation != _generation or not is_inside_tree():
			return
		if result.has("balance") or result.has("rejected"):
			break
		# No answer (API down, reply lost, wallet busy): the bet may already be applied,
		# so keep retrying the same ID rather than calling it void.
		await get_tree().create_timer(delay).timeout
		if generation != _generation or not is_inside_tree():
			return
		delay = minf(delay * 2.0, SETTLE_RETRY_MAX_S)
	var status := "void"
	if result.has("balance"):
		status = "won" if payout > 0 else "lost"
	if int(state["round"]) == round_id and (state["results"] as Dictionary).has(peer):
		var next := state.duplicate(true)
		next["results"][peer]["status"] = status
		state = next
	var pocket := "%s %s" % [RouletteWheel.label_for(number), RouletteWheel.color_for(number)]
	if status == "void":
		_notify(
			peer, "Roulette bet void (%s): %s" % [PlayerMoney.format_money(wager), result["error"]]
		)
	elif payout > wager and is_instance_valid(wallet):
		wallet.announce_gain(peer, payout - wager, "Roulette win on %s" % pocket)
	elif payout < wager:
		_notify(peer, "-%s: Roulette on %s" % [PlayerMoney.format_money(wager - payout), pocket])


func _end_round() -> void:
	_elapsed = 0.0
	_locked.clear()
	_arrived.clear()
	_edit_budget.clear()
	net_seconds_left = 0
	var next := state.duplicate(true)
	next["phase"] = PHASE_IDLE
	next["seats"] = [0, 0, 0]
	next["names"] = ["", "", ""]
	next["bets"] = {}
	state = next


## The oldest placements whose total fits in `balance`; later chips that no longer
## fit are dropped rather than voiding the whole bet at settlement.
static func affordable(placements: Array, balance: int) -> Array:
	var kept: Array = []
	var total := 0
	for placement: Array in placements:
		if total + int(placement[1]) > balance:
			break
		total += int(placement[1])
		kept.append(placement.duplicate())
	return kept


## Client side: explain a refused request to sit (the server has already decided).
func _on_request_finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if action != &"use" or result == NetworkedEntity.Result.ACCEPTED:
		return
	var text := "You can't join the roulette table from here"
	if phase() == PHASE_SPINNING or phase() == PHASE_RESULT:
		text = "Roulette: wait for the next round"
	elif not (state["seats"] as Array).has(0):
		text = "Roulette table is full"
	var chat := get_tree().get_first_node_in_group(&"chat_box")
	if chat != null:
		chat.receive_notice(text)


func _balance(peer: int) -> int:
	var wallet := _wallet()
	return int(wallet.balances.get(peer, 0)) if wallet != null else 0


func _wallet() -> PlayerMoney:
	return get_tree().get_first_node_in_group(&"player_money") as PlayerMoney


func _notify(peer: int, text: String) -> void:
	var chat := get_tree().get_first_node_in_group(&"chat_box")
	if chat != null:
		chat.send_notice(peer, text)


func _on_session_reset(_mode: Network.Mode) -> void:
	_reset()


func _on_mode_changed(_mode: Network.Mode) -> void:
	# Do not carry local/offline rounds into a newly joined server, or vice versa.
	_reset()


func _reset() -> void:
	_generation += 1
	state = initial_state()
	net_seconds_left = 0
	_wheel = RouletteWheel.new()
	_result = 0
	_elapsed = 0.0
	_locked.clear()
	_arrived.clear()
	_edit_budget.clear()
