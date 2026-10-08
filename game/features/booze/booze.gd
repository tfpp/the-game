class_name Booze
extends Node3D
## Casino liquor: stocks random drinks around the Golden Crown, handles their effect
## (one drink of BarCompanion intoxication per sip) and runs blackouts. Players who
## reach BoozeRules.BLACKOUT_DRINKS collapse, wake stripped to their underwear on a
## metro platform, and sober up. The server owns every phase; all peers lay the
## body down from the replicated `blackouts` snapshot. See README.md.

const SPOT_SCENE := preload("res://features/booze/drink_spot.tscn")

## peer -> BoozeRules.Phase. Replicated on change, including to late joiners.
@export var blackouts: Dictionary = {}

## Server-only phase countdowns, peers waiting to collapse and metro drop-offs.
var _timers: Dictionary[int, float] = {}
var _pending: Dictionary[int, bool] = {}
var _deliveries: Dictionary[int, Dictionary] = {}
var _rng := RandomNumberGenerator.new()
## Presentation on every peer: phase age, lying weight and the yaw a body lies at.
var _seen: Dictionary[int, Array] = {}
var _lying: Dictionary[int, float] = {}
var _lying_yaw: Dictionary[int, float] = {}
var _lying_at: Dictionary[int, Vector3] = {}
var _bar_connected: BarCompanion
var _metro_connected: Node

@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"booze")
	# After avatars (15) have animated, so the whole body can be laid down.
	process_priority = 16
	_rng.randomize()
	for index: int in BoozeRules.SPOTS.size():
		var spot := SPOT_SCENE.instantiate() as DrinkSpot
		spot.name = "Spot%d" % index
		spot.position = BoozeRules.SPOTS[index]
		spot.rotation.y = float(index) * 2.4
		$Spots.add_child(spot)
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(_forget)
	_connect.call_deferred()


## Hooks into sibling features once every feature has loaded.
func _connect() -> void:
	_bar()
	_metro()
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null and combat.multiplayer == multiplayer:
		combat.player_died.connect(func(victim: int, _attacker: int) -> void: _clear(victim))


func phase_for(peer: int) -> int:
	return int(blackouts.get(peer, BoozeRules.Phase.NONE))


## Seconds this peer has been in its current phase, as seen locally.
func phase_elapsed(peer: int) -> float:
	var seen: Array = _seen.get(peer, [])
	return float(seen[1]) if seen.size() == 2 else 0.0


## 0 standing … 1 flat on the ground, as currently drawn on this peer.
func lying_weight(peer: int) -> float:
	return float(_lying.get(peer, 0.0))


func lying_yaw(peer: int, fallback: float) -> float:
	return float(_lying_yaw.get(peer, fallback))


## Consumption handler for ItemDefinition.consumption_group = &"booze". The server's
## ConsumableUse validates sender, hand and state; this only refuses drinkers who
## are already passing out.
func can_consume(peer: int, id: String) -> bool:
	return BoozeRules.is_drink(id) and not blackouts.has(peer) and not _pending.has(peer)


func consume(peer: int, id: String) -> bool:
	if not multiplayer.is_server() or not can_consume(peer, id):
		return false
	var bar := _bar()
	if bar != null:
		bar.add_drink(peer)
	return true


func _process(delta: float) -> void:
	if not is_instance_valid(_bar_connected):
		_bar()
	if multiplayer.is_server():
		advance(delta)
	if Network.mode != Network.Mode.SERVER or DisplayServer.get_name() != "headless":
		present(delta)


