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

## Mirrors world/room.tscn's Spawn marker: features can't read core/world nodes
## directly, so killed players reappear here with the same jitter
## core/game/game.gd uses for normal spawns.
const RESPAWN_POINT := Vector3(0, 1.2, 12)
const RESPAWN_JITTER := 3.0

## peer_id (as String, since Dictionary keys round-trip through replication that way) -> float
@export var health: Dictionary = {}
## peer_id (as String) -> int of other players killed. Self-damage never counts.
@export var kills: Dictionary = {}

## Server-only countdowns. Cleared on disconnect and session changes.
var _respawns: Dictionary[int, float] = {}


func _ready() -> void:
	add_to_group(&"combat")
	Network.mode_changed.connect(_reset)
	multiplayer.peer_disconnected.connect(_cancel_respawn)


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
			_announce_respawn.rpc(peer_id)


func health_for(peer_id: int) -> float:
	return float(health.get(str(peer_id), MAX_HEALTH))


func kills_for(peer_id: int) -> int:
	return int(kills.get(str(peer_id), 0))


## Server-only: `attacker_peer` deals `amount` damage to `target_peer`. Once that
## brings them to zero or below, they're healed and respawn after the death screen.
func apply_damage(target_peer: int, amount: float, attacker_peer: int) -> void:
	if not multiplayer.is_server() or amount <= 0.0 or _respawns.has(target_peer):
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
	_announce_death.rpc(target_peer, attacker_peer)


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


func _reset(_mode: Network.Mode) -> void:
	_respawns.clear()
	health = {}
	kills = {}


func _set_health(peer_id: int, value: float) -> void:
	var next := health.duplicate()
	next[str(peer_id)] = value
	health = next


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
	return RESPAWN_POINT + jitter


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
