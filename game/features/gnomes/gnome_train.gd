extends Node3D
## A burrow of gnomes. After resting in a doggy-door hole on the wall, they come out
## one by one, each wanders its own random route across the room and then they all
## slip into another hole of the burrow. They sidestep players, NPCs and frogs, and
## can be shot or punched like frogs. A dead gnome is only hidden (Gnome.set_shown);
## it comes back the next time the burrow comes out of a hole.
##
## Server-authoritative (see game/AGENTS.md): only the server (or the offline peer)
## plans routes on the shared prebaked navmesh (`gnome_navmesh.tres`) and moves the
## gnomes. Sync replicates each gnome's position, facing and whether it is out, so
## clients do no path queries and only smooth and show what they receive.

const REMOTE_SMOOTHING := 12.0
const SENSE_INTERVAL := 0.1
const AVOID_SMOOTHING := 8.0
## Navmesh polygons sit this far above the floor they were baked from.
const NAV_FLOOR_OFFSET := 0.4
## Wander stops on a different floor (the gallery, the gaming pit) are rejected.
const MAX_WANDER_RISE := 0.8
## Route points snap to floor collision within this height, so gnomes don't hover on
## the navmesh's approximate (cell-rounded) height.
const FLOOR_SNAP_RANGE := 0.6
const FLOOR_LAYER := 1
const ROAM_SPEED := 3.5
const FLAP_SMOOTHING := 14.0

## Replicated state (server -> everyone). See the synchronizer config in gnome_train.tscn.
@export var net_positions := PackedVector3Array()
@export var net_yaws := PackedFloat32Array()
## Bit i is set while gnome i is out of its hole and alive.
@export var net_shown := 0

var _holes: Array[Node3D] = []
var _hole_positions: Array[Vector3] = []
var _from_hole := 0
var _to_hole := 0
var _resting := true
var _rest_timer := 0.0
var _elapsed := 0.0
var _routes: Array[PackedVector3Array] = []
var _route_lengths: Array[float] = []
var _speeds: Array[float] = []
var _delays: Array[float] = []
var _alive: Array[bool] = []
var _avoid: Array[Vector3] = []
var _obstacles: Array[Vector3] = []
var _sense_timer := 0.0
var _smoothed_ready: Array[bool] = []

@onready var _gnomes: Array[Gnome] = _collect_gnomes()


func _ready() -> void:
	for child: Node in get_children():
		if child.name.begins_with("Hole") and child is Node3D:
			_holes.append(child as Node3D)
			_hole_positions.append((child as Node3D).position)
	for i in _gnomes.size():
		_gnomes[i].train = self
		_gnomes[i].index = i
		_gnomes[i].set_shown(false)
		net_positions.append(_hole_positions[0])
		net_yaws.append(0.0)
		_routes.append(PackedVector3Array([_hole_positions[0]]))
		_route_lengths.append(0.0)
		_speeds.append(ROAM_SPEED)
		_delays.append(0.0)
		_alive.append(true)
		_avoid.append(Vector3.ZERO)
		_smoothed_ready.append(false)
	_rest_timer = randf_range(GnomeMath.REST_MIN, GnomeMath.REST_MAX)
	Network.mode_changed.connect(_on_mode_changed)


## Features load before networking starts, when every peer still counts as the server.
## A joining client must drop whatever it simulated so far and show only the
## server's state; a new server starts its burrows from rest.
func _on_mode_changed(_mode: Network.Mode) -> void:
	_resting = true
	_rest_timer = randf_range(GnomeMath.REST_MIN, GnomeMath.REST_MAX)
	_elapsed = 0.0
	net_shown = 0
	for i in _gnomes.size():
		_alive[i] = true
		_avoid[i] = Vector3.ZERO
		_routes[i] = PackedVector3Array([_hole_positions[_from_hole]])
		_route_lengths[i] = 0.0
		net_positions[i] = _hole_positions[_from_hole]
		net_yaws[i] = 0.0
		_smoothed_ready[i] = false
		_gnomes[i].set_shown(false)


func _collect_gnomes() -> Array[Gnome]:
	var result: Array[Gnome] = []
	for child: Node in get_children():
		if child is Gnome:
			result.append(child as Gnome)
	return result


