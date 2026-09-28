extends Node3D
## A burrow of gnomes that dash single file, train-style, along a navmesh route between
## whichever two of the burrow's holes the server last picked, resting at one before
## choosing the next.
##
## Server-authoritative like the rest of shared state (see game/AGENTS.md): the server
## (or the offline peer, which is its own server) drives `net_progress`/`net_from_hole`/
## `net_to_hole` in `_physics_process`, replicated to every client by Sync
## (MultiplayerSynchronizer). Every peer derives each gnome's position independently
## from that shared state, the burrow's hole positions (fixed in the scene, so already
## identical everywhere) and the shared prebaked navmesh (`gnome_navmesh.tres`, loaded
## by every peer the same way, so `NavigationServer3D.map_get_path` returns the same
## route everywhere too). GnomeMath.follower_distance gives the single-file spacing.

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
var _cached_from := -1
var _cached_to := -1
var _current_path: PackedVector3Array = []
var _current_path_length := 0.0

@onready var _gnomes: Array[Node3D] = _collect_named("Gnome")


func _ready() -> void:
	for hole: Node3D in _collect_named("Hole"):
		_holes.append(hole.position)
	for i in _gnomes.size():
		_smoothed.append(_holes[0])
		_smoothed_yaw.append(0.0)
	if multiplayer.is_server():
		net_from_hole = 0
		net_to_hole = GnomeMath.next_hole_index(0, _holes, randf())
		_rest_timer = randf_range(GnomeMath.REST_MIN, GnomeMath.REST_MAX)
	else:
		set_physics_process(false)


func _collect_named(prefix: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in get_children():
		if child.name.begins_with(prefix) and child is Node3D:
			result.append(child)
	return result


## Recomputes the navmesh route for the current (net_from_hole, net_to_hole) leg
## whenever that pair changes, and caches it: every peer calls this independently, but
## since the navmesh and hole positions are identical everywhere, so is the result.
## Falls back to a straight line if the navmesh hasn't finished registering yet (a
## couple of frames at startup) so movement never divides by a zero-length path.
## `_holes` (and everything else in this script) is in this node's local space, but
## the navmesh lives in world space, so the query goes out and comes back through
## to_global/to_local.
func _ensure_path() -> void:
	if _cached_from == net_from_hole and _cached_to == net_to_hole:
		return
	var map := get_world_3d().get_navigation_map()
	var from_pos := to_global(_holes[net_from_hole])
	var to_pos := to_global(_holes[net_to_hole])
	var path := NavigationServer3D.map_get_path(map, from_pos, to_pos, true)
	if path.size() < 2:
		path = PackedVector3Array([from_pos, to_pos])
	var local_path := PackedVector3Array()
	for point: Vector3 in path:
		local_path.append(to_local(point))
	_current_path = local_path
	_current_path_length = GnomeMath.path_total_length(local_path)
	_cached_from = net_from_hole
	_cached_to = net_to_hole


func _physics_process(delta: float) -> void:
	if _resting:
		_rest_timer -= delta
		if _rest_timer <= 0.0:
			_resting = false
			net_progress = 0.0
			_leg_speed = GnomeMath.leg_speed(GnomeMath.RUN_SPEED, randf())
		return
	_ensure_path()
	var total_distance := GnomeMath.total_distance(
		_current_path_length, _gnomes.size(), GnomeMath.FOLLOW_SPACING
	)
	var duration := GnomeMath.leg_duration(total_distance, _leg_speed)
	net_progress = GnomeMath.advance_progress(net_progress, delta, duration)
	if net_progress >= 1.0:
		_resting = true
		_rest_timer = randf_range(GnomeMath.REST_MIN, GnomeMath.REST_MAX)
		net_from_hole = net_to_hole
		net_to_hole = GnomeMath.next_hole_index(net_from_hole, _holes, randf())


func _process(delta: float) -> void:
	_ensure_path()
	var path_length := _current_path_length
	var total_distance := GnomeMath.total_distance(
		path_length, _gnomes.size(), GnomeMath.FOLLOW_SPACING
	)
	var is_server := multiplayer.is_server()
	var lerp_t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	# Avoidance compares against `target` below, which (like everything else in this
	# script) is in this node's local space, so players need converting too.
	var player_positions: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player != null:
			player_positions.append(to_local(player.global_position))
	for i in _gnomes.size():
		var distance := GnomeMath.follower_distance(
			net_progress, total_distance, path_length, i, GnomeMath.FOLLOW_SPACING
		)
		var target := GnomeMath.position_on_path(_current_path, distance)
		var dir := GnomeMath.direction_on_path(_current_path, distance)
		target += GnomeMath.avoidance_offset(target, dir, player_positions)
		var yaw := GnomeMath.facing_yaw(dir)
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
