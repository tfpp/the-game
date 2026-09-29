extends GutTest

const Feature := preload("res://features/hotel_annex/feature.tscn")
const Atrium := preload("res://features/hotel_annex/atrium_hotel.gd")

var _feature: Node3D
var _hotel: StreamedRoom


func before_each() -> void:
	_feature = Feature.instantiate() as Node3D
	add_child_autofree(_feature)
	_hotel = _feature.get_node("Atrium") as StreamedRoom


func test_floor_holes_leave_atrium_open_and_ramp_landings_solid() -> void:
	assert_eq(Atrium.floor_holes(0), [] as Array[Rect2])
	for level: int in range(1, Atrium.LEVELS):
		var rects := Atrium.subtract(Atrium.OUTER, Atrium.floor_holes(level))
		var area := 0.0
		for rect: Rect2 in rects:
			area += rect.get_area()
			assert_false(rect.intersects(Atrium.ATRIUM), "Atrium stays open")
		var holes := 0.0
		for hole: Rect2 in Atrium.floor_holes(level):
			holes += hole.get_area()
		assert_almost_eq(area, Atrium.OUTER.get_area() - holes, 0.01)
		# The ramp from below lands on solid floor just past its top end.
		var top: Vector3 = Atrium.ramp_ends(level - 1)[1]
		var landing := Vector2(top.x + signf(top.x) * 0.6, top.z)
		var solid := false
		for rect: Rect2 in rects:
			solid = solid or rect.has_point(landing)
		assert_true(solid, "Landing at storey %d" % level)


func _space() -> PhysicsDirectSpaceState3D:
	return _hotel.get_world_3d().direct_space_state


func _floor_at(local: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
		_hotel.to_global(local), _hotel.to_global(local + Vector3.DOWN * 3)
	)
	var hit := _space().intersect_ray(ray)
	return -INF if hit.is_empty() else _hotel.to_local(hit.position as Vector3).y


func test_every_storey_has_floor_around_the_open_atrium() -> void:
	_hotel.load_room(3000)
	await wait_physics_frames(3)
	var center := Atrium.ATRIUM.get_center()
	for level: int in Atrium.LEVELS:
		var y := Atrium.floor_y(level)
		assert_almost_eq(_floor_at(Vector3(center.x, y + 1, 4)), y, 0.02, "Gallery %d" % level)
		assert_almost_eq(_floor_at(Vector3(-13, y + 1, 5)), y, 0.02, "West room %d" % level)
		assert_almost_eq(_floor_at(Vector3(27, y + 1, 17)), y, 0.02, "East room %d" % level)
	# Looking down the atrium from the top storey reaches the lobby floor.
	var top := Atrium.floor_y(Atrium.LEVELS - 1) + 1
	var ray := PhysicsRayQueryParameters3D.create(
		_hotel.to_global(Vector3(center.x + 5, top, center.y)),
		_hotel.to_global(Vector3(center.x + 5, -1, center.y))
	)
	var hit := _space().intersect_ray(ray)
	assert_almost_eq(_hotel.to_local(hit.position as Vector3).y, 0.0, 0.02)


func test_ramps_climb_every_storey_with_headroom() -> void:
	_hotel.load_room(3000)
	await wait_physics_frames(3)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4064
	capsule.height = 1.8288
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	for level: int in Atrium.LEVELS - 1:
		var ends := Atrium.ramp_ends(level)
		var start: Vector3 = ends[0]
		var end: Vector3 = ends[1]
		var slope := (end.y - start.y) / absf(end.x - start.x)
		assert_lte(rad_to_deg(atan(slope)), 10.0, "Gentle ramp slope")
		for step: int in range(1, 10):
			var point := start.lerp(end, step / 10.0)
			assert_almost_eq(_floor_at(point + Vector3.UP), point.y, 0.05, "Ramp %d" % level)
			query.transform = Transform3D(
				Basis.IDENTITY, _hotel.to_global(point + Vector3.UP * 1.05)
			)
			assert_true(_space().intersect_shape(query).is_empty(), "Headroom on ramp %d" % level)
		# Step off onto the landing and turn into the next ramp's lane.
		var landing := end + Vector3(signf(end.x) * 1.0, 0, 0)
		assert_almost_eq(_floor_at(landing + Vector3.UP), end.y, 0.02, "Landing %d" % level)
		query.transform = Transform3D(Basis.IDENTITY, _hotel.to_global(landing + Vector3.UP * 0.96))
		query.motion = _hotel.global_basis * Vector3(0, 0, -2.5 if level % 2 == 0 else 2.5)
		assert_almost_eq(_space().cast_motion(query)[0], 1.0, 0.001, "Turn at %d" % level)
		query.motion = Vector3.ZERO


