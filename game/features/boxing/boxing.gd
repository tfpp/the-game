class_name Boxing
extends Node
## Punching for whoever has nothing in hand, plus X kicks with or without items.
## Click to jab; hold the
## click and release it for a power punch (stronger the longer you hold, up to
## BoxingMath.FULL_CHARGE_S).
##
## Server-authoritative: the client only reports pressing and releasing
## `primary_action` (the same left click / RB that fires a held weapon,
## features/holdables/hand.gd). The server times the hold itself, checks the
## sender is unarmed and off cooldown, then does a short melee trace from the
## puncher's eye. Targets with `take_punch(attacker_peer, strength, direction)`
## (features/shooting_gallery's dummies) handle it themselves; players take
## damage through features/combat; other `killable`s take a hit from power punches.

const REACH_M := 2.0
const SWEEP_RADIUS_M := 0.45
const JAB_COOLDOWN_S := 0.3
const POWER_COOLDOWN_S := 0.6

## Local only: when the owner started holding the button (msec), or -1.
var _local_press_ms := -1
var _local_kick := false
var _wind_up_kick: Dictionary[int, bool] = {}
var _dead_peers: Dictionary[int, bool] = {}
## Server only: peer -> press time (msec) and peer -> earliest next punch (msec).
var _wind_up_ms: Dictionary[int, int] = {}
var _ready_at_ms: Dictionary[int, int] = {}

var _fists := BoxingFists.new()
var _kicks := BoxingKicks.new()


func _ready() -> void:
	add_to_group(&"boxing")
	# Same bindings features/holdables/hand.gd registers; whichever loads first wins.
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_RIGHT_SHOULDER
	Controls.ensure_action(&"primary_action", [mouse, pad])
	_fists.name = "Fists"
	add_child(_fists)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_X
	Controls.ensure_action(&"kick", [key])
	_kicks.name = "Kicks"
	add_child(_kicks)
	Controls.input_reset.connect(_cancel_local)
	_connect_combat.call_deferred()
	multiplayer.peer_disconnected.connect(_forget_peer)
	Network.mode_changed.connect(_on_mode_changed)


