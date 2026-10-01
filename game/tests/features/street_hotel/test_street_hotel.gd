extends GutTest

const HOTEL := preload("res://features/street_hotel/feature.tscn")
const STREET := preload("res://features/street_district/feature.tscn")
const SPEC := preload("res://features/street_hotel/spec.gd")
const LAYOUT := preload("res://features/street_hotel/floor_layout.gd")
const FURNITURE := preload("res://features/street_hotel/furnishings.gd")
const PLAYER := preload("res://core/player/player.tscn")
var _root: Node3D
var _hotel: Node3D
var _street: Node3D


func before_each() -> void:
	_root = Node3D.new()
	add_child_autofree(_root)
	_street = STREET.instantiate() as Node3D
	_street.name = "street_district"
	_root.add_child(_street)
	_hotel = HOTEL.instantiate() as Node3D
	_hotel.name = "street_hotel"
	_root.add_child(_hotel)


func test_ten_floors_have_twenty_permanent_guest_doors_and_garage_lift_stops() -> void:
	assert_eq(_hotel.floors.size(), 10)
	var numbers: Array[int] = []
	for index: int in range(10):
		var floor: StreamedRoom = _hotel.floors[index]
		assert_false(floor.is_loaded())
		assert_eq(floor.get_node("GuestDoors").get_child_count(), 20)
		assert_false((floor.get_node("GuestDoors") as Node3D).visible)
		for door: SwingDoor in floor.get_node("GuestDoors").get_children():
			assert_not_null(door.get_node("NetworkedEntity"))
			var number := int(str(door.name).trim_prefix("Room"))
			assert_false(numbers.has(number))
			numbers.append(number)
		var button := floor.get_node("LiftCall") as Node3D
		assert_same(button.call("lift"), _hotel.lift)
		assert_eq(button.get("floor_index"), index)
		assert_same(_hotel.lift.gates[index], floor.get_node("LiftGate"))
		assert_almost_eq(_hotel.lift.stop_height(index), index * SPEC.STOREY, .001)
		assert_eq(_hotel.lift.stop_label(index), str(index + 1))
		assert_false(floor.has_node("ExpressLift"))
	assert_eq(numbers.size(), 200)


func test_all_floor_sockets_match_and_rooms_fit_the_ten_storey_envelope() -> void:
	for index: int in range(10):
		var floor := LAYOUT.build(_root, index, false)
		var rooms: Array = floor.get_meta("guest_rooms")
		assert_eq(rooms.size(), 20)
		var joins: Array = floor.get_meta("joins")
		assert_eq(joins.size(), 30)
		for join: Dictionary in joins:
			var a := join["from"] as ProceduralSocketAttachment
			var b := join["to"] as ProceduralSocketAttachment
			assert_true(a.errors_with(b).is_empty())
			assert_null(a.cap)
			assert_null(b.cap)
		for room: Node3D in rooms:
			for x: float in [-3.0, 3.0]:
				for y: float in [0.0, SPEC.HEIGHT]:
					for z: float in [0.0, 8.0]:
						var point := floor.to_local(room.to_global(Vector3(x, y, z)))
						assert_lte(absf(point.x), 9.501)
						assert_gte(point.z, 0.0)
						assert_lte(point.z, SPEC.LENGTH + .001)
						assert_lte(point.y + index * SPEC.STOREY, 42.0)
		floor.free()


