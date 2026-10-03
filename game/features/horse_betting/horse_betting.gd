class_name HorseBetting
extends StaticBody3D
## One shared server-owned race; wallet settlements use the existing atomic wager API.

const HORSES: Array[String] = ["Crown Jewel", "Rusty Rocket", "Velvet Thunder", "Last Orders"]
const STAKES: Array[int] = [100, 500, 1000]
const BETTING_SECONDS := 15.0
const RACE_SECONDS := 12.0
const RESULT_SECONDS := 8.0

@export var state: Dictionary = initial_state()
@export var seconds_left := 0
@export var progress: Array[float] = [0.0, 0.0, 0.0, 0.0]

var _elapsed := 0.0
var _update := 0.0
var _generation := 0
var _durations: Array[float] = []
var _locked: Dictionary = {}
var _menu: HorseBettingMenu

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _open_menu)
	entity.register_action(&"bet", _may_bet, _bet)
	entity.event_received.connect(_event)
	entity.request_finished.connect(_request_finished)
	Network.mode_changed.connect(_reset)


static func initial_state() -> Dictionary:
	return {"phase": "idle", "round": 0, "bets": {}, "winner": -1, "results": {}}


func interaction_point() -> Vector3:
	return to_global(Vector3(0, 1.35, 0.95))


## Idle forms target the upcoming round, so simultaneous first tickets agree.
func ticket_round() -> int:
	return int(state["round"]) + (1 if state["phase"] == "idle" else 0)


func interaction_text() -> String:
	return "Horse betting — tickets & race results"


func can_use(player: Player) -> bool:
	if not entity.in_range(player):
		return false
	var eye := player.net_position + Vector3.UP * 0.5
	var offset := interaction_point() - eye
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	if offset.length() < 0.01 or look.dot(offset.normalized()) < 0.5:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, interaction_point(), 1, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") == self


func use() -> void:
	entity.request_use()


func _open_menu(player: Player) -> bool:
	entity.send_event(&"menu", {}, player.get_multiplayer_authority())
	return true


func _event(event: StringName, _payload: Dictionary) -> void:
	if event != &"menu" or is_instance_valid(_menu):
		return
	_menu = HorseBettingMenu.new()
	_menu.race = self
	add_child(_menu)


func _request_finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if action == &"bet" and is_instance_valid(_menu):
		_menu.feedback = (
			"Ticket accepted. Watch the big display!"
			if result == NetworkedEntity.Result.ACCEPTED
			else "Ticket refused: check balance, distance or race status."
		)


