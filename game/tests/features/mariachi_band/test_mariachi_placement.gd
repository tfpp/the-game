extends GutTest
## The band rests on the west promenade, facing the pit with a clear audience aisle.

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const FEATURE := preload("res://features/mariachi_band/feature.tscn")
const PIT_EXIT := Vector3(-15, 0, 0)
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
		var up := _ray(point + Vector3(0, 0.3, 0), point + Vector3(0, 10, 0))
		assert_false(up.is_empty(), "covered by the casino ceiling")
		if not up.is_empty():
			assert_gt((up["position"] as Vector3).y, 3.6, "headroom over sign and sombreros")


func test_footprint_clears_west_wall_and_pit() -> void:
	var space := _room.get_world_3d().direct_space_state
	for point: Vector3 in _footprint():
		assert_lt(point.x, -15.5, "stage stays outside the gaming pit")
		assert_gt(point.x, -23.7, "stage clears the west wall")
		var query := PhysicsShapeQueryParameters3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.6, 3.0, 0.6)
		query.shape = shape
		query.transform = Transform3D(Basis(), point + Vector3(0, 1.6, 0))
		assert_true(space.intersect_shape(query, 1).is_empty(), "no wall at %s" % point)


func test_band_faces_east_into_the_gaming_pit() -> void:
	var band := FEATURE.instantiate() as MariachiBand
	var forward := band.transform.basis * Vector3.FORWARD
	var to_exit := (PIT_EXIT - band.position) * Vector3(1, 0, 1)
	band.free()
	assert_lt(rad_to_deg(forward.angle_to(to_exit)), 5.0, "the musicians face the pit exit")


func test_audience_can_walk_up_and_request_a_song() -> void:
	await _add_band()
	var front := _band.to_global(Vector3(0, 1.0, -4.0))
	assert_true(_ray(PIT_EXIT + Vector3(-1, 1.0, 0), front).is_empty(), "clear line from ramp")
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


func test_every_musician_faces_east_and_animated_meshes_clear_backdrop_and_wall() -> void:
	await _add_band()
	for time: float in [0.0, 0.5, 1.0, 2.0, 4.0, 8.0, 12.0, 16.0, 24.0, 32.0]:
		_band._clock = time
		for musician: Node3D in _band.get_node("Musicians").get_children():
			var body := musician.get_node("Body") as MariachiMusicianModel
			body._time = time + body.seed_phase
			body._update(0.0)
			var bounds := StationaryPatron._model_bounds(musician, Transform3D.IDENTITY)
			assert_lt(bounds.end.z, 1.15, "%s mesh clears backdrop at %s" % [musician.name, time])
			var world_bounds := _band.global_transform * bounds
			assert_gt(world_bounds.position.x, -23.8, "%s clears casino wall" % musician.name)
			var facing := musician.global_basis * Vector3.FORWARD
			assert_gt(facing.dot(Vector3.RIGHT), 0.99, "%s faces east" % musician.name)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return _room.get_world_3d().direct_space_state.intersect_ray(query)
