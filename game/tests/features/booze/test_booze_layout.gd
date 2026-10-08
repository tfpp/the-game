extends GutTest
## Drinks stand on real counters and tables in the live casino, clear of existing
## decor and busboy/quest objects, reachable from open floor, spread over the casino.

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const BAR := preload("res://features/bar_companion/feature.tscn")
const BOOZE := preload("res://features/booze/feature.tscn")
## Widest drink footprint (the cosmopolitan glass rim) plus a little air.
const FOOTPRINT := 0.075
var _room: Node3D
var _bar: Node3D
var _booze: Booze


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	_bar = BAR.instantiate() as Node3D
	add_child_autofree(_bar)
	(_bar.get_node("BusboyShift") as Node).set_process(false)
	_booze = BOOZE.instantiate() as Booze
	add_child_autofree(_booze)
	_booze.set_process(false)
	await wait_physics_frames(3)


func _space() -> PhysicsDirectSpaceState3D:
	return _room.get_world_3d().direct_space_state


func _surface(point: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.4, point - Vector3.UP, 1)
	return _space().intersect_ray(ray)


func test_every_spot_rests_on_the_visible_surface_under_its_whole_base() -> void:
	assert_eq(_booze.get_node("Spots").get_child_count(), BoozeRules.SPOTS.size())
	for index: int in BoozeRules.SPOTS.size():
		var spot := _booze.get_node("Spots/Spot%d" % index) as DrinkSpot
		var at := spot.global_position
		assert_eq(at, BoozeRules.SPOTS[index])
		assert_true(spot.find_children("*", "CollisionObject3D", true, false).is_empty())
		# Solid furniture lies at or just below the painted top (bar colliders sit 15 cm low).
		var hit := _surface(at)
		assert_false(hit.is_empty(), "spot %d is over furniture" % index)
		if not hit.is_empty():
			assert_between((hit["position"] as Vector3).y, at.y - 0.16, at.y + 0.002)
		# The drawn surface carries the whole base: neither floating nor sunk...
		for step: int in 8:
			var offset := Vector3.FORWARD.rotated(Vector3.UP, step * TAU / 8.0) * FOOTPRINT
			var top := _visual_top(at + offset)
			if is_finite(top):
				assert_almost_eq(top, at.y, 0.004, "spot %d base at %s" % [index, offset])
		var drawn := _visual_top(at)
		if not is_finite(drawn) and not hit.is_empty():
			drawn = (hit["position"] as Vector3).y  # Bundle tables draw exactly on their colliders.
		assert_almost_eq(drawn, at.y, 0.004, "spot %d stands on the furniture top" % index)
		# ...and nothing already drawn on the table pokes into the drink.
		for step: int in 12:
			var offset := (
				Vector3.FORWARD.rotated(Vector3.UP, step * TAU / 12.0) * (FOOTPRINT + 0.012)
			)
			var top := _visual_top(at + offset)
			if is_finite(top):
				assert_lte(top, at.y + 0.004, "spot %d clear of drawn decor" % index)


## Highest drawn mesh surface under `point` (within 0.4 m above/below), or -INF.
func _visual_top(point: Vector3) -> float:
	var best := -INF
	for root: Node in [_room, _bar]:
		for node: Node in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null or not mesh.is_visible_in_tree():
				continue
			var box := mesh.global_transform * mesh.get_aabb()
			if point.x < box.position.x or point.x > box.end.x:
				continue
			if point.z < box.position.z or point.z > box.end.z:
				continue
			if box.position.y > point.y + 0.4 or box.end.y < point.y - 0.4:
				continue
			var inverse := mesh.global_transform.affine_inverse()
			var from := inverse * (point + Vector3.UP * 0.4)
			var down := (inverse.basis * Vector3.DOWN).normalized()
			var faces := mesh.mesh.get_faces()
			for i: int in range(0, faces.size(), 3):
				var hit: Variant = Geometry3D.ray_intersects_triangle(
					from, down, faces[i], faces[i + 1], faces[i + 2]
				)
				if hit != null:
					best = maxf(best, (mesh.global_transform * (hit as Vector3)).y)
	return best


