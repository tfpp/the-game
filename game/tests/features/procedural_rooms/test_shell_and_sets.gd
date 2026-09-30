extends GutTest

const Layout := preload("res://features/procedural_rooms/example_layout.gd")
const Showcase := preload("res://features/procedural_rooms/showcase.gd")
const Shell := preload("res://features/procedural_rooms/shell_mesh.gd")
const PLAYER := preload("res://core/player/player.tscn")
var _world: Node3D


func before_each() -> void:
	var host := Node3D.new()
	add_child_autofree(host)
	_world = Layout.build(host)


func test_structure_has_indexed_shared_vertices_and_no_box_walls() -> void:
	var structure := _world.get_node("Structure")
	var pool: PackedVector3Array = structure.get_meta("vertex_pool")
	var unique: Dictionary[Vector3, bool] = {}
	for point: Vector3 in pool:
		assert_false(unique.has(point), "Canonical vertices must be unique")
		unique[point] = true
	var triangles: Dictionary[String, bool] = {}
	for mesh: MeshInstance3D in structure.find_children("*", "MeshInstance3D", true, false):
		assert_true(mesh.mesh is ArrayMesh)
		var arrays := mesh.mesh.surface_get_arrays(0)
		assert_eq(arrays[Mesh.ARRAY_VERTEX], pool)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert_gt(indices.size(), 0)
		for index: int in range(0, indices.size(), 3):
			var ids: Array[int] = [indices[index], indices[index + 1], indices[index + 2]]
			ids.sort()
			assert_false(triangles.has(str(ids)), "No duplicate structural face")
			triangles[str(ids)] = true


func test_rendered_face_edges_have_no_unjoined_vertices() -> void:
	var structure := _world.get_node("Structure")
	var pool: PackedVector3Array = structure.get_meta("vertex_pool")
	var groups: Dictionary = structure.get_meta("groups")
	var used: Dictionary[int, bool] = {}
	for indices: PackedInt32Array in groups.values():
		for index: int in indices:
			used[index] = true
	for indices: PackedInt32Array in groups.values():
		for index: int in range(0, indices.size(), 3):
			for side: int in 3:
				var a := pool[indices[index + side]]
				var b := pool[indices[index + (side + 1) % 3]]
				var edge := b - a
				for vertex: int in used:
					var point := pool[vertex]
					var t := (point - a).dot(edge) / edge.length_squared()
					if t > 0.00001 and t < 0.99999:
						assert_gt((a + edge * t).distance_to(point), 0.00001, "No edge T-junction")


func test_door_blocks_closed_clears_open_and_validates_use() -> void:
	Showcase.decorate(_world)
	var door := _world.get_node("Doors/RampDoor") as ProceduralSlidingDoor
	var player := PLAYER.instantiate() as Player
	_world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.position = Vector3(-20, 0.95, 6)
	player.net_position = player.position
	await wait_physics_frames(3)
	assert_true(_blocked(door))
	var outcome := door.entity._evaluate(1, &"use", {})
	assert_eq(outcome, NetworkedEntity.Result.ACCEPTED)
	await wait_physics_frames(30)
	assert_true(door.net_open)
	assert_false(_blocked(door))
	player.position = Vector3(-20, 0.95, 8)
	player.net_position = player.position
	assert_eq(door.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	player.net_position = Vector3(100, 1, 100)
	assert_eq(door.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	player.free()


func test_sets_preserve_open_socket_lanes() -> void:
	Showcase.decorate(_world)
	for door: ProceduralSlidingDoor in get_tree().get_nodes_in_group(&"prototype_doors"):
		door.net_open = true
	await wait_physics_frames(30)
	var space := _world.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	for kind: String in ["Ramp", "Stairs", "Sewer"]:
		var room := _world.get_node("Routes/" + kind + "/Arrival") as Node3D
		assert_not_null(room.get_node("SetPieces"))
		for side: float in [-0.7, 0, 0.7]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform = Transform3D(Basis.IDENTITY, room.to_global(Vector3(side, 0.9544, 1)))
			query.motion = room.global_basis.z * 7.4
			assert_almost_eq(
				space.cast_motion(query)[0], 1.0, 0.001, "Set pieces keep centre lane open"
			)


func _blocked(door: ProceduralSlidingDoor) -> bool:
	var point := door.to_global(Vector3(0.4, 1.4, 0))
	var axis := door.global_basis.z
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(point - axis, point + axis)
	)
	return not hit.is_empty()
