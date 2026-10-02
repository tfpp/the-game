class_name Gps
extends Node3D
## Client-side GPS. Press P (or pick GPS in the Esc menu) to raise the phone, choose a
## place, and follow the route on the radar and the direction banner. Nothing is
## networked: routes are private to each player and read only local scene state.

const ACTION := &"gps"
const ROUTE_COLOR := Color("c86bff")
const REFRESH_SEC := 0.4
const ARRIVED_HOLD_SEC := 4.0
## The walkable path is re-planned after moving this far or this long; in between,
## only its first point follows the player (planning costs a few milliseconds).
const REPLAN_DISTANCE := 2.0
const REPLAN_SEC := 3.0

var _catalog: GpsCatalog
var _phone: GpsPhone
var _target: GpsDestination
var _path := PackedVector2Array()
var _door := ""
var _text := ""
var _refresh := 0.0
var _arrived_left := 0.0
var _planned_at := Vector2(INF, INF)
var _planned_age := INF
var _planned_goal := Vector2(INF, INF)


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER:
		set_process(false)
		return
	_catalog = GpsCatalog.new()
	add_child(_catalog)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_P
	Controls.ensure_action(ACTION, [key])
	add_to_group(&"radar_overlays")
	add_to_group(&"esc_menu_links")
	_phone = GpsPhone.new()
	_phone.name = "Phone"
	add_child(_phone)
	_phone.destination_chosen.connect(start_route)
	_phone.route_cleared.connect(clear_route)


func _unhandled_input(event: InputEvent) -> void:
	if _phone == null or not event.is_action_pressed(ACTION) or event.is_echo():
		return
	if _phone.is_open():
		get_viewport().set_input_as_handled()
		_phone.close()
	elif Controls.gameplay_active():
		get_viewport().set_input_as_handled()
		esc_menu_open()


func esc_menu_label() -> String:
	return "GPS"


func esc_menu_icon() -> Texture2D:
	return preload("res://assets/kenney/game-icons/PNG/White/1x/target.png")


func esc_menu_open() -> void:
	var entries := destinations()
	if not is_instance_valid(_target) or not _target.available():
		clear_route()
	_phone.open(entries, _target)


## Every GPS destination in the world, sorted by label.
func destinations() -> Array[GpsDestination]:
	_catalog.refresh()
	var result: Array[GpsDestination] = []
	for node: Node in get_tree().get_nodes_in_group(GpsDestination.GROUP):
		if node is GpsDestination and node.label != "" and node.available():
			result.append(node)
	result.sort_custom(func(a: GpsDestination, b: GpsDestination) -> bool: return a.label < b.label)
	return result


func start_route(destination: GpsDestination) -> void:
	if not is_instance_valid(destination) or not destination.available():
		return
	_target = destination
	_arrived_left = 0.0
	_refresh = 0.0
	_path = PackedVector2Array()
	_planned_goal = Vector2(INF, INF)


func clear_route() -> void:
	_target = null
	_path = PackedVector2Array()
	_text = ""
	if _phone != null:
		_phone.set_guidance("", 0.0, "")


func target() -> GpsDestination:
	return _target


func route() -> PackedVector2Array:
	return _path


func _process(delta: float) -> void:
	if not is_instance_valid(_target) or not _target.available():
		clear_route()
	if _target == null:
		return
	var player := get_tree().get_first_node_in_group(&"local_player") as Node3D
	if player == null:
		return
	if _arrived_left > 0.0 and _target.tracks_source:
		if not GpsRoute.arrived(player.global_position, _target.destination_position()):
			_arrived_left = 0.0
	if _arrived_left > 0.0:
		_arrived_left -= delta
		if _arrived_left <= 0.0:
			clear_route()
		return
	_refresh -= delta
	_planned_age += delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SEC
		_update_route(player)
	_phone.set_guidance(_text, _heading(player), _target.label)


