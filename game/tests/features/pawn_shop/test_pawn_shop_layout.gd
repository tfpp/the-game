extends GutTest
## The pawn shop is its own walkable room off the south corridor: Rusty Hogg's
## counter, the gun wall and the Gun-O-Matic all stand on its real geometry.

const ROOM := preload("res://world/room.tscn")
const ANNEX := preload("res://features/annex/feature.tscn")
const SHOP := preload("res://features/pawn_shop/feature.tscn")
const RUNS := preload("res://features/slum_runs/feature.tscn")
const GUNS := preload("res://features/gun_machine/feature.tscn")
const COUNTER_CUSTOMER := Vector3(-10.2, 0.95, 39.5)

var _shop: Node3D
var _runs: Node3D
var _guns: Node3D
var _shape: CapsuleShape3D


func before_each() -> void:
	add_child_autofree(ROOM.instantiate())
	add_child_autofree(ANNEX.instantiate())
	_shop = add_child_autofree(SHOP.instantiate())
	_runs = add_child_autofree(RUNS.instantiate())
	_guns = add_child_autofree(GUNS.instantiate())
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.4064
	_shape.height = 1.8288
	await wait_physics_frames(4)


func test_walk_from_the_casino_through_the_doorway_to_every_counter() -> void:
	var route: Array[Vector3] = [
		Vector3(-1.7, 0.95, 28),
		Vector3(-1.7, 0.95, 41.5),
		Vector3(-8, 0.95, 41.5),
		COUNTER_CUSTOMER,
	]
	for index: int in route.size() - 1:
		_sweep(route[index], route[index + 1])
	for point: Vector3 in route:
		_assert_floor(point, 0.0)
	for customer: Vector3 in [
		Vector3(-9, 0.95, 36.4), Vector3(-6.5, 0.95, 42.2), Vector3(-8.3, 0.95, 42.4)
	]:
		_sweep(Vector3(-8, 0.95, 41.5), customer)
		_assert_floor(customer, 0.0)


func test_room_is_enclosed_and_covered() -> void:
	for x: float in [-13.5, -9.0, -4.5]:
		for z: float in [36.0, 40.0, 44.0]:
			_assert_floor(Vector3(x, 1, z), 0.0)
			assert_false(_ray(Vector3(x, 2, z), Vector3(x, 12, z)).is_empty(), "Ceiling")
	for target: Vector3 in [Vector3(-9, 1.5, 55), Vector3(-25, 1.5, 38), Vector3(-9, 1.5, 30)]:
		assert_false(_ray(Vector3(-9, 1.5, 40), target).is_empty(), "Walls toward %s" % target)
	# The corridor wall stays solid beside and above the doorway, and the corridor sconce
	# at z 38 keeps its wall.
	assert_false(_ray(Vector3(0, 1.5, 38), Vector3(-6, 1.5, 38)).is_empty())
	assert_false(_ray(Vector3(0, 3.6, 41.5), Vector3(-6, 3.6, 41.5)).is_empty())


func test_counter_stands_on_the_floor_with_rusty_behind_it() -> void:
	var fence := _runs.get_node("Fence") as LootFence
	assert_almost_eq(fence.global_position.y - fence.size.y * 0.5, 0.0, 0.001)
	assert_true(fence.can_use(_player_at(COUNTER_CUSTOMER)), "Pawn from the customer side")
	var rusty := _shop.get_node("RustyHogg") as StationaryPatron
	assert_eq(rusty.global_position.y, 0.0)
	assert_lt(rusty.global_position.x, fence.global_position.x - fence.size.z * 0.5)
	# Rusty faces the customers (+X) across the counter.
	var facing: Vector3 = (rusty.get_node("Body") as Node3D).global_basis * Vector3.FORWARD
	assert_almost_eq(facing, Vector3.RIGHT, Vector3.ONE * 0.001)
	_assert_clear(COUNTER_CUSTOMER)


func test_guns_hang_on_the_wall_within_reach() -> void:
	var wall := _shop.get_node("GunWall")
	assert_eq(wall.get_child_count(), 4)
	var board := _shop.get_node("Hall/GunBoard") as CSGBox3D
	var board_front := board.global_position.z + board.size.z * 0.5
	var customer := Vector3(0, 0.95, 36.4)
	for gun: WallGun in wall.get_children():
		assert_eq(ItemCatalog.find(gun.item_id).category, ItemDefinition.Category.WEAPON)
		assert_gt(gun.price_cents, 0)
		assert_between(gun.global_position.z, board_front, board_front + 0.3)
		assert_between(gun.global_position.y, 1.2, 2.2)
		customer.x = gun.global_position.x
		_assert_clear(customer)
		assert_true(gun.entity.in_range(_player_at(customer)), "%s reachable" % gun.name)


func test_top_hat_sits_on_its_stand_within_reach() -> void:
	var stand := _shop.get_node("HatStand") as CSGBox3D
	var hat := stand.get_node("TopHat") as WallGun
	assert_eq(hat.item_id, ClothingCatalog.TOP_HAT)
	assert_eq(hat.price_cents, 1000000, "$10,000")
	var cap := stand.get_node("HatStandCap") as CSGBox3D
	var cap_top := cap.global_position.y + cap.size.y * 0.5
	var brim := hat.get_node("View/Hat") as Node3D
	assert_almost_eq(brim.global_position.y, cap_top, 0.005, "Brim rests on the stand")
	var customer := stand.global_position + Vector3(1.0, 0.4, 0)
	customer.y = 0.95
	_assert_clear(customer)
	assert_true(hat.entity.in_range(_player_at(customer)))


func test_gun_o_matic_moved_in_with_a_normal_sign() -> void:
	var kiosk := _guns.get_node("Kiosk") as Node3D
	var can := _guns.get_node("TrashCan") as Node3D
	for node: Node3D in [kiosk, can]:
		assert_between(node.global_position.x, -14.5, -3.5)
		assert_between(node.global_position.z, 35.0, 44.5)
		assert_eq(node.global_position.y, 0.0)
		_assert_floor(node.global_position + Vector3(0, 1, -1.2), 0.0)
	var sign := kiosk.get_node("Sign") as Label3D
	assert_false(sign.fixed_size, "Sign scales with distance like other 3D signs")
	assert_lt(sign.font_size * sign.pixel_size, 0.25)


func _player_at(at: Vector3) -> Player:
	var player := preload("res://core/player/player.tscn").instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = at
	return player


func _assert_clear(origin: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = _shape
	query.transform.origin = origin
	var space := _shop.get_world_3d().direct_space_state
	assert_true(space.intersect_shape(query).is_empty(), "Clear standing room at %s" % origin)


func _sweep(start: Vector3, end: Vector3) -> void:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.shape = _shape
	query.transform.origin = start
	query.motion = end - start
	var space := _shop.get_world_3d().direct_space_state
	assert_almost_eq(space.cast_motion(query)[0], 1.0, 0.001, "Clear route %s -> %s" % [start, end])


func _assert_floor(from: Vector3, expected_y: float) -> void:
	var hit := _ray(from, from - Vector3(0, 4, 0))
	assert_false(hit.is_empty(), "Floor under %s" % from)
	if not hit.is_empty():
		assert_almost_eq((hit["position"] as Vector3).y, expected_y, 0.02)


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	return _shop.get_world_3d().direct_space_state.intersect_ray(query)
