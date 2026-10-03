extends GutTest
## The separate storefront retains reachable merchandise and Rusty Hogg's
## counter and the gun wall stand on its real geometry.

const SHOP := preload("res://features/pawn_shop/feature.tscn")
const RUNS := preload("res://features/slum_runs/feature.tscn")
const COUNTER_CUSTOMER := Vector3(-10.2, 0.95, 24.5)

var _shop: Node3D
var _runs: Node3D
var _shape: CapsuleShape3D


func before_each() -> void:
	_shop = add_child_autofree(SHOP.instantiate())
	_runs = add_child_autofree(RUNS.instantiate())
	# Exercise the local layout; the travel integration verifies deployed world positions.
	_shop.position = Vector3.ZERO
	(_shop.get_node("Room") as StreamedRoom).load_room(60000)
	for prop: String in ["Fence"]:
		(_runs.get_node(prop) as Node3D).position.z += 4000
	_shape = CapsuleShape3D.new()
	_shape.radius = 0.4064
	_shape.height = 1.8288
	await wait_physics_frames(4)


func test_walk_from_van_arrival_to_every_counter() -> void:
	var route: Array[Vector3] = [
		Vector3(-3.5, 0.95, 27.0),
		Vector3(-8, 0.95, 26.5),
		COUNTER_CUSTOMER,
	]
	for index: int in route.size() - 1:
		_sweep(route[index], route[index + 1])
	for point: Vector3 in route:
		_assert_floor(point, 0.0)
	for customer: Vector3 in [
		Vector3(-9, 0.95, 21.4), Vector3(-6.5, 0.95, 27.200000000000003), Vector3(-8.3, 0.95, 27.4)
	]:
		_sweep(Vector3(-8, 0.95, 26.5), customer)
		_assert_floor(customer, 0.0)


func test_room_is_enclosed_and_covered() -> void:
	for x: float in [-13.5, -9.0, -4.5]:
		for z: float in [21.0, 25.0, 29.5]:
			_assert_floor(Vector3(x, 1, z), 0.0)
			assert_false(_ray(Vector3(x, 2, z), Vector3(x, 12, z)).is_empty(), "Ceiling")
	for target: Vector3 in [
		Vector3(-9, 1.5, 40.0), Vector3(-25, 1.5, 23.0), Vector3(-9, 1.5, 15.0)
	]:
		assert_false(_ray(Vector3(-9, 1.5, 25.0), target).is_empty(), "Walls toward %s" % target)
	for x: float in [-15, -13, -11, -9, -7, -5, -3]:
		for y: float in [0.5, 1.8, 2.4, 3.5, 4.8]:
			assert_false(_ray(Vector3(x, y, 29.5), Vector3(x, y, 31)).is_empty(), "Closed frontage")


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
	var customer := Vector3(0, 0.95, 21.4)
	for gun: WallGun in wall.get_children():
		assert_eq(ItemCatalog.find(gun.item_id).category, ItemDefinition.Category.WEAPON)
		assert_gt(gun.price_cents, 0)
		assert_between(gun.global_position.z, board_front, board_front + 0.3)
		assert_between(gun.global_position.y, 1.2, 2.2)
		customer.x = gun.global_position.x
		_assert_clear(customer)
		assert_true(gun.entity.in_range(_player_at(customer)), "%s reachable" % gun.name)


func test_rusty_talk_is_reachable_without_stealing_the_pawn_counter() -> void:
	var interaction := preload("res://features/interaction/interaction.gd").new()
	add_child_autofree(interaction)
	interaction.set_physics_process(false)
	var device := Controls.device
	var playing := Controls.playing
	Controls.device = Controls.Device.TOUCH
	Controls.playing = true
	var player := _player_at(COUNTER_CUSTOMER)
	player.add_to_group(&"local_player")
	player.global_position = player.net_position
	assert_same(interaction._find_target(), _runs.get_node("Fence"))
	var talk_spot := Vector3(-12.7, 0.95, 27.2)
	_sweep(Vector3(-8, 0.95, 26.5), talk_spot)
	_assert_clear(talk_spot)
	_assert_floor(talk_spot, 0.0)
	player.net_position = talk_spot
	player.global_position = talk_spot
	assert_same(interaction._find_target(), _shop.get_node("RustyHogg"))
	assert_eq(interaction.target_text(), "Talk to Rusty Hogg")
	Controls.device = device
	Controls.playing = playing


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
