class_name RoomVisibility
extends Node
## The server assigns each player a scene-authored room. On that player's peer,
## Godot streams its room content and clips rendering at the room's far edge.

const ASSIGN_INTERVAL_SEC := 0.1

var _elapsed := 0.0
var _assigned: Dictionary = {}
var _current_room := NodePath("")
var _current_bounds := AABB()
var _camera: Camera3D
var _original_far := 0.0
var _casino_bounds := AABB()


func _ready() -> void:
	add_to_group(&"room_visibility")
	_casino_bounds = _world_bounds(get_parent().get_parent().get_node_or_null("Room") as Node3D)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_elapsed += delta
	if _elapsed < ASSIGN_INTERVAL_SEC:
		return
	_elapsed = 0.0
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null:
			continue
		var peer := player.get_multiplayer_authority()
		var room := _room_at(player.net_position)
		var path: NodePath = room["path"]
		if _assigned.get(peer, NodePath("_unassigned")) == path:
			continue
		_assigned[peer] = path
		assign_room.rpc_id(peer, path, room["bounds"])


func _process(_delta: float) -> void:
	if _current_bounds.size == Vector3.ZERO:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	if camera != _camera:
		_camera = camera
		_original_far = camera.far
	# The scene's own bounds determine the far plane. The renderer culls all
	# geometry beyond it, including visuals from other always-loaded features.
	camera.far = far_for_bounds(_current_bounds, camera.global_position, camera.near)


static func far_for_bounds(bounds: AABB, camera_position: Vector3, near: float) -> float:
	var farthest := near
	for x: int in 2:
		for y: int in 2:
			for z: int in 2:
				var corner := bounds.position + bounds.size * Vector3(x, y, z)
				farthest = maxf(farthest, camera_position.distance_to(corner))
	return farthest + near


func _room_at(position: Vector3) -> Dictionary:
	var best := {"path": NodePath(""), "bounds": AABB()}
	var best_volume := INF
	for node: Node in get_tree().get_nodes_in_group(&"streamed_rooms"):
		var room := node as StreamedRoom
		if room == null or not room.contains(position):
			continue
		var bounds := room.global_bounds()
		var volume := bounds.get_volume()
		if volume < best_volume:
			best = {"path": room.get_path(), "bounds": bounds}
			best_volume = volume
	for node: Node in get_tree().get_nodes_in_group(GpsDestination.GROUP):
		var destination := node as GpsDestination
		if destination == null or destination.area.size == Vector3.ZERO:
			continue
		if not destination.area.has_point(position):
			continue
		var volume := destination.area.get_volume()
		if volume < best_volume:
			best = {"path": destination.get_path(), "bounds": destination.area}
			best_volume = volume
	if best_volume < INF:
		return best
	return {"path": NodePath(""), "bounds": _casino_bounds}


func _world_bounds(world: Node3D) -> AABB:
	if world == null:
		return AABB()
	var boxes: Array[AABB] = []
	_collect_bounds(world, boxes)
	if boxes.is_empty():
		return AABB()
	var bounds := boxes[0]
	for box: AABB in boxes:
		bounds = bounds.merge(box)
	return bounds


func _collect_bounds(node: Node, boxes: Array[AABB]) -> void:
	if node is GeometryInstance3D:
		var geometry := node as GeometryInstance3D
		if geometry.visible:
			var box := geometry.global_transform * geometry.get_aabb()
			if box.size != Vector3.ZERO:
				boxes.append(box)
	for child: Node in node.get_children():
		_collect_bounds(child, boxes)


@rpc("authority", "call_local", "reliable")
func assign_room(path: NodePath, bounds: AABB) -> void:
	_current_room = path
	_current_bounds = bounds
	for node: Node in get_tree().get_nodes_in_group(&"streamed_rooms"):
		var room := node as StreamedRoom
		if room == null:
			continue
		if room.get_path() == path:
			room.load_room()
		else:
			room.unload_room()


func _on_peer_disconnected(peer: int) -> void:
	_assigned.erase(peer)


func _on_mode_changed(_mode: Network.Mode) -> void:
	_assigned.clear()
	_current_room = NodePath("")
	_current_bounds = AABB()
	if is_instance_valid(_camera):
		_camera.far = _original_far
	_camera = null