func test_spots_leave_existing_decor_and_quest_objects_alone() -> void:
	# Small decor props (bottles, cigars, glasses) have shapes on collision layer 0,
	# so compare against every authored box shape rather than a physics query.
	var shapes: Array[AABB] = []
	for root: Node in [_room, _bar]:
		for node: Node in root.find_children("*", "CollisionShape3D", true, false):
			var shape := node as CollisionShape3D
			if shape.shape is BoxShape3D:
				var size := (shape.shape as BoxShape3D).size
				shapes.append(shape.global_transform * AABB(-size * 0.5, size))
	var markers: Array[Vector3] = []
	var shift := _bar.get_node("BusboyShift")
	for node: Node in shift.get_children():
		if node.name.begins_with("Glass") or node.name.begins_with("TableCard"):
			markers.append((node as Node3D).global_position)
	markers.append((shift.get_node("Bar") as Node3D).global_position)
	markers.append_array(VivienneCase.SPOTS)
	assert_gt(markers.size(), 30)
	# The check does see decor: the east lounge martini and the bar's beer bottle.
	for decor: Vector3 in [Vector3(19.6, 1.045, 8.0), Vector3(-7.0, -0.27, -9.6)]:
		assert_true(_touches(decor, shapes))
	for index: int in BoozeRules.SPOTS.size():
		var spot := BoozeRules.SPOTS[index]
		assert_false(_touches(spot, shapes), "spot %d is clear of bottles and props" % index)
		for marker: Vector3 in markers:
			assert_gt(
				Vector2(spot.x - marker.x, spot.z - marker.z).length(),
				0.2,
				"spot %d keeps off existing table objects" % index
			)
		for other: int in range(index + 1, BoozeRules.SPOTS.size()):
			assert_gt(spot.distance_to(BoozeRules.SPOTS[other]), 0.9)


func _touches(spot: Vector3, shapes: Array[AABB]) -> bool:
	var drink := AABB(
		spot + Vector3(-FOOTPRINT, 0.005, -FOOTPRINT), Vector3(FOOTPRINT * 2, 0.2, FOOTPRINT * 2)
	)
	for box: AABB in shapes:
		if box.intersects(drink):
			return true
	return false


func test_each_drink_can_be_reached_from_open_floor() -> void:
	for index: int in BoozeRules.SPOTS.size():
		var spot := BoozeRules.SPOTS[index]
		var reachable := false
		for radius: float in [0.7, 1.0, 1.4]:
			for step: int in 16:
				var direction := Vector3.FORWARD.rotated(Vector3.UP, step * TAU / 16.0)
				var probe := spot + direction * radius
				var ray := PhysicsRayQueryParameters3D.create(
					probe + Vector3.UP * 0.2, probe + Vector3.DOWN * 2.0, 1
				)
				var hit := _space().intersect_ray(ray)
				if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
					continue
				var centre := (hit["position"] as Vector3) + Vector3.UP * 0.95
				if centre.distance_to(spot) > NetworkedInteraction.DEFAULT_RANGE - 0.2:
					continue
				if _capsule_clear(centre):
					reachable = true
					break
			if reachable:
				break
		assert_true(reachable, "spot %d reachable from a standing position" % index)


func test_drinks_are_spread_over_the_whole_casino() -> void:
	var low := Vector3.INF
	var high := -Vector3.INF
	var levels := {}
	for spot: Vector3 in BoozeRules.SPOTS:
		low = low.min(spot)
		high = high.max(spot)
		levels[snappedf(spot.y, 1.0)] = true
	assert_gt(high.x - low.x, 45.0, "west balcony to east promenade")
	assert_gt(high.z - low.z, 28.0, "north to south")
	assert_gte(levels.size(), 3, "gaming floor, promenade and balcony")


func _capsule_clear(centre: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, centre + Vector3.UP * 0.02)
	query.collision_mask = 1
	return _space().intersect_shape(query).is_empty()