func test_saved_floor_batches_have_real_buffers_and_only_one_floor_loads() -> void:
	var previous: StreamedRoom
	for index: int in range(10):
		var floor: StreamedRoom = _hotel.floors[index]
		floor.load_room(3000)
		if previous != null:
			previous.unload_room()
			assert_false(previous.is_loaded())
		var layout := floor.get_node("Content/FloorLayout") as Node3D
		assert_lt(int(layout.get_meta("furniture_instances")), 380)
		assert_lt(int(layout.get_meta("furniture_batches")), 120)
		assert_eq(layout.get_meta("floor_index"), index)
		for batch: MultiMeshInstance3D in layout.get_node("BatchedFurniture").get_children():
			assert_eq(
				batch.multimesh.buffer.size(),
				batch.multimesh.instance_count * 16,
				"Transforms and colors must survive the bake"
			)
			assert_eq(batch.visibility_range_end, 32.0)
			assert_eq(batch.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		var proxy := floor.get_node("Content/LowDetailStreet") as Node3D
		assert_almost_eq(proxy.position.y, -index * SPEC.STOREY, .001)
		assert_eq(proxy.get_meta("source_origin"), SPEC.STREET_ORIGIN)
		assert_true(proxy.find_children("*", "CollisionShape3D", true, false).is_empty())
		for batch: MultiMeshInstance3D in proxy.find_children(
			"*", "MultiMeshInstance3D", true, false
		):
			var material := batch.material_override as StandardMaterial3D
			assert_eq(material.albedo_texture.get_width(), 32)
			assert_eq(material.albedo_texture.get_height(), 32)
		previous = floor
		await wait_physics_frames(2)


func test_room_recipes_are_deterministic_and_varied_on_every_floor() -> void:
	var seeds: Array[int] = []
	for floor: int in range(10):
		var layouts: Array[int] = []
		for index: int in range(20):
			var recipe := SPEC.recipe(floor, index)
			assert_eq(recipe, SPEC.recipe(floor, index))
			assert_false(seeds.has(recipe["seed"]))
			seeds.append(recipe["seed"])
			if not layouts.has(recipe["layout"]):
				layouts.append(recipe["layout"])
		assert_eq(layouts.size(), 5)


func test_street_hotel_and_physical_elevator_round_trip() -> void:
	var door := _hotel.get_node("StreetEntrance") as RoomDoor
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = door.global_position + Vector3(1.2, 0, 0)
	player.net_position = player.position
	_root.add_child(player)
	player.set_physics_process(false)
	assert_not_null(door._arrival)
	door.use()
	var first: StreamedRoom = _hotel.floors[0]
	assert_true(first.is_loaded())
	assert_eq(player.net_position, (first.get_node("Arrival") as Marker3D).global_position)
	var lift := _hotel.lift as ProceduralMovingLift
	player.global_position = lift.cab.global_position + Vector3(0, .95, -.65)
	player.net_position = player.global_position
	player.set_physics_process(true)
	await wait_physics_frames(8)
	assert_true(player.is_on_floor())
	assert_true(lift.request_floor(9))
	await _wait_for_lift(lift, 9)
	assert_true(lift.contains(player), "The real cab carries the player to floor ten")
	assert_almost_eq(player.net_position.y, 9 * SPEC.STOREY + .9144, .12)
	var top: StreamedRoom = _hotel.floors[9]
	assert_true(top.is_loaded(), "Landing streams before the doors open")
	assert_true(lift.request_floor(0))
	await _wait_for_lift(lift, 0)
	assert_true(lift.contains(player))
	player.set_physics_process(false)
	var returning := first.get_node("StreetReturn") as RoomDoor
	assert_eq(returning.destination_room(), _street.get_node("Room"))
	player.net_position = returning.global_position
	returning.use()
	var street := _street.get_node("Room") as StreamedRoom
	assert_true(street.is_loaded())
	assert_eq(player.net_position, (street.get_node("HotelArrival") as Marker3D).global_position)
	await wait_physics_frames(3)
	player.set_physics_process(true)
	await wait_physics_frames(80)
	assert_true(player.is_on_floor())
	assert_gt(player.net_position.y, .5)


func test_every_guest_has_supported_clear_route_and_windows_block_falling() -> void:
	var floor: StreamedRoom = _hotel.floors[0]
	floor.load_room(3000)
	await wait_physics_frames(3)
	var layout := floor.get_node("Content/FloorLayout") as Node3D
	var space := floor.get_world_3d().direct_space_state
	var hull := CapsuleShape3D.new()
	hull.radius = .4064
	hull.height = 1.8288
	for index: int in range(20):
		var room := layout.get_node("Room%d" % SPEC.room_number(0, index)) as Node3D
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.transform.origin = room.to_global(Vector3(0, .95, .9))
		query.motion = room.global_basis.z * 5.9
		assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, str(room.name))
		query.transform.origin = room.to_global(Vector3(0, .95, 7.3))
		query.motion = room.global_basis.z * 1.4
		assert_lt(space.cast_motion(query)[0], 1.0, "Window collision retains the player")
		var at := room.to_global(Vector3(0, 1, 2))
		var hit := space.intersect_ray(
			PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 2)
		)
		assert_false(hit.is_empty())


