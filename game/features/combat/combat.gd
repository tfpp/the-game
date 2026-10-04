class_name Combat
extends Node
## Server-authoritative health and kills. Weapons (features/holdables/hand.gd's
## `_fire`) look this feature up by group and call `apply_damage` when a hitscan
## connects; this turns that into a kill and a respawn once someone's health runs
## out. Health is a peer-keyed dictionary, replicated the same way
## features/smeckles/smeckles.gd replicates balances.

## Broadcast whenever someone's health hits zero (see `_announce_death`), so
## combat_hud.gd can show the victim the death screen.
signal player_died(victim_peer: int, attacker_peer: int)
signal player_respawned(peer_id: int)

const MAX_HEALTH := 100.0
const RESPAWN_DELAY_S := 2.0

## Legacy fallback when no feature supplies a player_spawn marker.
## Join, fall recovery and combat respawn use the same feature-owned marker.
const RESPAWN_POINT := Vector3(0, 1.2, 12)
const RESPAWN_JITTER := 3.0
const HEALTH_STATE := preload("res://features/combat/health_state.gd")

## peer_id (as String, since Dictionary keys round-trip through replication that way) -> float
@export var health: Dictionary = {}
## peer_id (as String) -> int of other players killed. Self-damage never counts.
@export var kills: Dictionary = {}

## Server-only countdowns. Cleared on disconnect and session changes.
var _respawns: Dictionary[int, float] = {}
var _health_spawner: MultiplayerSpawner
var _health_states: Node
var _events: NetworkedEntity


func _ready() -> void:
	add_to_group(&"combat")
	_health_states = Node.new()
	_health_states.name = "HealthStates"
	add_child(_health_states)
	_health_spawner = MultiplayerSpawner.new()
	_health_spawner.name = "HealthSpawner"
	_health_spawner.spawn_path = NodePath("../HealthStates")
	_health_spawner.spawn_function = _spawn_health
	add_child(_health_spawner)
	_events = NetworkedEntity.new()
	_events.name = "NetworkedEntity"
	add_child(_events)
	_events.event_received.connect(_receive_status)
	Network.mode_changed.connect(_reset)
	multiplayer.peer_disconnected.connect(_cancel_respawn)
	multiplayer.peer_connected.connect(_on_peer_connected)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for peer_id: int in _respawns.keys():
		_respawns[peer_id] -= delta
		if _respawns[peer_id] <= 0.0:
			_respawns.erase(peer_id)
			var player := _player_for_peer(peer_id)
			if player != null:
				player.server_teleport.rpc_id(peer_id, _respawn_position())
			_send_status(&"respawn", peer_id)


func health_for(peer_id: int) -> float:
	if not multiplayer.is_server():
		var state := _health_states.get_node_or_null(str(peer_id))
		return float(state.get("value")) if state != null else MAX_HEALTH
	return float(health.get(str(peer_id), MAX_HEALTH))


func kills_for(peer_id: int) -> int:
	return int(kills.get(str(peer_id), 0))


func is_respawning(peer_id: int) -> bool:
	return _respawns.has(peer_id)


## Server-only: `attacker_peer` deals `amount` damage to `target_peer`. Once that
## brings them to zero or below, they're healed and respawn after the death screen.
func apply_damage(target_peer: int, amount: float, attacker_peer: int) -> void:
	if not multiplayer.is_server() or amount <= 0.0 or _respawns.has(target_peer):
		return
	if (
		attacker_peer != target_peer
		and (
			_in_safe_zone(target_peer, attacker_peer)
			or not _same_instance(target_peer, attacker_peer)
		)
	):
		return
	var remaining := health_for(target_peer) - amount
	if remaining > 0.0:
		_set_health(target_peer, remaining)
		return
	_set_health(target_peer, MAX_HEALTH)
	_respawns[target_peer] = RESPAWN_DELAY_S
	if attacker_peer != target_peer:
		_add_kill(attacker_peer)
	# Announce before teleporting so slum-run listeners can scatter the victim's
	# valuables where they actually fell, not at the casino respawn point.
	_send_status(&"death", target_peer, attacker_peer)


func _spawn_health(data: Variant) -> Node:
	var info := data as Dictionary
	var state := HEALTH_STATE.new()
	state.name = str(info["peer"])
	state.peer_id = int(info["peer"])
	state.value = float(info["value"])
	return state