func _may_bet(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 3 or not payload.get("horse") is int:
		return false
	if not payload.get("stake") is int or not payload.get("round") is int:
		return false
	var player := entity.player_for_peer(peer)
	var wallet := _wallet()
	return (
		player != null
		and can_use(player)
		and wallet != null
		and state["phase"] in ["idle", "betting"]
		and int(payload["round"]) == ticket_round()
		and (state["phase"] == "idle" or not state["bets"].has(peer))
		and int(payload["horse"]) >= 0
		and int(payload["horse"]) < HORSES.size()
		and int(payload["stake"]) in STAKES
		and int(wallet.balances.get(peer, 0)) >= int(payload["stake"])
	)


func _bet(peer: int, payload: Dictionary) -> bool:
	var next := state.duplicate(true)
	if state["phase"] == "idle":
		next = initial_state()
		next["round"] = int(state["round"]) + 1
		next["phase"] = "betting"
		_elapsed = 0.0
		seconds_left = 15
		progress = [0.0, 0.0, 0.0, 0.0]
	var player := entity.player_for_peer(peer)
	next["bets"][peer] = {
		"horse": payload["horse"], "stake": payload["stake"], "name": player.display_name
	}
	state = next
	return true


func _process(delta: float) -> void:
	if not entity.is_authority():
		return
	if state["phase"] == "betting":
		_prune_disconnected()
	_elapsed += delta
	match str(state["phase"]):
		"betting":
			seconds_left = maxi(0, ceili(BETTING_SECONDS - _elapsed))
			if _elapsed >= BETTING_SECONDS:
				_start_race()
		"racing":
			_update += delta
			if _update >= 0.1:
				_update = 0.0
				progress = race_progress(_elapsed, _durations)
			if _elapsed >= RACE_SECONDS:
				_finish_race()
		"result":
			if _elapsed >= RESULT_SECONDS and _locked.is_empty():
				var next := state.duplicate(true)
				next["phase"] = "idle"
				state = next


static func race_progress(elapsed: float, durations: Array[float]) -> Array[float]:
	var positions: Array[float] = []
	for horse: int in durations.size():
		var time := clampf(elapsed / durations[horse], 0.0, 1.0)
		# Different surges preserve monotonic motion and the sampled finish order.
		positions.append(clampf(time + 0.06 * sin(time * TAU + horse) * sin(time * PI), 0, 1))
	return positions


func _prune_disconnected() -> void:
	var next := state.duplicate(true)
	for peer: int in next["bets"]:
		if entity.player_for_peer(peer) == null:
			next["bets"].erase(peer)
	if next != state:
		state = next


func _start_race() -> void:
	_elapsed = 0.0
	seconds_left = 0
	_locked.clear()
	var wallet := _wallet()
	for peer: int in state["bets"]:
		var ticket: Dictionary = state["bets"][peer].duplicate(true)
		ticket["account"] = wallet.account_for(peer) if wallet != null else 0
		ticket["player"] = entity.player_for_peer(peer)
		ticket["id"] = Crypto.new().generate_random_bytes(32).hex_encode()
		_locked[peer] = ticket
	_durations.clear()
	for horse: int in HORSES.size():
		_durations.append(randf_range(8.0, 11.9) + horse * 0.00001)
	var next := state.duplicate(true)
	next["phase"] = "racing"
	state = next


func _finish_race() -> void:
	_elapsed = 0.0
	var winner := _durations.find(_durations.min())
	var next := state.duplicate(true)
	next["phase"] = "result"
	next["winner"] = winner
	for peer: int in _locked:
		next["results"][peer] = "Settling…"
	state = next
	for peer: int in _locked.keys():
		_settle(peer, _locked[peer], winner)


func _settle(peer: int, ticket: Dictionary, winner: int) -> void:
	var generation := _generation
	var wallet := _wallet()
	var stake := int(ticket["stake"])
	var payout := stake * 4 if int(ticket["horse"]) == winner else 0
	var result := {"error": "Wallet unavailable", "rejected": true}
	var delay := 0.5
	while is_instance_valid(wallet):
		# Temporary wallets cannot settle into a replacement player using the same peer.
		if int(ticket["account"]) == 0 and not is_instance_valid(ticket["player"]):
			break
		result = await wallet.settle_roulette(peer, ticket["account"], ticket["id"], stake, payout)
		if generation != _generation or not is_inside_tree():
			return
		if result.has("balance") or result.has("rejected"):
			break
		await get_tree().create_timer(delay).timeout
		if generation != _generation or not is_inside_tree():
			return
		delay = minf(delay * 2, 10.0)
	var message := "Void — wallet could not cover ticket"
	if result.has("balance"):
		message = "Won %s" % PlayerMoney.format_money(payout) if payout else "Lost ticket"
		if payout > stake:
			wallet.announce_gain(peer, payout - stake, "Horse race: " + HORSES[winner])
	var next := state.duplicate(true)
	next["results"][peer] = message
	state = next
	_locked.erase(peer)


func _wallet() -> PlayerMoney:
	return get_tree().get_first_node_in_group(&"player_money") as PlayerMoney


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	state = initial_state()
	progress = [0.0, 0.0, 0.0, 0.0]
	seconds_left = 0
	_elapsed = 0.0
	_locked.clear()
	_durations.clear()
	if is_instance_valid(_menu):
		_menu.close()
