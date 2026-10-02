extends GutTest
## New players, fall recovery and combat respawns start in the Golden Crown in front
## of the elevator (Phase 1 task D2), on clear floor inside the safe zone.

const FEATURE := preload("res://features/crown_spawn/feature.tscn")
const STARTER := preload("res://features/starter_room/feature.tscn")
const ROOM := preload("res://world/room.tscn")
## Elevator doorway threshold in the casino (features/elevator/README.md).
const ELEVATOR_DOOR := Vector3(0, 0, -20)
const JITTER := 3.0


class SpawnProbe:
	extends Game

	func _ready() -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass


func _probe_game() -> Game:
	var game := SpawnProbe.new()
	for title: String in ["Features", "Players", "PlayerSpawner", "Room"]:
		var child: Node = MultiplayerSpawner.new() if title == "PlayerSpawner" else Node3D.new()
		child.name = title
		game.add_child(child)
	var fallback := Marker3D.new()
	fallback.name = "Spawn"
	fallback.position = Vector3(10, 1, 10)
	game.get_node("Room").add_child(fallback)
	add_child_autofree(game)
	return game


func test_join_and_respawn_use_the_crown_marker_not_the_operations_garage() -> void:
	add_child_autofree(STARTER.instantiate())
	add_child_autofree(FEATURE.instantiate())
	var game := _probe_game()
	var combat := Combat.new()
	add_child_autofree(combat)
	var spawns := get_tree().get_nodes_in_group(&"player_spawn")
	assert_eq(spawns.size(), 1, "Only one feature supplies player_spawn")
	var marker := spawns[0] as Marker3D
	assert_eq(marker.get_parent().name, &"CrownSpawn")
	for i: int in 20:
		for position: Vector3 in [game._spawn_position(), combat._respawn_position()]:
			var offset := position - marker.global_position
			assert_lte(absf(offset.x), JITTER)
			assert_lte(absf(offset.z), JITTER)
			assert_eq(offset.y, 0.0)


func test_spawn_faces_the_elevator_close_by() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var marker := feature.get_node("Spawn") as Marker3D
	var to_door := ELEVATOR_DOOR - marker.global_position
	# Players spawn facing -Z, straight at the doors, and outside the threshold.
	assert_lte(to_door.z, -JITTER - 1.0)
	assert_lt(Vector2(to_door.x, to_door.z).length(), 9.0)
	assert_almost_eq(to_door.x, 0.0, 0.01)


func test_spawn_is_inside_the_crown_safe_zone() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	add_child_autofree(load("res://features/safe_zone/feature.tscn").instantiate())
	await wait_physics_frames(2)
	var marker := feature.get_node("Spawn") as Marker3D
	assert_true(SafeZone.covers(get_tree(), marker.global_position))


func test_entire_spawn_square_has_floor_and_capsule_clearance() -> void:
	var room := ROOM.instantiate() as Node3D
	add_child_autofree(room)
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	await wait_physics_frames(3)
	var marker := feature.get_node("Spawn") as Marker3D
	var space := room.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	for dx: float in [-JITTER, -1.5, 0.0, 1.5, JITTER]:
		for dz: float in [-JITTER, -1.5, 0.0, 1.5, JITTER]:
			var origin := marker.global_position + Vector3(dx, 0, dz)
			var ray := PhysicsRayQueryParameters3D.create(origin, origin - Vector3.UP * 3)
			var hit := space.intersect_ray(ray)
			assert_false(hit.is_empty(), str(origin))
			if not hit.is_empty():
				assert_almost_eq((hit["position"] as Vector3).y, 0.0, .03, str(origin))
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform.origin = origin + Vector3.UP * .05
			assert_true(space.intersect_shape(query).is_empty(), str(origin))
