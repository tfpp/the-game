extends Node3D
## A burrow of gnomes that dash single file, train-style, between whichever two of the
## burrow's holes the server last picked, resting at one before choosing the next.
##
## Server-authoritative like the rest of shared state (see game/AGENTS.md): the server
## (or the offline peer, which is its own server) drives `net_progress`/`net_from_hole`/
## `net_to_hole` in `_physics_process`, replicated to every client by Sync
## (MultiplayerSynchronizer). Every peer derives each gnome's position independently
## from that shared state plus the burrow's hole positions, which are fixed in the
## scene and therefore already identical everywhere. GnomeMath.follower_distance gives
## the single-file spacing.

const REMOTE_SMOOTHING := 12.0

## Replicated state (server -> everyone). See the synchronizer config in gnome_train.tscn.
@export var net_progress := 0.0
@export var net_from_hole := 0
@export var net_to_hole := 0

var _holes: Array[Vector3] = []
var _leg_speed := GnomeMath.RUN_SPEED
var _resting := true
var _rest_timer := 0.0
var _smoothed: Array[Vector3] = []
var _smoothed_yaw: Array[float] = []

@onready var _gnomes: Array[Node3D] = _collect_named("Gnome")


func _ready() -> void:
	for hole: Node3D in _collect_named("Hole"):
		_holes.append(hole.position)
	for i in _gnomes.size():
		_smoothed.append(_holes[0])
		_smoothed_yaw.append(0.0)
	if multiplayer.is_server():
		net_from_hole = 0
		net_to_hole = GnomeMath.next_hole_index(0, _holes.size(), randf())
		_rest_timer = randf_range(GnomeMath.REST_MIN, GnomeMath.REST_MAX)
	else:
		set_physics_process(false)


func _collect_named(prefix: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in get_children():
		if child.name.begins_with(prefix) and child is Node3D:
			result.append(child)
	return result


func _physics_process(delta: float) -> void:
	if _resting:
		_rest_timer -= delta
		if _rest_timer <= 0.0:
			_resting = false
			net_progress = 0.0
			_leg_speed = GnomeMath.leg_speed(GnomeMath.RUN_SPEED, randf())
		return
	var path_length := _holes[net_from_hole].distance_to(_holes[net_to_hole])
	var total_distance := GnomeMath.total_distance(
		path_length, _gnomes.size(), GnomeMath.FOLLOW_SPACING
	)
	var duration := GnomeMath.leg_duration(total_distance, _leg_speed)
	net_progress = GnomeMath.advance_progress(net_progress, delta, duration)
	if net_progress >= 1.0:
		_resting = true
		_rest_timer = randf_range(GnomeMath.REST_MIN, GnomeMath.REST_MAX)
		net_from_hole = net_to_hole
		net_to_hole = GnomeMath.next_hole_index(net_from_hole, _holes.size(), randf())


func _process(delta: float) -> void:
	var hole_a := _holes[net_from_hole]
	var hole_b := _holes[net_to_hole]
	var path_length := hole_a.distance_to(hole_b)
	var total_distance := GnomeMath.total_distance(
		path_length, _gnomes.size(), GnomeMath.FOLLOW_SPACING
	)
	var travel_dir := hole_b - hole_a
	var yaw := GnomeMath.facing_yaw(hole_a, hole_b, true)
	var is_server := multiplayer.is_server()
	var lerp_t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	var player_positions: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player != null:
			player_positions.append(player.global_position)
	for i in _gnomes.size():
		var distance := GnomeMath.follower_distance(
			net_progress, total_distance, path_length, i, GnomeMath.FOLLOW_SPACING
		)
		var target := GnomeMath.gnome_position(hole_a, hole_b, true, distance, path_length)
		target += GnomeMath.avoidance_offset(target, travel_dir, player_positions)
		var gnome := _gnomes[i]
		if is_server:
			gnome.position = target
			gnome.rotation.y = yaw
		else:
			_smoothed[i] = _smoothed[i].lerp(target, lerp_t)
			_smoothed_yaw[i] = lerp_angle(_smoothed_yaw[i], yaw, lerp_t)
			gnome.position = _smoothed[i]
			gnome.rotation.y = _smoothed_yaw[i]
		gnome.visible = GnomeMath.gnome_visible(distance, path_length)
