extends Node
## Run against the complete game so another feature cannot obstruct an elevator.

var failures := 0


func _ready() -> void:
	var game := (load("res://main.tscn") as PackedScene).instantiate() as Game
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame
	var metro := MetroService.for_node(self)
	assert(metro != null)
	metro.set_physics_process(false)
	for player: Player in game.get_players():
		player.set_physics_process(false)
	for access: MetroAccess in metro.accesses:
		var cab := access.source
		var room := StreamedRoom.for_position(self, cab.car.global_position)
		if room != null:
			room.load_room(60000)
		cab.set_physics_process(false)
		cab.net_aperture = 1
		cab._update_doors()
		for frame: int in 4:
			await get_tree().physics_frame
		for x: float in [-0.6, 0.0, 0.6]:
			for z: float in [-2.4, -1.5, -0.7, 0.8]:
				var at := access.to_global(Vector3(x, 0.94, z))
				var query := PhysicsShapeQueryParameters3D.new()
				var capsule := CapsuleShape3D.new()
				capsule.radius = 0.4064
				capsule.height = 1.8288
				query.shape = capsule
				query.transform.origin = at
				query.collision_mask = 1
				var space := access.get_world_3d().direct_space_state
				for hit: Dictionary in space.intersect_shape(query):
					failures += 1
					print(
						"METRO_BLOCKED ",
						access.zone_id,
						" at ",
						Vector2(x, z),
						" by ",
						(hit["collider"] as Node).get_path()
					)
				var ray := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 1.2, 1)
				if space.intersect_ray(ray).is_empty():
					failures += 1
					print("METRO_MISSING_FLOOR ", access.zone_id, " at ", Vector2(x, z))
	print(
		"METRO_LIVE_AUDIT ",
		"PASS" if failures == 0 else "FAIL",
		" endpoints=",
		metro.accesses.size(),
		" failures=",
		failures
	)
	get_tree().quit(0 if failures == 0 else 1)