func _update_route(player: Node3D) -> void:
	var from := player.global_position
	var hop := GpsRoute.next_hop(regions(), links(), from, _target.destination_position())
	_door = hop["door"]
	var goal: Vector3 = hop["position"]
	var start := Vector2(from.x, from.z)
	var end := Vector2(goal.x, goal.z)
	if (
		_path.size() >= 2
		and end.distance_to(_planned_goal) < REPLAN_DISTANCE
		and start.distance_to(_planned_at) < REPLAN_DISTANCE
		and _planned_age < REPLAN_SEC
	):
		_path[0] = start
	else:
		_plan(start, end)
	if _door == "" and GpsRoute.arrived(from, _target.destination_position()):
		_text = "Arrived at %s" % _target.label
		_arrived_left = ARRIVED_HOLD_SEC
		_phone.set_guidance(_text, 0.0, _target.label)
		return
	_text = GpsRoute.instruction(_path, _door, _target.label)
	var rise := _target.destination_position().y - from.y
	if _door == "" and absf(rise) > 2.5 and start.distance_to(end) < 12.0:
		_text = "Go %s to %s" % ["upstairs" if rise > 0.0 else "downstairs", _target.label]


func _plan(start: Vector2, end: Vector2) -> void:
	_planned_at = start
	_planned_goal = end
	_planned_age = 0.0
	var radar := get_tree().get_first_node_in_group(&"radar")
	var walls := PackedVector2Array()
	if radar != null and radar.has_method(&"walls") and (radar as CanvasItem).visible:
		walls = radar.call(&"walls")
	if walls.is_empty():
		_path = PackedVector2Array([start, end])
	else:
		_path = GpsRoute.grid_path(walls, start, end)


## Angle (radians, clockwise) from the player's facing to the next route point.
func _heading(player: Node3D) -> float:
	if _path.size() < 2:
		return 0.0
	var start := Vector2(player.global_position.x, player.global_position.z)
	var next := _path[1] if _path[1].distance_to(start) > 0.5 or _path.size() < 3 else _path[2]
	var yaw := float(player.get("net_yaw"))
	return relative_heading(yaw, next - start)


## Clockwise angle from facing `yaw` (forward is -Z) to ground direction `to` (x, z).
static func relative_heading(yaw: float, to: Vector2) -> float:
	var forward := Vector2(-sin(yaw), -cos(yaw))
	return forward.angle_to(to)


## World-space extents that doors connect: streamed rooms and closed-off areas.
func regions() -> Array[AABB]:
	var result: Array[AABB] = []
	for node: Node in get_tree().get_nodes_in_group(&"streamed_rooms"):
		if node.has_method(&"global_bounds"):
			result.append(node.call(&"global_bounds"))
	for node: Node in get_tree().get_nodes_in_group(GpsDestination.GROUP):
		var destination := node as GpsDestination
		if destination != null and destination.area.has_volume():
			result.append(destination.area)
	return result


## Every door (`GarageDoor` and subclasses such as `RoomDoor`) as a routing link.
func links() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(&"interactables"):
		var door := node as GarageDoor
		if door == null or door.destination.is_empty() or DevGate.blocks(door):
			continue
		var arrival := door.get_node_or_null(door.destination) as Node3D
		if arrival == null:
			continue
		(
			result
			. append(
				{
					"from": door.global_position,
					"to": arrival.global_position,
					"label": door.door_label,
				}
			)
		)
	return result


func draw_radar_overlay(radar: Control) -> void:
	if _target == null or _path.size() < 2:
		return
	var points := PackedVector2Array()
	for point: Vector2 in _path:
		points.append(radar.call(&"map_point", Vector3(point.x, 0.0, point.y)))
	radar.draw_polyline(points, Color(0, 0, 0, 0.5), 5.0, true)
	radar.draw_polyline(points, ROUTE_COLOR, 3.0, true)
	var end := points[points.size() - 1]
	radar.draw_circle(end, 5.0, ROUTE_COLOR)
	radar.draw_circle(end, 2.0, Color.WHITE)