func _on_peer_connected(peer: int) -> void:
	if multiplayer.is_server():
		_ensure_health_state(peer, health_for(peer))


func _ensure_health_state(peer: int, value: float) -> void:
	var state := _health_states.get_node_or_null(str(peer))
	if state == null:
		_health_spawner.spawn({"peer": peer, "value": value})
	else:
		state.set("value", value)


func _status_recipients(victim: int) -> Array[int]:
	var result: Array[int] = []
	for peer: int in multiplayer.get_peers():
		var relevant := true
		for service: Node in get_tree().get_nodes_in_group(&"zone_instances"):
			if service.multiplayer == multiplayer:
				relevant = bool(service.call("can_observe_player", victim, peer))
				break
		if relevant:
			result.append(peer)
	return result


func _send_status(event: StringName, victim: int, attacker: int = 0) -> void:
	# Capture recipients before local death listeners remove excursion membership.
	var recipients := _status_recipients(victim)
	var payload := {"victim": victim, "attacker": attacker}
	_receive_status(event, payload)
	for peer: int in recipients:
		_events.send_event(event, payload, peer)


func _receive_status(event: StringName, payload: Dictionary) -> void:
	if event == &"death":
		_announce_death(int(payload["victim"]), int(payload["attacker"]))
	elif event == &"respawn":
		_announce_respawn(int(payload["victim"]))


## Hostile NPC damage has no player attacker. Keep the no-kill-credit behavior
## without treating it as deliberate self-damage, which remains available in hubs.
func apply_enemy_damage(target_peer: int, amount: float) -> void:
	if not multiplayer.is_server() or SafeZone.covers_peer(get_tree(), target_peer):
		return
	apply_damage(target_peer, amount, target_peer)


## Server-only: restores up to `amount` health to `peer_id`, never above
## MAX_HEALTH. Food items call this when eaten (features/holdables/hand.gd).
func heal(peer_id: int, amount: float) -> void:
	if not multiplayer.is_server() or amount <= 0.0:
		return
	var current := health_for(peer_id)
	if current < MAX_HEALTH:
		_set_health(peer_id, minf(current + amount, MAX_HEALTH))


@rpc("authority", "call_local", "reliable")
func _announce_death(victim_peer: int, attacker_peer: int) -> void:
	player_died.emit(victim_peer, attacker_peer)


@rpc("authority", "call_local", "reliable")
func _announce_respawn(peer_id: int) -> void:
	player_respawned.emit(peer_id)


func _cancel_respawn(peer_id: int) -> void:
	_respawns.erase(peer_id)
	if not multiplayer.is_server():
		return
	var state := _health_states.get_node_or_null(str(peer_id))
	if state != null:
		state.queue_free()


func _reset(_mode: Network.Mode) -> void:
	_respawns.clear()
	health = {}
	kills = {}
	for state: Node in _health_states.get_children():
		_health_states.remove_child(state)
		state.queue_free()


func _set_health(peer_id: int, value: float) -> void:
	var next := health.duplicate()
	next[str(peer_id)] = value
	health = next
	_ensure_health_state(peer_id, value)


func _add_kill(peer_id: int) -> void:
	var next := kills.duplicate()
	next[str(peer_id)] = kills_for(peer_id) + 1
	kills = next


func _respawn_position() -> Vector3:
	var jitter := Vector3(
		randf_range(-RESPAWN_JITTER, RESPAWN_JITTER),
		0.0,
		randf_range(-RESPAWN_JITTER, RESPAWN_JITTER)
	)
	var feature_spawn := get_tree().get_first_node_in_group(&"player_spawn") as Marker3D
	return (feature_spawn.global_position if feature_spawn != null else RESPAWN_POINT) + jitter


## The Golden Crown is safe (features/safe_zone): no player hurts another while
## either stands inside. Self-inflicted damage such as /suicide still applies.
func _in_safe_zone(target_peer: int, attacker_peer: int) -> bool:
	var tree := get_tree()
	return SafeZone.covers_peer(tree, target_peer) or SafeZone.covers_peer(tree, attacker_peer)


func _same_instance(target_peer: int, attacker_peer: int) -> bool:
	for service: Node in get_tree().get_nodes_in_group(&"zone_instances"):
		if service.multiplayer == multiplayer:
			return bool(service.call("shares_instance", target_peer, attacker_peer))
	return true


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