## Server: progresses collapses, metro drop-offs and wake-ups.
func advance(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for peer: int in _pending.keys():
		if _start(peer):
			_pending.erase(peer)
	for peer: int in blackouts.keys():
		if not _timers.has(peer):
			continue
		_timers[peer] -= delta
		match phase_for(peer):
			BoozeRules.Phase.COLLAPSE:
				if _timers[peer] <= 0.0:
					_pass_out(peer)
			BoozeRules.Phase.OUT:
				if _deliveries.has(peer):
					_drive_delivery(peer, delta)
				elif _timers[peer] <= 0.0:
					_set_phase(peer, BoozeRules.Phase.WAKE)
					_timers[peer] = BoozeRules.WAKE_S
			BoozeRules.Phase.WAKE:
				if _timers[peer] <= 0.0:
					_clear(peer)


func _on_drink(peer: int, intoxication: float) -> void:
	if multiplayer.is_server() and BoozeRules.blacks_out(intoxication):
		if not blackouts.has(peer):
			_pending[peer] = true


## Begins a collapse once the drinker's hand is idle. False keeps it pending.
func _start(peer: int) -> bool:
	var player := _player(peer)
	if player == null or _respawning(peer):
		return true
	var hand := Hand.for_peer(get_tree(), peer)
	if hand != null:
		if hand.consumption.active() or hand.inventory().loading:
			return false
		hand.inventory().stow_equipment([-1])
	var rig := GunRig.for_peer(get_tree(), peer)
	if rig != null:
		rig.holster()
	_set_phase(peer, BoozeRules.Phase.COLLAPSE)
	_timers[peer] = BoozeRules.COLLAPSE_S
	return true


func _pass_out(peer: int) -> void:
	_set_phase(peer, BoozeRules.Phase.OUT)
	_timers[peer] = BoozeRules.OUT_S
	var hand := Hand.for_peer(get_tree(), peer)
	if hand != null:
		hand.inventory().stow_equipment([-1, -2, -3, -4])
	var bar := _bar()
	if bar != null:
		bar.sober_up(peer)
	var runs := get_tree().get_first_node_in_group(&"slum_runs")
	if runs != null and runs.multiplayer == multiplayer and bool(runs.call("is_active", peer)):
		runs.call("finish", peer)
	var player := _player(peer)
	var metro := _metro()
	if player == null or metro == null:
		return
	var spot := BoozeRules.wake_spot(
		_rng.randi_range(0, 3),
		_rng.randi_range(0, 1),
		_rng.randf(),
		player.movement.hull_height_m()
	)
	var stations: Array = metro.get("stations")
	var origin := (stations[int(spot["station"])] as Node3D).global_position
	_deliveries[peer] = {
		"position": origin + (spot["local"] as Vector3),
		"yaw": spot["yaw"],
		"started": false,
		"waited": 0.0
	}
	_drive_delivery(peer, 0.0)


## Starts (and if needed retries) the metro drop-off; gives up after a timeout.
func _drive_delivery(peer: int, delta: float) -> void:
	var trip := _deliveries[peer]
	trip["waited"] = float(trip["waited"]) + delta
	var metro := _metro()
	if metro == null or float(trip["waited"]) > BoozeRules.DELIVERY_TIMEOUT_S:
		if metro != null:
			metro.call("cancel_delivery", peer)
		_deliveries.erase(peer)
		return
	if not bool(trip["started"]):
		var player := _player(peer)
		trip["started"] = (
			player != null
			and bool(metro.call("deliver", player, trip["position"], float(trip["yaw"])))
		)


func _on_delivered(peer: int) -> void:
	if _deliveries.has(peer):
		_deliveries.erase(peer)
		_timers[peer] = minf(float(_timers.get(peer, 0.0)), 0.5)


func _set_phase(peer: int, phase: int) -> void:
	var next := blackouts.duplicate()
	next[peer] = phase
	blackouts = next


func _clear(peer: int) -> void:
	if multiplayer.is_server():
		if _deliveries.has(peer) and _metro() != null:
			_metro().call("cancel_delivery", peer)
		_pending.erase(peer)
		_timers.erase(peer)
		_deliveries.erase(peer)
		if blackouts.has(peer):
			var next := blackouts.duplicate()
			next.erase(peer)
			blackouts = next


func _forget(peer: int) -> void:
	_clear(peer)
	_seen.erase(peer)
	_lying.erase(peer)
	_lying_yaw.erase(peer)
	_lying_at.erase(peer)


func _reset(_mode: Network.Mode) -> void:
	_pending.clear()
	_timers.clear()
	_deliveries.clear()
	blackouts = {}


## Every peer: lays blacked-out bodies down and stands them back up.
func present(delta: float) -> void:
	if blackouts.is_empty() and _lying.is_empty():
		_seen.clear()
		return
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or player.multiplayer != multiplayer or player.is_queued_for_deletion():
			continue
		var peer := player.get_multiplayer_authority()
		var phase := phase_for(peer)
		var seen: Array = _seen.get(peer, [BoozeRules.Phase.NONE, 0.0])
		seen = [phase, 0.0] if int(seen[0]) != phase else [phase, float(seen[1]) + delta]
		_seen[peer] = seen
		var weight := lying_weight(peer)
		var target := BoozeRules.lying_target(phase, float(seen[1]))
		if not _lying.has(peer) and target <= 0.0:
			continue
		var rate := 1.0 / (BoozeRules.FALL_S if target > weight else BoozeRules.STAND_S)
		weight = move_toward(weight, target, delta * rate)
		var body := player.get_node_or_null("Body") as Node3D
		if body == null:
			continue
		if weight <= 0.0001:
			body.transform = Transform3D(Basis(Vector3.UP, body.rotation.y), Vector3.ZERO)
			_lying.erase(peer)
			_lying_yaw.erase(peer)
			_lying_at.erase(peer)
			continue
		_lying[peer] = weight
		# Capture the facing once, and again after a teleport (the metro drop-off).
		if not _lying_yaw.has(peer) or player.net_position.distance_to(_lying_at[peer]) > 2.0:
			_lying_yaw[peer] = player.yaw if player.is_local() else player.net_yaw
			_lying_at[peer] = player.net_position
		body.transform = BoozeRules.lying_body(
			_lying_yaw[peer], player.movement.hull_height_m(), standing_height(player), weight
		)


static func standing_height(player: Player) -> float:
	var avatar := player.get_node_or_null("Body/Avatar") as BlockPlayerModel
	var scale := avatar.height_scale() if avatar != null else 1.0
	return BoozeRules.STANDARD_HEIGHT * scale


func _bar() -> BarCompanion:
	for node: Node in get_tree().get_nodes_in_group(&"bar_companion"):
		var bar := node as BarCompanion
		if bar != null and bar.multiplayer == multiplayer:
			if _bar_connected != bar:
				_bar_connected = bar
				bar.drink_added.connect(_on_drink)
			return bar
	return null


func _metro() -> Node:
	for node: Node in get_tree().get_nodes_in_group(&"metro_service"):
		if node.multiplayer == multiplayer and node.has_method("deliver"):
			if _metro_connected != node:
				_metro_connected = node
				node.connect(&"delivered", _on_delivered)
			return node
	return null


func _player(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.multiplayer == multiplayer:
			if player.get_multiplayer_authority() == peer and not player.is_queued_for_deletion():
				return player
	return null


func _respawning(peer: int) -> bool:
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	return combat != null and combat.multiplayer == multiplayer and combat.is_respawning(peer)