func _wait_for_lift(lift: ProceduralMovingLift, target: int) -> void:
	for tick: int in range(2400):
		if lift.net_floor == target and lift.net_phase == ProceduralMovingLift.Phase.DOCKED:
			return
		await wait_physics_frames(1)
	fail_test("Physical hotel elevator did not reach its requested floor")


func test_guest_furniture_fits_walls_and_groups_do_not_overlap() -> void:
	for floor_index: int in range(10):
		var floor := LAYOUT.build(_root, floor_index)
		for room: Node3D in floor.get_meta("guest_rooms"):
			var solids: Array[AABB] = []
			var bed := Vector3.ZERO
			var table := Vector3.ZERO
			var desk := Vector3.ZERO
			var chair := Vector3.ZERO
			for item: Dictionary in room.get_meta("furniture_layout"):
				var pose: Transform3D = item["transform"]
				var id: String = item["id"]
				var bounds := pose * (FURNITURE.data(id)["mesh"] as Mesh).get_aabb()
				assert_gte(bounds.position.x, -3.001, "Furniture stays inside walls")
				assert_lte(bounds.end.x, 3.001)
				assert_gte(bounds.position.z, .1)
				assert_lte(bounds.end.z, 7.99)
				if id == "bed":
					bed = pose.origin
				if id == "bedside":
					table = pose.origin
				if id == "desk":
					desk = pose.origin
				if id == "chair":
					chair = pose.origin
				if item["solid"]:
					for other: AABB in solids:
						assert_false(
							bounds.grow(-.015).intersects(other.grow(-.015)),
							"Furniture groups must not intersect"
						)
					solids.append(bounds)
			# Twins share one wall; the table accompanies the first bed.
			assert_lt(absf(absf(bed.x) - absf(table.x)), .8)
			assert_almost_eq(desk.z, chair.z, .001, "Chair faces its desk")
			assert_almost_eq(absf(desk.x - chair.x), .85, .001)
		floor.free()


func test_hotel_elevator_controls_are_distinct_and_all_landings_are_supported() -> void:
	var lift := _hotel.lift as ProceduralMovingLift
	lift.set_physics_process(false)
	var player := PLAYER.instantiate() as Player
	_root.add_child(player)
	player.set_physics_process(false)
	player.global_position = lift.cab.global_position + Vector3(0, .95, -.65)
	player.net_position = player.global_position
	for index: int in range(10):
		var button := lift.cab.get_node("Floor%d" % index) as Node3D
		var eye := (
			player.global_position
			+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * .5)
		)
		var direction := (button.global_position - eye).normalized()
		player.yaw = atan2(-direction.x, -direction.z)
		player.pitch = asin(direction.y)
		assert_true(button.call("aimed_at", player))
		for other: int in range(10):
			if other != index:
				assert_false(lift.cab.get_node("Floor%d" % other).call("aimed_at", player))
	player.queue_free()
	await wait_physics_frames(2)
	var hull := CapsuleShape3D.new()
	hull.radius = .4064
	hull.height = 1.8288
	for index: int in range(10):
		var floor: StreamedRoom = _hotel.floors[index]
		floor.load_room(3000)
		lift.net_floor = index
		lift.net_height = lift.stop_height(index)
		lift.cab.position.y = lift.net_height
		lift._update_doors()
		await wait_physics_frames(2)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = hull
		query.transform.origin = floor.to_global(Vector3(6, .9544, 4.8))
		query.motion = Vector3(0, 0, 1.5)
		var space := floor.get_world_3d().direct_space_state
		assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, "Cab exit clears both doors")
		var point := floor.to_global(Vector3(6, .2, 5.4))
		assert_false(
			(
				space
				. intersect_ray(
					PhysicsRayQueryParameters3D.create(point, point + Vector3.DOWN * .4)
				)
				. is_empty()
			)
		)
		for other: int in range(10):
			assert_eq(lift.gates[other]._amount, 1.0 if other == index else 0.0)
		floor.unload_room()
	await wait_physics_frames(2)
