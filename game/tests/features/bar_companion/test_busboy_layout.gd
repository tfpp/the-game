extends GutTest

const ROOM := preload("res://features/casino_hub/gridmap/playable.tscn")
const BAR := preload("res://features/bar_companion/feature.tscn")
var _room: Node3D
var _shift: BusboyShift


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	var bar := BAR.instantiate() as Node3D
	add_child_autofree(bar)
	_shift = bar.get_node("BusboyShift") as BusboyShift
	_shift.set_process(false)
	await wait_physics_frames(3)


func test_glasses_rest_on_actual_tabletops_without_new_blocking_geometry() -> void:
	var furniture := _room.get_node("Casino/Furnishings")
	for table: int in BusboyShift.TABLES.size():
		var collider: CollisionShape3D
		if table < 3:
			collider = furniture.get_node("TableBody%d/Shape" % table) as CollisionShape3D
		elif table < 5:
			var label := "CocktailTable" if table == 3 else "CocktailTableWest"
			collider = furniture.get_node("BundleFurnishings/%s/Collider" % label)
		else:
			collider = _shift.get_node("Table%d/Collider" % (table + 1))
		var shape := collider.shape as BoxShape3D
		var top := collider.global_position.y + shape.size.y * 0.5
		for slot: int in 3:
			var point := _shift.get_node("Glass%d" % (table * 3 + slot)) as Node3D
			assert_almost_eq(point.global_position.y, top, 0.001)
			var local := collider.to_local(point.global_position)
			assert_lt(absf(local.x) + 0.041, shape.size.x * 0.5)
			assert_lt(absf(local.z) + 0.041, shape.size.z * 0.5)
			assert_true(point.find_children("*", "CollisionObject3D", true, false).is_empty())
			assert_true(point.is_in_group(&"interactables"))
	assert_gt(BusboyShift.TABLES[0].distance_to(BusboyShift.TABLES[3]), 20.0)


func test_bar_station_is_on_counter_clear_of_shop_and_existing_decor() -> void:
	var counter := _room.get_node("Casino/Furnishings/BarCounter") as Node3D
	var collider := counter.get_node("Shape") as CollisionShape3D
	var top := counter.global_position.y + (collider.shape as BoxShape3D).size.y * 0.5
	var point := _shift.get_node("Bar") as Node3D
	assert_almost_eq(point.global_position.y, top, 0.001)
	assert_gt(point.global_position.distance_to(Vector3(-6.5, -0.15, -9.6)), 3.0)
	assert_gt(point.global_position.distance_to(Vector3(-9.5, -0.27, -9.6)), 0.35)
	_assert_standing_clear(Vector3(-10, -1.25, -8.65))
	assert_lt(Vector3(-10, -0.35, -8.65).distance_to(point.global_position), 2.2)


func test_orders_mark_existing_patrons_and_all_stations_have_clear_approaches() -> void:
	var furniture := _room.get_node("Casino/Furnishings")
	for index: int in 3:
		var patron := furniture.get_node("Patron%d_0" % index) as StationaryPatron
		var point := _shift.get_node("Order%d" % index) as Node3D
		assert_eq(point.global_position, patron.global_position + Vector3.UP)
		assert_true(_shift._patron_alive(index))
		var approach := Vector3(-2.8, -1.25, patron.global_position.z)
		_assert_standing_clear(approach)
		assert_lt((approach + Vector3.UP * 0.9).distance_to(point.global_position), 2.2)
		# Glass row approached from west, not through the seated patrons.
		approach = BusboyShift.TABLES[index] + Vector3(-2.7, -0.94, 0)
		_assert_standing_clear(approach)
		assert_lt(
			(approach + Vector3.UP * 0.9).distance_to(
				(_shift.get_node("Glass%d" % (index * 3)) as Node3D).global_position
			),
			2.2,
			"west-edge glasses are reachable without climbing on furniture"
		)
	_assert_standing_clear(Vector3(19.6, 0, 7.1))
	for table: int in range(4, BusboyShift.TABLES.size()):
		_assert_standing_clear(BusboyShift.TABLES[table] + Vector3(0, -1.045, -1.0))
	# Existing main ramps, elevator approaches and lounge circulation stay open.
	for x: float in [-17, 17]:
		for z: float in [-15, -8, 0, 8, 14, 17]:
			_assert_standing_clear(Vector3(x, 0, z))


func test_permanent_two_sided_cards_rest_on_all_eight_tables() -> void:
	assert_eq(BusboyShift.TABLES.size(), 8)
	for table: int in BusboyShift.TABLES.size():
		var card := _shift.get_node("TableCard%d" % (table + 1)) as Node3D
		assert_true(card.visible)
		assert_eq(card.get("number"), table + 1)
		assert_almost_eq(card.global_position.y, BusboyShift.TABLES[table].y, 0.001)
		var foot := card.get_node("Foot") as MeshInstance3D
		assert_almost_eq(foot.position.y - (foot.mesh as BoxMesh).size.y / 2, 0.0, 0.001)
		assert_true(card.has_node("NumberFront"))
		assert_true(card.has_node("NumberBack"))
		assert_true(card.find_children("*", "CollisionObject3D", true, false).is_empty())
		var ink := (card.get_node("NumberFront") as MeshInstance3D).material_override
		assert_eq((ink as StandardMaterial3D).albedo_texture.get_width(), 64)


func _assert_standing_clear(feet: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, 0.94, 0))
	query.collision_mask = 1
	assert_true(
		_room.get_world_3d().direct_space_state.intersect_shape(query).is_empty(),
		"clear standing approach %s" % feet
	)
	var ray := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.1, feet - Vector3.UP, 1)
	assert_false(_room.get_world_3d().direct_space_state.intersect_ray(ray).is_empty())
