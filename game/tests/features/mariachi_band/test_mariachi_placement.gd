extends GutTest
## The stage on the north promenade: on the floor, under the ceiling, clear of the
## ramp-to-wing walkway and the coin, and facing the players coming up the ramp.

const ROOM := preload("res://world/room.tscn")
const FEATURE := preload("res://features/mariachi_band/feature.tscn")
## Top of the north ramp out of the gaming floor (casino_hub README, layout test).
const PIT_EXIT := Vector3(0, 0, -12)
## The walkway from the pit exit to the casino wing doorway at (0, 0, -34).
const WALKWAY_HALF_WIDTH := 3.5
const COIN := Vector3(14, 0.4, -14)
const KAABA := Vector3(-24, 0, -24)
const STAGE_RADIUS := 2.6

var _room: Node3D
var _band: MariachiBand


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	await wait_physics_frames(3)


func _add_band() -> void:
	_band = FEATURE.instantiate() as MariachiBand
	add_child_autofree(_band)
	_band.set_process(false)
	await wait_physics_frames(3)


## World-space points around the stage rim and the backdrop's ends.
func _footprint() -> Array[Vector3]:
	var band := FEATURE.instantiate() as MariachiBand
	var at := band.transform
	band.free()
	var points: Array[Vector3] = []
	for step: int in 16:
		var angle := TAU * step / 16.0
		points.append(at * (Vector3(cos(angle), 0, sin(angle)) * STAGE_RADIUS))
	for side: float in [-2.5, 2.5]:
		points.append(at * Vector3(side, 0, 1.3))
	return points


func test_stage_sits_on_the_promenade_floor_under_its_ceiling() -> void:
	for point: Vector3 in _footprint():
		var down := _ray(point + Vector3(0, 2, 0), point - Vector3(0, 3, 0))
		assert_false(down.is_empty(), "floor under %s" % point)
		if not down.is_empty():
			assert_almost_eq((down["position"] as Vector3).y, 0.0, 0.03, "flush on the floor")
		var up := _ray(point + Vector3(0, 0.3, 0), point + Vector3(0, 8, 0))
		assert_false(up.is_empty(), "covered by the casino ceiling")
		if not up.is_empty():
			assert_gt((up["position"] as Vector3).y, 3.6, "headroom over sign and sombreros")


func test_footprint_has_no_walls_and_stays_off_the_walkway() -> void:
	var space := _room.get_world_3d().direct_space_state
	for point: Vector3 in _footprint():
		assert_gt(point.x, WALKWAY_HALF_WIDTH, "ramp-to-wing walkway stays open")
		assert_gt(Vector2(point.x - COIN.x, point.z - COIN.z).length(), 3.0, "coin reachable")
		assert_gt(point.distance_to(KAABA), 10.0)
		assert_lt(point.z, -12.5, "on the promenade, beyond the pit rail")
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6, 3.0, 0.6)
		query.shape = shape
		query.transform = Transform3D(Basis(), point + Vector3(0, 1.6, 0))
		assert_true(space.intersect_shape(query, 1).is_empty(), "no wall at %s" % point)


func test_band_faces_players_coming_up_the_north_ramp() -> void:
	var band := FEATURE.instantiate() as MariachiBand
	var forward := band.transform.basis * Vector3.FORWARD
	var to_exit := (PIT_EXIT - band.position) * Vector3(1, 0, 1)
	band.free()
	assert_lt(rad_to_deg(forward.angle_to(to_exit)), 5.0, "the musicians face the pit exit")


func test_audience_can_walk_up_and_request_a_song() -> void:
	await _add_band()
	var front := _band.to_global(Vector3(0, 1.0, -4.0))
	assert_true(_ray(PIT_EXIT + Vector3(0, 1.0, -0.5), front).is_empty(), "clear line from ramp")
	var origin := _band.to_global(
		(_band.get_node("NetworkedEntity") as NetworkedInteraction).interaction_offset
	)
	assert_lt(origin.distance_to(front), MariachiBand.REQUEST_RANGE, "front row can request")
	for musician: Node in _band.get_node("Musicians").get_children():
		var feet := (musician as Node3D).global_position
		var floor_hit := _ray(feet + Vector3(0, 0.5, 0), feet - Vector3(0, 0.5, 0))
		assert_false(floor_hit.is_empty())
		if not floor_hit.is_empty():
			assert_almost_eq((floor_hit["position"] as Vector3).y, feet.y, 0.02, "stands on stage")


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return _room.get_world_3d().direct_space_state.intersect_ray(query)
