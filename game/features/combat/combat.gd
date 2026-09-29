class_name Combat
extends Node
## Server-authoritative health and kills. Weapons (features/holdables/hand.gd's
## `_fire`) look this feature up by group and call `apply_damage` when a hitscan
## connects; this turns that into a kill and a respawn once someone's health runs
## out. Health is a peer-keyed dictionary, replicated the same way
## features/smeckles/smeckles.gd replicates balances.

## Broadcast whenever someone's health hits zero (see `_announce_death`), so
## combat_hud.gd can show the victim a "You died" flash.
signal player_died(victim_peer: int, attacker_peer: int)

const MAX_HEALTH := 100.0

## Mirrors world/room.tscn's Spawn marker: features can't read core/world nodes
## directly, so killed players reappear here with the same jitter
## core/game/game.gd uses for normal spawns.
const RESPAWN_POINT := Vector3(0, 1.2, 12)
const RESPAWN_JITTER := 3.0

## peer_id (as String, since Dictionary keys round-trip through replication that way) -> float
@export var health: Dictionary = {}
## peer_id (as String) -> int of other players killed. Self-damage never counts.
@export var kills: Dictionary = {}


func _ready() -> void:
	add_to_group(&"combat")
	Network.mode_changed.connect(_reset)


func health_for(peer_id: int) -> float:
	return float(health.get(str(peer_id), MAX_HEALTH))


func kills_for(peer_id: int) -> int:
	return int(kills.get(str(peer_id), 0))


## Server-only: `attacker_peer` deals `amount` damage to `target_peer`. Once that
## brings them to zero or below, they're healed back up and respawned.
func apply_damage(target_peer: int, amount: float, attacker_peer: int) -> void:
	if not multiplayer.is_server() or amount <= 0.0:
		return
	var remaining := health_for(target_peer) - amount
	if remaining > 0.0:
		_set_health(target_peer, remaining)
		return
	_set_health(target_peer, MAX_HEALTH)
	var player := _player_for_peer(target_peer)
	if attacker_peer != target_peer:
		_add_kill(attacker_peer)
	# Announce before teleporting so slum-run listeners can scatter the victim's
	# valuables where they actually fell, not at the casino respawn point.
	_announce_death.rpc(target_peer, attacker_peer)
	if player != null:
		player.server_teleport.rpc_id(target_peer, _respawn_position())


@rpc("authority", "call_local", "reliable")
func _announce_death(victim_peer: int, attacker_peer: int) -> void:
	player_died.emit(victim_peer, attacker_peer)


func _reset(_mode: Network.Mode) -> void:
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