func test_gallery_rail_guards_the_atrium_drop() -> void:
	_hotel.load_room(3000)
	await wait_physics_frames(3)
	var center := Atrium.ATRIUM.get_center()
	for level: int in range(1, Atrium.LEVELS):
		var y := Atrium.floor_y(level) + 0.7
		var ray := PhysicsRayQueryParameters3D.create(
			_hotel.to_global(Vector3(center.x, y, Atrium.ATRIUM.position.y - 1)),
			_hotel.to_global(Vector3(center.x, y, Atrium.ATRIUM.position.y + 1))
		)
		assert_false(_space().intersect_ray(ray).is_empty(), "Rail on storey %d" % level)


func test_wing_round_trip_preloads_collision_and_retains_shared_doors() -> void:
	var classic := _feature.get_node("Hotel") as StreamedRoom
	var marker := classic.get_node("AtriumArrival") as Marker3D
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	player.set_multiplayer_authority(1)
	player.position = marker.global_position
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	await wait_physics_frames(2)
	assert_true(classic.is_loaded())
	assert_false(_hotel.is_loaded())
	var entrance := classic.get_node("AtriumEntrance") as RoomDoor
	assert_true(entrance.can_use(player))
	entrance.use()
	assert_true(_hotel.is_loaded(), "Destination collision loads before teleport")
	assert_eq(player.net_position, (_hotel.get_node("Arrival") as Marker3D).global_position)
	await wait_physics_frames(3)
	assert_false(classic.is_loaded(), "Each wing streams independently")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = (player.get_node("Collider") as CollisionShape3D).shape
	query.transform = player.global_transform
	query.exclude = [player.get_rid()]
	assert_true(_space().intersect_shape(query).is_empty(), "Atrium arrival clears player hull")
	assert_almost_eq(_floor_at(_hotel.to_local(player.global_position)), 0.0, 0.02)
	var doors := _hotel.get_node("RoomDoors")
	assert_eq(doors.get_child_count(), 18)
	var door := doors.get_node("Room101") as SwingDoor
	assert_not_null(door.get_node("NetworkedEntity") as NetworkedInteraction)
	door.net_state = SwingDoor.State.OPEN_IN
	var exit := _hotel.get_node("Return") as RoomDoor
	assert_true(exit.can_use(player))
	exit.use()
	assert_true(classic.is_loaded())
	assert_eq(player.net_position, marker.global_position)
	_hotel._hold_until_msec = 0
	await wait_physics_frames(3)
	assert_false(_hotel.is_loaded())
	query.transform = player.global_transform
	assert_true(_space().intersect_shape(query).is_empty(), "Classic arrival clears player hull")
	entrance.use()
	assert_same(doors.get_node("Room101"), door)
	assert_eq(door.net_state, SwingDoor.State.OPEN_IN)


func test_gps_routes_through_classic_hotel_to_atrium_and_back() -> void:
	var gps := Gps.new()
	add_child_autofree(gps)
	var regions := gps.regions()
	var links := gps.links()
	var casino := (_feature.get_node("CasinoArrival") as Marker3D).global_position
	var arrival := (_hotel.get_node("Arrival") as Marker3D).global_position
	var classic := _feature.get_node("Hotel") as StreamedRoom
	var lounge := (classic.get_node("AtriumArrival") as Marker3D).global_position
	assert_ne(GpsRoute.region_of(regions, lounge), GpsRoute.region_of(regions, arrival))
	var hop := GpsRoute.next_hop(regions, links, casino, arrival)
	assert_eq(hop["position"], (_feature.get_node("Entrance") as RoomDoor).global_position)
	hop = GpsRoute.next_hop(regions, links, lounge, arrival)
	assert_eq(hop["position"], (classic.get_node("AtriumEntrance") as RoomDoor).global_position)
	hop = GpsRoute.next_hop(regions, links, arrival, casino)
	assert_eq(hop["position"], (_hotel.get_node("Return") as RoomDoor).global_position)
