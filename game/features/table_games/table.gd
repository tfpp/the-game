class_name CrownGameTable
extends StaticBody3D
## Persistent endpoints exist on every peer; only the server owns decks and decisions.

const SCREEN := preload("res://features/table_games/screen.gd")
@export_enum("blackjack", "poker", "baccarat", "craps", "video_poker") var game := "blackjack"
@export var state: Dictionary = {
	"phase": "idle",
	"players": {},
	"board": [],
	"dealer": [],
	"turn": 0,
	"message": "",
	"point": 0,
	"dice": [],
	"seconds": 0
}
@export var betting_seconds := 12.0
@export var turn_seconds := 25.0
var private_hand: Array = []
var _hands: Dictionary = {}
var _decks: Array[int] = []
var _dealer: Array[int] = []
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _street := 0
var _acted: Dictionary = {}
var _street_bets: Dictionary = {}
var _target := 0
var _raised := false
var _generation := 0
var _screen: CanvasLayer
var _dealer_serial := 0
var _dealer_tick := 0.0
@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"crown_game_tables")
	var model := get_node_or_null("Model") as MeshInstance3D
	if model != null:
		var bounds := model.mesh.get_aabb()
		var shape := BoxShape3D.new()
		shape.size = bounds.size
		($Collider as CollisionShape3D).shape = shape
		($Collider as CollisionShape3D).position = bounds.get_center()
	_rng.randomize()
	entity.register_use(can_use, _join, 0.2)
	entity.register_action(&"move", _may_move, _move, 0.15)
	entity.register_action(&"leave", _may_leave, _leave, 0.15)
	entity.event_received.connect(_event)
	entity.session_reset.connect(_reset)
	Network.mode_changed.connect(_reset)


func interaction_point() -> Vector3:
	return to_global(Vector3(0, 1, 0))


func interaction_text() -> String:
	return (
		"Play %s · $1 stake%s"
		% [game.replace("_", " ").capitalize(), " / reserve $5" if game == "poker" else ""]
	)


