class_name RoomVisibility
extends Node
## The server assigns each player a scene-authored room. On that player's peer,
## Godot streams its room content and clips rendering at the room's far edge.

const ASSIGN_INTERVAL_SEC := 0.1

var _elapsed := 0.0
var _assigned: Dictionary = {}
var _current_room := NodePath("")
var _current_bounds := AABB()
var _pending_unloads: Array[StreamedRoom] = []
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
	_expire_preloads()
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
	# The farthest corner is the farther end of each axis. This gives the same
	# exact bound with one square root instead of measuring all eight corners.
	var low := bounds.position - camera_position
	var high := bounds.end - camera_position
	var distance_squared := (
		maxf(low.x * low.x, high.x * high.x)
		+ maxf(low.y * low.y, high.y * high.y)
		+ maxf(low.z * low.z, high.z * high.z)
	)
	return maxf(near, sqrt(distance_squared)) + near


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
			best = {"path": room.get_path(), "bounds": room.global_render_bounds()}
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
	if node is GridMap:
		var grid := node as GridMap
		if grid.visible and grid.mesh_library != null:
			for cell: Vector3i in grid.get_used_cells():
				var item := grid.get_cell_item(cell)
				var mesh := grid.mesh_library.get_item_mesh(item)
				if mesh == null:
					continue
				var transform := (
					grid.global_transform
					* Transform3D(grid.get_cell_item_basis(cell), grid.map_to_local(cell))
					* grid.mesh_library.get_item_mesh_transform(item)
				)
				boxes.append(transform * mesh.get_aabb())
	elif node is GeometryInstance3D:
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
			_pending_unloads.erase(room)
			room.load_room()
		elif room.arrival_held():
			if not _pending_unloads.has(room):
				_pending_unloads.append(room)
		else:
			_pending_unloads.erase(room)
			room.unload_room()


func _on_peer_disconnected(peer: int) -> void:
	_assigned.erase(peer)


func _on_mode_changed(_mode: Network.Mode) -> void:
	_pending_unloads.clear()
	_assigned.clear()
	_current_room = NodePath("")
	_current_bounds = AABB()
	if is_instance_valid(_camera):
		_camera.far = _original_far
	_camera = null


func _expire_preloads() -> void:
	for i: int in range(_pending_unloads.size() - 1, -1, -1):
		var room := _pending_unloads[i]
		if not is_instance_valid(room):
			_pending_unloads.remove_at(i)
		elif not room.arrival_held():
			room.unload_room()
			_pending_unloads.remove_at(i)
