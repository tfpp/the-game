extends GutTest

const Radar := preload("res://features/radar/radar.gd")
const Geometry := preload("res://features/radar/radar_geometry.gd")

var _world: Node3D
var _radar: Control


func before_each() -> void:
	_world = Node3D.new()
	add_child(_world)
	_radar = Radar.new()
	_radar._height = 1.0
	_radar._index_geometry(_world)


func after_each() -> void:
	_radar.free()
	_world.free()


func _box(parent: Node) -> CollisionShape3D:
	var body := StaticBody3D.new()
	parent.add_child(body)
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	collider.add_to_group(&"radar_geometry")
	body.add_child(collider)
	return collider


func _nearby() -> Array[Node3D]:
	var result: Array[Node3D] = []
	_radar._collect(_world, result)
	return result


func test_streamed_subtree_add_remove_and_reentry_updates_map_sources() -> void:
	var content := Node3D.new()
	var floor_shape := _box(content)
	_world.add_child(content)
	assert_has(_nearby(), floor_shape)
	_world.remove_child(content)
	assert_true(_nearby().is_empty(), "Removed room must disappear before queue_free")
	assert_true(_radar._sources.is_empty())
	_world.add_child(content)
	assert_has(_nearby(), floor_shape, "Reentering the tree must register again")
	content.free()
	assert_true(_nearby().is_empty())
	assert_true(_radar._sources.is_empty(), "Do not retain freed room nodes")


func test_existing_scene_is_indexed_once_and_unrelated_nodes_are_ignored() -> void:
	var shape := _box(_world)
	_radar._index_geometry(_world)
	for index: int in 200:
		_world.add_child(Node3D.new())
	assert_eq(_radar._sources.size(), 1)
	assert_eq(_nearby(), [shape])
	assert_eq(_nearby(), [shape], "Repeated scans preserve membership without duplicate sources")


func test_runtime_group_disable_and_shape_changes_remain_visible_to_scan() -> void:
	var shape := _box(_world)
	assert_has(_nearby(), shape)
	shape.remove_from_group(&"radar_geometry")
	assert_true(_nearby().is_empty())
	shape.add_to_group(&"radar_geometry")
	shape.disabled = true
	assert_true(_nearby().is_empty())
	shape.disabled = false
	shape.shape = null
	assert_true(_nearby().is_empty())
	var mesh_shape := ConcavePolygonShape3D.new()
	mesh_shape.set_faces(BoxMesh.new().get_faces())
	shape.shape = mesh_shape
	assert_has(_nearby(), shape)


func test_transformed_reparented_geometry_uses_current_world_bounds() -> void:
	var shape := _box(_world)
	var room := Node3D.new()
	_world.add_child(room)
	shape.get_parent().reparent(room)
	room.position = Vector3(200, 8, -600)
	room.rotation.y = PI / 2
	assert_true(_nearby().is_empty())
	_radar._center = Vector2(200, -600)
	_radar._height = 9.0
	assert_has(_nearby(), shape)
	room.position.y = 20
	assert_true(_nearby().is_empty(), "Current height matters even without scene membership change")


func test_csg_combination_maps_root_only_and_can_be_root_of_index() -> void:
	var csg := CSGBox3D.new()
	csg.use_collision = true
	_world.add_child(csg)
	var child := CSGBox3D.new()
	child.use_collision = true
	csg.add_child(child)
	var collider := _box(csg)
	assert_has(_nearby(), csg)
	assert_does_not_have(_nearby(), child)
	assert_does_not_have(_nearby(), collider)
	var result: Array[Node3D] = []
	_radar._collect(csg, result)
	assert_eq(result, [csg])
	csg.use_collision = false
	result.clear()
	_radar._collect(csg, result)
	assert_true(result.is_empty())


func test_unloaded_room_is_skipped_during_pending_geometry_build() -> void:
	var content := Node3D.new()
	var floor_shape := _box(content)
	_world.add_child(content)
	_radar._pending = _nearby()
	assert_has(_radar._pending, floor_shape)
	_radar._building = Geometry.new()
	_radar._build_height = 1.0
	_world.remove_child(content)
	_radar._build_step()
	assert_true(_radar.walls().is_empty())
	assert_true(_radar._geometry.floors.is_empty())
	content.free()


func test_other_scene_and_private_icon_viewport_geometry_is_not_registered() -> void:
	var elsewhere := Node3D.new()
	add_child(elsewhere)
	_box(elsewhere)
	assert_true(_radar._sources.is_empty())
	elsewhere.free()