func can_use(player: Player) -> bool:
	if not entity.in_range(player):
		return false
	var eye := player.net_position + Vector3.UP * .5
	var offset := interaction_point() - eye
	if offset.length() < .01:
		return false
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	if look.dot(offset.normalized()) < .5:
		return false
	var ignore: Array[RID] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node is CollisionObject3D:
			ignore.append((node as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(eye, interaction_point(), 1, ignore)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == self


func use() -> void:
	entity.request_use()
	open_screen()


func open_screen() -> void:
	if is_instance_valid(_screen) or not get_tree().get_nodes_in_group(&"modal_ui").is_empty():
		return
	_screen = SCREEN.new()
	_screen.set("table", self)
	add_child(_screen)


func _join(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	if state["players"].has(peer):
		_send_hand(peer)
		return true
	if not ["idle", "betting"].has(state["phase"]):
		return false
	if state["players"].size() >= (1 if game == "video_poker" else 4):
		return false
	var wallet := _wallet()
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	if wallet == null or not wallet.reserve_table(peer, id, 500 if game == "poker" else 100):
		return false
	var next := state.duplicate(true)
	next["players"][peer] = {
		"name": player.display_name,
		"id": id,
		"account": wallet.account_for(peer),
		"stake": 100,
		"choice": "player",
		"done": false,
		"folded": false,
		"payout": 0,
		"status": "Playing"
	}
	if state["phase"] == "idle":
		next["phase"] = "betting"
		next["message"] = "Join now — $1 per hand"
		next["board"] = []
		next["dealer"] = []
		next["point"] = 0
		next["dice"] = []
		_clock = betting_seconds
	state = next
	if state["players"].size() == 1:
		_animate_dealer(["greet"])
	return true


# gdlint: disable=max-returns
func moves(peer: int) -> Array[String]:
	if not state["players"].has(peer):
		return []
	if state["phase"] == "betting" and game == "baccarat":
		return ["player", "banker", "tie"]
	if state["phase"] != "playing" or int(state["turn"]) != peer:
		return []
	match game:
		"blackjack":
			return ["hit", "stand"]
		"poker":
			var options: Array[String] = [
				"call" if int(_public_bet(peer)) < int(state.get("target", 0)) else "check", "fold"
			]
			if not bool(state.get("raised", false)):
				options.append("bet" if int(state.get("target", 0)) == 0 else "raise")
			return options
		"craps":
			return ["roll"]
		"video_poker":
			return ["draw"]
	return []


func _public_bet(peer: int) -> int:
	return int((state.get("street_bets", {}) as Dictionary).get(peer, 0))


func _may_move(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 2 or not payload.get("move") is String or not payload.get("hold") is int:
		return false
	var player := entity.player_for_peer(peer)
	if player == null or not entity.in_range(player) or not moves(peer).has(payload["move"]):
		return false
	var mask := int(payload["hold"])
	return mask >= 0 and mask < 32 and (game == "video_poker" or mask == 0)


func _move(peer: int, payload: Dictionary) -> bool:
	var action := str(payload["move"])
	var next := state.duplicate(true)
	if state["phase"] == "betting":
		next["players"][peer]["choice"] = action
		state = next
		return true
	match game:
		"blackjack":
			if action == "hit":
				(_hands[peer] as Array).append(_decks.pop_back())
				_animate_dealer(["deal"])
				next["dealer_animation"] = state["dealer_animation"].duplicate(true)
				next["players"][peer]["cards"] = _hands[peer].duplicate()
			if action == "stand" or CasinoCards.blackjack(_hands[peer]) >= 21:
				next["players"][peer]["done"] = true
			state = next
			_next_turn()
		"poker":
			_poker_move(peer, action)
		"craps":
			_roll()
		"video_poker":
			for i: int in 5:
				if int(payload["hold"]) & (1 << i) == 0:
					_hands[peer][i] = _decks.pop_back()
			next["players"][peer]["cards"] = _hands[peer].duplicate()
			next["players"][peer]["payout"] = CasinoCards.video_payout(_hands[peer]) * 100
			next["message"] = CasinoCards.hand_name(CasinoCards.five(_hands[peer]))
			state = next
			_finish()
	return true


func _may_leave(peer: int, payload: Dictionary) -> bool:
	return payload.is_empty() and state["players"].has(peer) and state["phase"] == "betting"


func _leave(peer: int, _payload: Dictionary) -> bool:
	var entry: Dictionary = state["players"][peer]
	_wallet().release_table(peer, str(entry["id"]))
	var next := state.duplicate(true)
	next["players"].erase(peer)
	if next["players"].is_empty():
		next["phase"] = "idle"
	state = next
	return true


func _process(delta: float) -> void:
	_update_dealer_clock(delta)
	if not entity.is_authority() or state["phase"] == "idle":
		return
	_clock -= delta
	var seconds := maxi(0, ceili(_clock))
	if int(state["seconds"]) != seconds:
		var next := state.duplicate(true)
		next["seconds"] = seconds
		state = next
	if state["phase"] == "betting":
		for peer: int in state["players"].keys():
			var player := entity.player_for_peer(peer)
			if player == null or not entity.in_range(player):
				_leave(peer, {})
		if _clock <= 0 and state["phase"] == "betting":
			_start()
	elif state["phase"] == "playing":
		var peer := int(state["turn"])
		var player := entity.player_for_peer(peer)
		if _clock <= 0 or player == null or not entity.in_range(player):
			var action := (
				"stand"
				if game == "blackjack"
				else ("fold" if game == "poker" else ("roll" if game == "craps" else "draw"))
			)
			_move(peer, {"move": action, "hold": 0})
	elif state["phase"] == "result" and _clock <= 0:
		var next := state.duplicate(true)
		next["phase"] = "idle"
		next["players"] = {}
		state = next
		_hands.clear()
		private_hand.clear()


func _start() -> void:
	if game == "craps":
		_animate_dealer(["greet"])
	else:
		_animate_dealer(["shuffle", "deal", "deal"])
	if game == "poker" and state["players"].size() < 2:
		for peer: int in state["players"].keys():
			_leave(peer, {})
		return
	_decks = CasinoCards.deck(_rng)
	_hands.clear()
	_dealer = [_decks.pop_back(), _decks.pop_back()]
	var next := state.duplicate(true)
	next["phase"] = "playing"
	next["message"] = ""
	for peer: int in next["players"]:
		var cards: Array[int] = []
		for i: int in 5 if game == "video_poker" else 2:
			cards.append(_decks.pop_back())
		_hands[peer] = cards
		if game == "blackjack":
			next["players"][peer]["cards"] = cards.duplicate()
			next["players"][peer]["done"] = CasinoCards.blackjack(cards) == 21
	if game == "blackjack":
		next["dealer"] = [_dealer[0]]
	if game == "poker":
		_street = 0
		_acted.clear()
		_street_bets.clear()
		_target = 0
		_raised = false
		next["target"] = 0
		next["raised"] = false
		next["street_bets"] = {}
	state = next
	for peer: int in _hands:
		_send_hand(peer)
	if game == "baccarat":
		_baccarat()
	elif game == "blackjack" and CasinoCards.blackjack(_dealer) == 21:
		_blackjack_finish()
	else:
		_next_turn()


func _next_turn() -> void:
	var next := state.duplicate(true)
	var selected := 0
	for peer: int in next["players"]:
		var entry: Dictionary = next["players"][peer]
		if not bool(entry["done"]) and not bool(entry["folded"]):
			selected = peer
			break
	next["turn"] = selected
	_clock = turn_seconds
	state = next
	if selected == 0:
		if game == "blackjack":
			_blackjack_finish()
		elif game == "poker":
			_poker_advance()


func _blackjack_finish() -> void:
	_animate_dealer(["reveal"])
	while CasinoCards.blackjack(_dealer) < 17:
		_dealer.append(_decks.pop_back())
	var next := state.duplicate(true)
	next["dealer"] = _dealer.duplicate()
	next["message"] = "Dealer stands on all 17s · blackjack pays 3:2"
	for peer: int in next["players"]:
		next["players"][peer]["payout"] = CasinoRules.blackjack_payout(_hands[peer], _dealer, 100)
	state = next
	_finish()


func _baccarat() -> void:
	_animate_dealer(["reveal"])
	var deal := CasinoRules.baccarat_deal(_decks)
	var next := state.duplicate(true)
	next["board"] = deal["player"]
	next["dealer"] = deal["banker"]
	next["message"] = (
		"Player %d / Banker %d"
		% [CasinoCards.baccarat(deal["player"]), CasinoCards.baccarat(deal["banker"])]
	)
	for peer: int in next["players"]:
		next["players"][peer]["payout"] = CasinoRules.baccarat_payout(
			str(next["players"][peer]["choice"]), deal["player"], deal["banker"], 100
		)
	state = next
	_finish()


func _roll() -> void:
	_animate_dealer(["roll"])
	var dice: Array[int] = [_rng.randi_range(1, 6), _rng.randi_range(1, 6)]
	var total := dice[0] + dice[1]
	var outcome := CasinoRules.craps_outcome(total, int(state["point"]))
	var next := state.duplicate(true)
	next["dice"] = dice
	if outcome == 0:
		if int(next["point"]) == 0:
			next["point"] = total
		next["message"] = "Point %d · roll the point before seven" % int(next["point"])
		state = next
		_clock = turn_seconds
		return
	next["message"] = "Pass line wins" if outcome == 1 else "Pass line loses"
	for peer: int in next["players"]:
		next["players"][peer]["payout"] = 200 if outcome == 1 else 0
	state = next
	_finish()


## Fixed limit: $1 ante, $0.50 bets, one raise per street. Max exposure $5.
func _poker_move(peer: int, action: String) -> void:
	var next := state.duplicate(true)
	if action == "fold":
		next["players"][peer]["folded"] = true
	else:
		if action == "bet" or action == "raise":
			_target += 50
			_raised = action == "raise"
			_acted.clear()
		var before := int(_street_bets.get(peer, 0))
		next["players"][peer]["stake"] = int(next["players"][peer]["stake"]) + _target - before
		_street_bets[peer] = _target
	_acted[peer] = true
	next["target"] = _target
	next["raised"] = _raised
	next["street_bets"] = _street_bets.duplicate()
	for other: int in next["players"]:
		next["players"][other]["done"] = _acted.has(other)
	state = next
	var active := 0
	for entry: Dictionary in state["players"].values():
		active += 0 if bool(entry["folded"]) else 1
	if active <= 1:
		_poker_showdown()
	else:
		_next_turn()


func _poker_advance() -> void:
	_animate_dealer(["deal"])
	if _street == 3:
		_poker_showdown()
		return
	_street += 1
	_acted.clear()
	_street_bets.clear()
	_target = 0
	_raised = false
	var next := state.duplicate(true)
	for i: int in 3 if _street == 1 else 1:
		next["board"].append(_decks.pop_back())
	for entry: Dictionary in next["players"].values():
		entry["done"] = false
	next["target"] = 0
	next["raised"] = false
	next["street_bets"] = {}
	state = next
	_next_turn()


func _poker_showdown() -> void:
	_animate_dealer(["reveal"])
	var next := state.duplicate(true)
	var best := -1
	var winners: Array[int] = []
	var pot := 0
	for peer: int in next["players"]:
		pot += int(next["players"][peer]["stake"])
		if bool(next["players"][peer]["folded"]):
			continue
		var cards: Array = _hands[peer].duplicate()
		cards.append_array(next["board"])
		var score := CasinoCards.best(cards) if cards.size() >= 5 else 0
		next["players"][peer]["cards"] = _hands[peer].duplicate()
		if score > best:
			best = score
			winners = [peer]
		elif score == best:
			winners.append(peer)
	if winners.is_empty():
		# Everybody disconnected/folded: return their stakes without creating money.
		for entry: Dictionary in next["players"].values():
			entry["payout"] = entry["stake"]
	else:
		for i: int in winners.size():
			next["players"][winners[i]]["payout"] = (
				pot / winners.size() + (1 if i < pot % winners.size() else 0)
			)
	next["message"] = (
		"Pot %s · %s" % [PlayerMoney.format_money(pot), CasinoCards.hand_name(maxi(0, best))]
	)
	next["winners"] = winners
	state = next
	_finish()


func _finish() -> void:
	var next := state.duplicate(true)
	next["phase"] = "settling"
	next["turn"] = 0
	state = next
	_settle_round()


func _settle_round() -> void:
	var generation := _generation
	# Debits settle before winner credits for a poker pot.
	var peers: Array = state["players"].keys()
	peers.sort_custom(
		func(a: int, b: int) -> bool:
			return int(state["players"][a]["payout"]) < int(state["players"][b]["payout"])
	)
	for peer: int in peers:
		var entry: Dictionary = state["players"][peer].duplicate(true)
		var delay := .5
		while generation == _generation and is_inside_tree():
			var result := await _wallet().settle_table(
				peer,
				int(entry["account"]),
				str(entry["id"]),
				int(entry["stake"]),
				int(entry["payout"])
			)
			if generation != _generation:
				return
			if result.has("balance") or result.has("rejected"):
				var next := state.duplicate(true)
				if result.has("rejected"):
					_wallet().release_table(peer, str(entry["id"]))
					if game == "poker" and int(entry["payout"]) == 0:
						_remove_void_stake(next, int(entry["stake"]))
				next["players"][peer]["status"] = (
					"Paid %s" % PlayerMoney.format_money(int(entry["payout"]))
					if result.has("balance")
					else "Bet void"
				)
				state = next
				if result.has("balance") and int(entry["payout"]) > int(entry["stake"]):
					_wallet().announce_gain(
						peer, int(entry["payout"]) - int(entry["stake"]), game.capitalize() + " win"
					)
				break
			await get_tree().create_timer(delay).timeout
			delay = minf(delay * 2, 10)
	var next := state.duplicate(true)
	next["phase"] = "result"
	state = next
	_animate_dealer(["collect", "payout"])
	_clock = 8


func _remove_void_stake(next: Dictionary, stake: int) -> void:
	var winners: Array = next.get("winners", [])
	if winners.is_empty():
		return
	var remaining := -stake
	for peer: int in winners:
		remaining += int(next["players"][peer]["payout"])
	remaining = maxi(0, remaining)
	for i: int in winners.size():
		next["players"][winners[i]]["payout"] = (
			remaining / winners.size() + (1 if i < remaining % winners.size() else 0)
		)
	next["message"] = "A void wager was removed from the pot"


func _send_hand(peer: int) -> void:
	if (
		_hands.has(peer)
		and (peer == multiplayer.get_unique_id() or multiplayer.get_peers().has(peer))
	):
		entity.send_event(&"hand", {"cards": _hands[peer]}, peer)


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"hand":
		private_hand = (payload["cards"] as Array).duplicate()


func _wallet() -> PlayerMoney:
	return get_tree().get_first_node_in_group(&"player_money") as PlayerMoney


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	if is_instance_valid(_screen):
		_screen.call("close")
	var wallet := _wallet()
	if wallet != null:
		for peer: int in state["players"]:
			wallet.release_table(peer, str(state["players"][peer]["id"]))
	state = {
		"phase": "idle",
		"players": {},
		"board": [],
		"dealer": [],
		"turn": 0,
		"message": "",
		"point": 0,
		"dice": [],
		"seconds": 0
	}
	private_hand.clear()
	_hands.clear()


func _exit_tree() -> void:
	var wallet := _wallet() if is_inside_tree() else null
	if wallet != null:
		for peer: int in state["players"]:
			wallet.release_table(peer, str(state["players"][peer]["id"]))


func _animate_dealer(clips: Array[String]) -> void:
	if game == "video_poker":
		return
	var cue: Dictionary = state.get("dealer_animation", {})
	var queue: Array = cue.get("queue", []).duplicate()
	var elapsed := float(cue.get("elapsed", 0.0))
	while not queue.is_empty():
		var duration := CrownDealer.CLIPS.get_animation(StringName(queue[0])).length
		if elapsed < duration - .0001:
			break
		elapsed -= duration
		queue.pop_front()
	if queue.is_empty():
		elapsed = 0.0
	queue.append_array(clips)
	if queue.size() > 16:
		queue = queue.slice(queue.size() - 16)
		elapsed = 0.0
	_dealer_serial += 1
	var next := state.duplicate(true)
	next["dealer_animation"] = {"serial": _dealer_serial, "queue": queue, "elapsed": elapsed}
	state = next


func _update_dealer_clock(delta: float) -> void:
	if not entity.is_authority() or not state.has("dealer_animation"):
		return
	var duration := 0.0
	for clip: String in state["dealer_animation"]["queue"]:
		duration += CrownDealer.CLIPS.get_animation(StringName(clip)).length
	if float(state["dealer_animation"]["elapsed"]) >= duration:
		return
	_dealer_tick += delta
	if _dealer_tick < .1:
		return
	var next := state.duplicate(true)
	next["dealer_animation"]["elapsed"] = minf(
		duration, float(next["dealer_animation"]["elapsed"]) + _dealer_tick
	)
	_dealer_tick = 0.0
	state = next
