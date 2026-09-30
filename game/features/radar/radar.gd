extends Control
## Desktop-only, north-up local floor plan. Reads geometry and replicated players;
## no extra camera, rendering viewport, networking or physics queries.

const Geometry := preload("res://features/radar/radar_geometry.gd")
const RANGE := 38.0
const INK := Color("c6d7d7")
const ACCENT := Color("7ce8c2")
const FLOOR_COLOR := Color("2b4148")
const WALL_COLOR := Color("819698")
const ROOTS_PER_FRAME := 16
## Nodes in this group draw on the map: `draw_radar_overlay(radar: Control)`, using
## `map_point()` and the radar's draw calls (the GPS route does this).
const OVERLAY_GROUP := &"radar_overlays"

var _mobile := false
var _refresh := 0.0
var _player: Node3D
var _center := Vector2.ZERO
var _height := 0.0
var _pending: Array[Node3D] = []
var _building: RadarGeometry
var _geometry: RadarGeometry
var _floor_mesh: ArrayMesh
var _build_center := Vector2(INF, INF)
var _build_height := INF
var _roots: Array[Node3D] = []
# Index only possible map geometry; do not rediscover all props/avatars every second.
var _sources: Dictionary[int, Node3D] = {}
var _source_root: Node
var _source_tree: SceneTree


func _ready() -> void:
	_mobile = OS.has_feature("android") or OS.has_feature("ios")
	if OS.has_feature("web"):
		_mobile = bool(
			JavaScriptBridge.eval(
				(
					"/Android|iPhone|iPad|iPod/i.test(navigator.userAgent) || "
					+ "(navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)"
				)
			)
		)
	add_to_group(&"radar")
	visible = false
	if _mobile or Network.mode == Network.Mode.SERVER:
		set_process(false)
	else:
		_watch_geometry.call_deferred()


static func desktop_visible(mobile: bool, touch: bool, server: bool) -> bool:
	return not mobile and not touch and not server


func _process(delta: float) -> void:
	_player = get_tree().get_first_node_in_group(&"local_player") as Node3D
	visible = desktop_visible(
		_mobile, Controls.touch_visible(), Network.mode == Network.Mode.SERVER
	)
	visible = visible and is_instance_valid(_player)
	if not visible:
		return
	_center = Vector2(_player.global_position.x, _player.global_position.z)
	# Half-metre bands prevent rebuilding every frame while walking on a ramp.
	_height = snappedf(_player.global_position.y, 0.5)
	_refresh -= delta
	if _refresh <= 0.0 and _pending.is_empty():
		_refresh = 1.0
		var nearby: Array[Node3D] = []
		_collect(get_tree().current_scene, nearby)
		if (
			nearby != _roots
			or _center.distance_to(_build_center) > 12.0
			or _height != _build_height
		):
			_roots = nearby
			_pending = nearby.duplicate()
			_building = Geometry.new()
			# Never display the previous room after a door teleport.
			if _center.distance_to(_build_center) > RANGE or absf(_height - _build_height) > 4.0:
				_geometry = null
				_floor_mesh = null
			_build_center = _center
			_build_height = _height
	_build_step()
	queue_redraw()


func _watch_geometry() -> void:
	if is_inside_tree():
		_index_geometry(get_tree().current_scene)


func _index_geometry(root: Node) -> void:
	if root == null:
		return
	_source_root = root
	_sources.clear()
	if _source_tree == null:
		_source_tree = root.get_tree()
		_source_tree.node_added.connect(_source_added)
		_source_tree.node_removed.connect(_source_removed)
	_index_branch(root)


func _index_branch(node: Node) -> void:
	_source_added(node)
	for child: Node in node.get_children():
		_index_branch(child)


func _source_added(node: Node) -> void:
	if not (node is CSGShape3D or node is CollisionShape3D):
		return
	if (
		is_instance_valid(_source_root)
		and (node == _source_root or _source_root.is_ancestor_of(node))
	):
		_sources[node.get_instance_id()] = node as Node3D


func _source_removed(node: Node) -> void:
	_sources.erase(node.get_instance_id())


func _collect(node: Node, result: Array[Node3D]) -> void:
	if node == null:
		return
	if not is_instance_valid(_source_root) or node != _source_root:
		_index_geometry(node)
	for source: Node3D in _sources.values():
		# A CSG subtree is represented by its root's combined mesh only.
		var parent := source.get_parent()
		var nested := false
		while parent != null:
			if parent is CSGShape3D:
				nested = true
				break
			parent = parent.get_parent()
		if not nested:
			_append_source(source, result)