## Outward direction of a hole, in this node's space: holes face into the room on +Z.
func hole_normal(hole: int) -> Vector3:
	return _holes[hole].basis.z.normalized()


func is_resting() -> bool:
	return _resting


## Server only: kills gnome `index` if it is out. It stays hidden, and is not freed,
## until the burrow's next outing.
func kill_gnome(index: int) -> void:
	if not multiplayer.is_server() or index < 0 or index >= _gnomes.size():
		return
	if net_shown & (1 << index) == 0:
		return
	_alive[index] = false
	net_shown &= ~(1 << index)
	_explode.rpc(index)


@rpc("authority", "call_local", "reliable")
func _explode(index: int) -> void:
	if index < 0 or index >= _gnomes.size():
		return
	var gnome := _gnomes[index]
	MeshExplosion.spawn(gnome, gnome.body)
	gnome.set_shown(false)


## Server only: picks the next hole and plans every gnome's own wandering route to it.
func start_outing() -> void:
	_to_hole = GnomeMath.next_hole_index(_from_hole, _hole_positions, randf())
	for i in _gnomes.size():
		_alive[i] = true
		_avoid[i] = Vector3.ZERO
		_routes[i] = _plan_route(_from_hole, _to_hole)
		_route_lengths[i] = GnomeMath.path_total_length(_routes[i])
		_speeds[i] = GnomeMath.leg_speed(ROAM_SPEED, randf())
		_delays[i] = i * GnomeMath.EMERGE_STAGGER + randf() * 0.4
	_elapsed = 0.0
	_resting = false


func _plan_route(from_hole: int, to_hole: int) -> PackedVector3Array:
	var stops: Array[Vector3] = [_hole_positions[from_hole]]
	var count := randi_range(GnomeMath.WANDER_STOPS_MIN, GnomeMath.WANDER_STOPS_MAX)
	for s in count:
		var t := float(s + 1) / float(count + 1)
		var anchor := _hole_positions[from_hole].lerp(_hole_positions[to_hole], t)
		var normal := hole_normal(from_hole if t < 0.5 else to_hole)
		stops.append(_wander_point(anchor, normal))
	stops.append(_hole_positions[to_hole])
	var route := PackedVector3Array([stops[0]])
	for s in range(1, stops.size()):
		var leg := _nav_path(stops[s - 1], stops[s])
		for p in range(1, leg.size()):
			route.append(leg[p])
	# Hole positions are authored at floor level; everything between them sits on the
	# floor collision below it.
	for p in range(1, route.size() - 1):
		route[p] = snap_to_floor(route[p])
	return route


## Local point moved onto the floor collision directly below or just above it; left
## unchanged when there is no floor within FLOOR_SNAP_RANGE. Players and other moving
## bodies are skipped so gnomes never climb onto them.
func snap_to_floor(local: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var point := to_global(local)
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * FLOOR_SNAP_RANGE, point + Vector3.DOWN * FLOOR_SNAP_RANGE, FLOOR_LAYER
	)
	for attempt in 4:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return local
		if hit["collider"] is PhysicsBody3D and not hit["collider"] is StaticBody3D:
			query.exclude = query.exclude + [hit["rid"]]
			continue
		return to_local(hit["position"] as Vector3)
	return local


## A random reachable spot in front of `anchor`, snapped onto the navmesh, or a spot
## just in front of the hole when the navmesh has nothing on the same floor there.
func _wander_point(anchor: Vector3, normal: Vector3) -> Vector3:
	var offset := Vector2(randf_range(-1.0, 1.0), randf())
	var candidate := GnomeMath.wander_target(anchor, normal, offset)
	var fallback := anchor + normal * GnomeMath.WANDER_MIN_DEPTH
	var map := get_world_3d().get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return fallback
	var goal := to_global(candidate) + Vector3.UP * NAV_FLOOR_OFFSET
	var closest := NavigationServer3D.map_get_closest_point(map, goal)
	if closest.distance_to(goal) > GnomeMath.WANDER_RADIUS * 0.5:
		return fallback
	var local := to_local(closest) + Vector3.DOWN * NAV_FLOOR_OFFSET
	if absf(local.y - anchor.y) > MAX_WANDER_RISE:
		return fallback
	return local