func _process(_delta: float) -> void:
	var player := _local_player()
	var winding := _local_press_ms >= 0 and player != null
	if (
		_local_press_ms >= 0
		and (
			player == null
			or not Controls.gameplay_active()
			or not _can_strike(multiplayer.get_unique_id(), _local_kick)
		)
	):
		_cancel_local()
		winding = false
	var held := (Time.get_ticks_msec() - _local_press_ms) / 1000.0 if winding else 0.0
	_fists.set_local_charge(BoxingMath.charge(held) if winding and not _local_kick else -1.0)
	_kicks.set_local_charge(BoxingMath.charge(held) if winding and _local_kick else -1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not (event.is_action(&"primary_action") or event.is_action(&"kick")) or event.is_echo():
		return
	var me := multiplayer.get_unique_id()
	var kicking := event.is_action(&"kick")
	if event.is_pressed():
		if _local_press_ms >= 0 or not Controls.gameplay_active() or not _can_strike(me, kicking):
			return
		_local_press_ms = Time.get_ticks_msec()
		_local_kick = kicking
		request_wind_up.rpc_id(1, kicking)
		get_viewport().set_input_as_handled()
	elif _local_press_ms >= 0 and kicking == _local_kick:
		_local_press_ms = -1
		if Controls.gameplay_active():
			request_punch.rpc_id(1, kicking)
		else:
			request_cancel.rpc_id(1)
		get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func request_wind_up(kicking: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if not _can_strike(peer, kicking) or _wind_up_ms.has(peer):
		return
	if Time.get_ticks_msec() < int(_ready_at_ms.get(peer, 0)):
		return
	_wind_up_ms[peer] = Time.get_ticks_msec()
	_wind_up_kick[peer] = kicking


@rpc("any_peer", "call_local", "reliable")
func request_punch(kicking: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	# Kicks require a matching server-accepted press; no client supplies strength.
	if kicking and (not _wind_up_ms.has(peer) or not _wind_up_kick.get(peer, false)):
		return
	if _wind_up_ms.has(peer) and bool(_wind_up_kick.get(peer, false)) != kicking:
		return
	var held := 0.0
	if _wind_up_ms.has(peer):
		held = (Time.get_ticks_msec() - _wind_up_ms[peer]) / 1000.0
		_wind_up_ms.erase(peer)
		_wind_up_kick.erase(peer)
	punch(peer, held, kicking)


@rpc("any_peer", "call_local", "reliable")
func request_cancel() -> void:
	if multiplayer.is_server():
		_wind_up_ms.erase(_sender())
		_wind_up_kick.erase(_sender())


## Server: `peer` throws a punch or kick after holding the button for `held_s` seconds.
## Returns the node that was hit, or null for a miss or a rejected punch.
func punch(peer: int, held_s: float, kicking: bool = false) -> Node:
	if not multiplayer.is_server():
		return null
	var now := Time.get_ticks_msec()
	if now < int(_ready_at_ms.get(peer, 0)) or not _can_strike(peer, kicking):
		return null
	var player := _player_for(peer)
	if player == null:
		return null
	var power := BoxingMath.is_power(held_s)
	var cooldown := POWER_COOLDOWN_S if power else JAB_COOLDOWN_S
	_ready_at_ms[peer] = now + int(cooldown * 1000.0)
	var strength := BoxingMath.strength(held_s)
	_play_swing.rpc(peer, power, kicking)
	var hit := _melee_trace(player, kicking)
	if hit.is_empty():
		return null
	var target := hit["collider"] as Node
	_land(target, peer, strength, power, BoxingMath.push_direction(player.net_yaw))
	_play_landed.rpc(hit["position"])
	return target


func _land(target: Node, peer: int, strength: float, power: bool, direction: Vector3) -> void:
	if target.has_method(&"take_punch"):
		target.call(&"take_punch", peer, strength, direction)
	elif target is Player:
		var combat := get_tree().get_first_node_in_group(&"combat")
		if combat != null:
			combat.call(
				&"apply_damage",
				target.get_multiplayer_authority(),
				BoxingMath.PLAYER_DAMAGE_AT_FULL * strength,
				peer
			)
	elif power and target.is_in_group(&"killable"):
		target.call(&"take_hit", peer)


## A ray from the eye along the aim, then a small sphere at the end of reach so a
## dummy lying at your feet is still easy to hit.
func _melee_trace(player: Player, kicking: bool = false) -> Dictionary:
	var origin := (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5)
	)
	var aim := ThrowMath.aim_direction(player.net_yaw, player.net_pitch)
	var space := player.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
		origin, origin + aim * REACH_M, 1 | 2, [player.get_rid()]
	)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		if _punchable(hit["collider"]):
			return hit
		if kicking:
			return {}
	var sphere := SphereShape3D.new()
	sphere.radius = SWEEP_RADIUS_M
	var shape := PhysicsShapeQueryParameters3D.new()
	shape.shape = sphere
	shape.collision_mask = 1 | 2
	shape.exclude = [player.get_rid()]
	var center := origin + aim * (REACH_M - SWEEP_RADIUS_M)
	shape.transform = Transform3D(Basis.IDENTITY, center)
	for result: Dictionary in space.intersect_shape(shape, 8):
		if _punchable(result["collider"]):
			if kicking:
				var body := result["collider"] as Node3D
				var sight := PhysicsRayQueryParameters3D.create(
					origin, body.global_position, 1 | 2, [player.get_rid()]
				)
				var blocker := space.intersect_ray(sight)
				if not blocker.is_empty() and blocker["collider"] != body:
					continue
			return {"collider": result["collider"], "position": center}
	return {}


func _punchable(collider: Object) -> bool:
	var node := collider as Node
	return (
		node != null
		and (node.has_method(&"take_punch") or node is Player or node.is_in_group(&"killable"))
	)


@rpc("authority", "call_local", "reliable")
func _play_swing(peer: int, power: bool, kicking: bool = false) -> void:
	if kicking:
		_kicks.swing(peer, power)
	else:
		_fists.swing(peer, power)


@rpc("authority", "call_local", "reliable")
func _play_landed(at: Vector3) -> void:
	GameAudio.play_at(self, &"hit", at)


## Cosmetic pose of the last server-accepted swing, or empty when at rest.
func arm_pose(peer: int) -> Dictionary:
	return _fists.arm_pose(peer)


func leg_pose(peer: int) -> Dictionary:
	return _kicks.leg_pose(peer)


func _can_strike(peer: int, kicking: bool) -> bool:
	return _player_for(peer) != null and not _dead_peers.has(peer) and (kicking or _unarmed(peer))


func _cancel_local() -> void:
	if _local_press_ms >= 0:
		request_cancel.rpc_id(1)
	_local_press_ms = -1
	_fists.set_local_charge(-1.0)
	_kicks.set_local_charge(-1.0)


func _connect_combat() -> void:
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null:
		combat.player_died.connect(_on_player_died)
		combat.player_respawned.connect(_on_player_respawned)


func _on_player_died(peer: int, _attacker: int) -> void:
	_forget_peer(peer)
	_dead_peers[peer] = true
	if peer == multiplayer.get_unique_id():
		_cancel_local()


func _on_player_respawned(peer: int) -> void:
	_dead_peers.erase(peer)


func _unarmed(peer: int) -> bool:
	var hand := Hand.for_peer(get_tree(), peer)
	if hand != null and not hand.net_item_id.is_empty():
		return false
	var rig := GunRig.for_peer(get_tree(), peer)
	return rig == null or not rig.is_active()


func _sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()


func _player_for(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if (
			player != null
			and player.multiplayer == multiplayer
			and player.name == str(peer)
			and player.get_multiplayer_authority() == peer
		):
			return player
	return null


func _local_player() -> Player:
	return _player_for(multiplayer.get_unique_id())


func _forget_peer(peer: int) -> void:
	_fists.forget_peer(peer)
	_kicks.forget_peer(peer)
	_dead_peers.erase(peer)
	_wind_up_kick.erase(peer)
	_wind_up_ms.erase(peer)
	_ready_at_ms.erase(peer)


func _on_mode_changed(_mode: Network.Mode) -> void:
	_fists.reset()
	_kicks.reset()
	_dead_peers.clear()
	_wind_up_kick.clear()
	_wind_up_ms.clear()
	_ready_at_ms.clear()
	_local_press_ms = -1