func _append_source(node: Node3D, result: Array[Node3D]) -> void:
	var bounds := AABB()
	var candidate := false
	if node is CSGShape3D:
		var shape := node as CSGShape3D
		if not shape.is_root_shape() or not shape.use_collision:
			return
		bounds = shape.global_transform * shape.get_aabb()
		candidate = true
	elif node is CollisionShape3D and node.is_in_group(&"radar_geometry"):
		var collider := node as CollisionShape3D
		if not collider.disabled and collider.shape != null:
			if collider.shape is BoxShape3D:
				var box := collider.shape as BoxShape3D
				bounds = collider.global_transform * AABB(-box.size * 0.5, box.size)
				candidate = true
			elif collider.shape is ConcavePolygonShape3D:
				bounds = collider.global_transform * collider.shape.get_debug_mesh().get_aabb()
				candidate = true
	if candidate:
		var area := Rect2(
			Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)
		)
		if (
			area.grow(RANGE + 16.0).has_point(_center)
			and bounds.position.y < _height
			and bounds.end.y > _height - 4.0
		):
			result.append(node as Node3D)
		return


func _build_step() -> void:
	if _building == null:
		return
	for index: int in mini(ROOTS_PER_FRAME, _pending.size()):
		var shape: Node3D = _pending.pop_back()
		if not is_instance_valid(shape) or not shape.is_inside_tree():
			continue
		if shape is CollisionShape3D:
			# Generated worlds mark their structural collision, omitting decorative
			# mouldings and furniture meshes from the floor plan.
			var collider := shape as CollisionShape3D
			if collider.shape is ConcavePolygonShape3D:
				_building.append_faces(
					(collider.shape as ConcavePolygonShape3D).get_faces(),
					shape.global_transform,
					_build_height
				)
			elif collider.shape is BoxShape3D:
				var box := BoxMesh.new()
				box.size = (collider.shape as BoxShape3D).size
				_building.append_mesh(box, shape.global_transform, _build_height)
		else:
			var meshes := (shape as CSGShape3D).get_meshes()
			if meshes.size() == 2:
				_building.append_mesh(
					meshes[1] as Mesh,
					shape.global_transform * (meshes[0] as Transform3D),
					_build_height
				)
	if _pending.is_empty():
		_geometry = _building
		_floor_mesh = _geometry.floor_mesh()
		_building = null


## Wall segments (pairs of ground-plane points) of the current storey slice, or
## empty while nothing has been built. Only desktop clients build them.
func walls() -> PackedVector2Array:
	return _geometry.walls if _geometry != null else PackedVector2Array()


func map_point(world_position: Vector3) -> Vector2:
	return size * 0.5 + (Vector2(world_position.x, world_position.z) - _center) * _map_scale()


func _map_scale() -> float:
	return size.x / (RANGE * 2.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101e27"))
	var scale_factor := _map_scale()
	var midpoint := size * 0.5
	for grid: int in range(-4, 5):
		var offset := float(grid) * 10.0 * scale_factor
		draw_line(
			Vector2(midpoint.x + offset, 0), Vector2(midpoint.x + offset, size.y), Color("1a2b34")
		)
		draw_line(
			Vector2(0, midpoint.y + offset), Vector2(size.x, midpoint.y + offset), Color("1a2b34")
		)
	if _geometry != null:
		draw_set_transform(midpoint - _center * scale_factor, 0.0, Vector2.ONE * scale_factor)
		if _floor_mesh != null and _floor_mesh.get_surface_count() > 0:
			draw_mesh(_floor_mesh, null, Transform2D.IDENTITY, FLOOR_COLOR)
		if not _geometry.walls.is_empty():
			draw_multiline(_geometry.walls, WALL_COLOR, 1.2 / scale_factor, true)
		draw_set_transform(Vector2.ZERO)
	for overlay: Node in get_tree().get_nodes_in_group(OVERLAY_GROUP):
		overlay.call(&"draw_radar_overlay", self)
	_draw_players()
	draw_rect(Rect2(Vector2.ZERO, size), Color("61797e"), false, 2.0)
	draw_rect(Rect2(1, 1, size.x - 2, 25), Color(0.06, 0.12, 0.15, 0.94))
	draw_string(
		ThemeDB.fallback_font, Vector2(10, 18), "RADAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(size.x - 23, 18),
		"N",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		ACCENT
	)
	draw_rect(Rect2(1, size.y - 22, size.x - 2, 21), Color(0.06, 0.12, 0.15, 0.94))
	draw_string(
		ThemeDB.fallback_font,
		Vector2(10, size.y - 7),
		"YOU  /  NEARBY PLAYERS",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		10,
		INK
	)


func _draw_players() -> void:
	if not is_instance_valid(_player):
		return
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as Node3D
		if other == null or other == _player or other.is_queued_for_deletion():
			continue
		if absf(other.global_position.y - _player.global_position.y) > 3.0:
			continue
		var point := map_point(other.global_position)
		if Rect2(8, 30, size.x - 16, size.y - 60).has_point(point):
			draw_circle(point, 3.5, Color("f4c779"))
	var yaw := float(_player.get("net_yaw"))
	var arrow := PackedVector2Array()
	for point: Vector2 in [Vector2(0, -8), Vector2(5, 5), Vector2(0, 2), Vector2(-5, 5)]:
		arrow.append(size * 0.5 + point.rotated(-yaw))
	draw_circle(size * 0.5, 11, Color(0.48, 0.91, 0.76, 0.12))
	draw_colored_polygon(arrow, ACCENT)
