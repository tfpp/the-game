extends GutTest
## Authoring contract: every public fast-travel room owns a usable metro connector.

const SCENES: Array[String] = [
	"res://features/casino_hub/casino_gridmap.tscn",
	"res://features/table_games/feature.tscn",
	"res://features/room_doors/feature.tscn",
	"res://features/chicken_betting/feature.tscn",
	"res://features/vip_lounge/feature.tscn",
	"res://features/strip_mall/feature.tscn",
	"res://features/pawn_shop/feature.tscn",
	"res://features/starter_room/feature.tscn",
	"res://features/street_district/feature.tscn",
	"res://features/shooting_gallery/feature.tscn",
	"res://features/dev_room/feature.tscn",
	"res://features/gnomes/feature.tscn",
	"res://features/hotel_annex/feature.tscn",
	"res://features/apartments/feature.tscn",
	"res://features/hotel_props/feature.tscn",
]


func test_all_seventeen_connectors_have_floor_and_capsule_clearance() -> void:
	var metro := (
		(load("res://features/metro/feature.tscn") as PackedScene).instantiate() as MetroService
	)
	add_child_autofree(metro)
	metro.set_physics_process(false)
	var count := 0
	for path: String in SCENES:
		var feature := (load(path) as PackedScene).instantiate() as Node3D
		add_child(feature)
		await wait_physics_frames(2)
		for node: Node in feature.find_children("MetroAccess", "Node3D", true, false):
			var access := node as MetroAccess
			count += 1
			assert_not_null(access.source, path)
			if access.source == null:
				continue
			var cab := access.source
			var room := StreamedRoom.for_position(access, cab.car.global_position)
			if room != null:
				room.load_room(10000)
			cab.net_aperture = 1
			cab.set_physics_process(false)
			cab._update_doors()
			await wait_physics_frames(5)
			for z: float in [-2.4, -1.5, -0.7, 0.0, 0.8]:
				var at := access.to_global(Vector3(0, 0.93, z))
				var capsule := CapsuleShape3D.new()
				capsule.radius = 0.4064
				capsule.height = 1.8288
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.transform.origin = at
				query.collision_mask = 1
				var space := access.get_world_3d().direct_space_state
				var hits := space.intersect_shape(query)
				var names: Array[String] = []
				for hit: Dictionary in hits:
					names.append(str((hit["collider"] as Node).get_path()))
				assert_true(
					hits.is_empty(), "%s at %.1f blocked by %s" % [access.zone_id, z, names]
				)
				var ray := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 1.2, 1)
				assert_false(space.intersect_ray(ray).is_empty(), access.zone_id + " floor")
				if room != null:
					assert_true(room.contains(at), access.zone_id + " remains in streamed bounds")
			metro.accesses.erase(access)
			access.destination.free()
		if path == SCENES[0]:
			autofree(feature)
		else:
			feature.free()
		await wait_physics_frames(2)
	assert_eq(count, 17)


func test_future_authored_public_rooms_require_a_connector() -> void:
	for folder: String in DirAccess.get_directories_at("res://features"):
		var path := "res://features/" + folder + "/feature.tscn"
		if folder == "metro" or not ResourceLoader.exists(path):
			continue
		var state := (load(path) as PackedScene).get_state()
		var rooms: Array[NodePath] = []
		var connectors: Array[NodePath] = []
		for index: int in state.get_node_count():
			for property: int in state.get_node_property_count(index):
				var key := state.get_node_property_name(index, property)
				var value: Variant = state.get_node_property_value(index, property)
				if key == &"room_scene" and not str(value).is_empty():
					rooms.append(state.get_node_path(index))
				if (
					key == &"script"
					and value is Script
					and value.resource_path == "res://features/metro/metro_access.gd"
				):
					connectors.append(state.get_node_path(index))
		for room: NodePath in rooms:
			var found := false
			for connector: NodePath in connectors:
				found = found or str(connector).begins_with(str(room) + "/")
			assert_true(found, path + ": public room " + str(room) + " needs MetroAccess")