## Local-space navmesh route between two floor points; a straight line when the
## navmesh has no route (or hasn't registered yet).
func _nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var map := get_world_3d().get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return PackedVector3Array([from, to])
	var lift := Vector3.UP * NAV_FLOOR_OFFSET
	var path := NavigationServer3D.map_get_path(
		map, to_global(from) + lift, to_global(to) + lift, true
	)
	var local := PackedVector3Array([from])
	if path.size() >= 2:
		for p in range(1, path.size() - 1):
			local.append(to_local(path[p]) - lift)
	local.append(to)
	return local


func _physics_process(delta: float) -> void:
	# Checked every frame: authority is only known once networking has started.
	if not multiplayer.is_server():
		return
	if _resting:
		_rest_timer -= delta
		if _rest_timer <= 0.0:
			start_outing()
		return
	_sense_timer -= delta
	if _sense_timer <= 0.0:
		_sense_timer = SENSE_INTERVAL
		_sense_obstacles()
	_elapsed += delta
	var all_home := true
	var shown := 0
	var avoid_t := 1.0 - exp(-AVOID_SMOOTHING * delta)
	for i in _gnomes.size():
		var length := _route_lengths[i]
		var distance := GnomeMath.route_distance(_elapsed, _delays[i], _speeds[i])
		if distance < length:
			all_home = false
		var target := GnomeMath.position_on_path(_routes[i], distance)
		var dir := GnomeMath.direction_on_path(_routes[i], distance)
		# Fade the sidestep out near the holes so gnomes still line up with the doors.
		var near_door := clampf(minf(distance, length - distance), 0.0, 1.0)
		var push := GnomeMath.avoidance_offset(target, dir, _obstacles) * near_door
		_avoid[i] = _avoid[i].lerp(push, avoid_t)
		net_positions[i] = target + _avoid[i]
		net_yaws[i] = GnomeMath.facing_yaw(dir + _avoid[i] * 0.5)
		if _alive[i] and GnomeMath.gnome_visible(distance, length):
			shown |= 1 << i
	net_shown = shown
	if all_home:
		_resting = true
		_rest_timer = randf_range(GnomeMath.REST_MIN, GnomeMath.REST_MAX)
		_from_hole = _to_hole


## Players, NPCs, frogs and other killables (except gnomes) that gnomes steer around.
func _sense_obstacles() -> void:
	_obstacles.clear()
	for group: StringName in [&"players", &"killable"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var obstacle := node as Node3D
			if obstacle == null or obstacle is Gnome or not obstacle.is_visible_in_tree():
				continue
			_obstacles.append(to_local(obstacle.global_position))


func _process(delta: float) -> void:
	var is_server := multiplayer.is_server()
	var lerp_t := 1.0 - exp(-REMOTE_SMOOTHING * delta)
	var count := mini(_gnomes.size(), net_positions.size())
	for i in count:
		var gnome := _gnomes[i]
		var shown := net_shown & (1 << i) != 0
		if is_server or not _smoothed_ready[i] or not gnome.is_shown():
			gnome.position = net_positions[i]
			gnome.rotation.y = net_yaws[i]
			_smoothed_ready[i] = true
		else:
			gnome.position = gnome.position.lerp(net_positions[i], lerp_t)
			gnome.rotation.y = lerp_angle(gnome.rotation.y, net_yaws[i], lerp_t)
		gnome.set_shown(shown)
	_swing_flaps(delta)


## Cosmetic: each doggy-door flap swings open while a gnome passes through it.
func _swing_flaps(delta: float) -> void:
	var flap_t := 1.0 - exp(-FLAP_SMOOTHING * delta)
	for h in _holes.size():
		var flap := _holes[h].get_node_or_null(^"Flap") as Node3D
		if flap == null:
			continue
		var nearest := INF
		for gnome: Gnome in _gnomes:
			if gnome.is_shown():
				nearest = minf(nearest, gnome.position.distance_to(_hole_positions[h]))
		var target := -GnomeMath.flap_angle(nearest)
		flap.rotation.x = lerpf(flap.rotation.x, target, flap_t)
