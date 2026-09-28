class_name Frog
extends Node3D
## A decorative frog that hops around its spawn point forever.
##
## Server-authoritative like the rest of shared state (see game/AGENTS.md): the server
## (or the offline peer, which is its own server) drives the hop cycle in
## `_physics_process` and publishes `net_position`/`net_yaw`, which Sync
## (MultiplayerSynchronizer) replicates to every client. Non-authoritative peers only
## smooth toward the replicated values. The hop math itself lives in frog_hop.gd so
## it's unit-testable on its own.

const REMOTE_SMOOTHING := 12.0

## Replicated state (server -> everyone). See the synchronizer config in frog.tscn.
@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0

## Set by the feature script's spawn data, identically on every peer, before this node
## enters the tree, so it doesn't need its own synchronizer property.
var body_color := Color(0.3, 0.8, 0.35)

var _home := Vector3.ZERO
var _hopping := false
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_elapsed := 0.0
var _rest_timer := 0.0

@onready var _body: Node3D = $Body


func _ready() -> void:
	_home = position
	net_position = position
	var mat := _body.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.albedo_color = body_color
	if multiplayer.is_server():
		_rest_timer = randf_range(FrogHop.REST_MIN, FrogHop.REST_MAX)
	else:
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if _hopping:
		_hop_elapsed += delta
		var t := _hop_elapsed / FrogHop.HOP_DURATION
		net_position = FrogHop.arc_position(_hop_from, _hop_to, t, FrogHop.HOP_HEIGHT)
		position = net_position
		if t >= 1.0:
			_hopping = false
			position = _hop_to
			net_position = _hop_to
			_rest_timer = randf_range(FrogHop.REST_MIN, FrogHop.REST_MAX)
	else:
		_rest_timer -= delta
		if _rest_timer <= 0.0:
			_start_hop()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		return
	var t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	position = position.lerp(net_position, t)
	_body.rotation.y = lerp_angle(_body.rotation.y, net_yaw, t)


func _start_hop() -> void:
	_hop_from = position
	_hop_to = FrogHop.pick_target(_home, FrogHop.HOP_RADIUS, randf() * TAU, randf())
	net_yaw = FrogHop.facing_yaw(_hop_from, _hop_to)
	_body.rotation.y = net_yaw
	_hop_elapsed = 0.0
	_hopping = true
