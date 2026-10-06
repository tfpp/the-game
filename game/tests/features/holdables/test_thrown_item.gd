extends GutTest
## Bounce behavior for thrown/dropped items (features/holdables/thrown_item.gd):
## heavier items (weapons) thud once and settle, lighter ones (props) bounce a few
## times first. Runs single-process, so `multiplayer.is_server()` is true here (see
## test_holdables.gd's header) and `_advance` runs the same physics the server would.

const ThrownItemScene := preload("res://features/holdables/thrown_item.tscn")


func _spawn(item_id: String, from: Vector3, to: Vector3) -> ThrownItem:
	var item := ThrownItemScene.instantiate() as ThrownItem
	item.item_id = item_id
	item.from = from
	item.to = to
	add_child_autofree(item)
	return item


func test_a_heavy_weapon_settles_on_first_landing_without_bouncing() -> void:
	var item := _spawn("pistol", Vector3.ZERO, Vector3(4, 0, 0))
	item._advance(ThrownItem.FLIGHT_DURATION_S)
	assert_true(item.net_landed)
	assert_eq(item._bounce_index, 0)


func test_a_light_item_bounces_at_least_once_before_settling() -> void:
	var item := _spawn("banana", Vector3.ZERO, Vector3(4, 0, 0))
	item._advance(ThrownItem.FLIGHT_DURATION_S)
	assert_false(item.net_landed)
	assert_eq(item._bounce_index, 1)


func test_bounces_shrink_and_eventually_settle() -> void:
	var item := _spawn("banana", Vector3.ZERO, Vector3(4, 0, 0))
	var guard := 0
	while not item.net_landed and guard < 20:
		item._advance(1.0)
		guard += 1
	assert_true(item.net_landed)
	assert_lt(guard, 20)


func test_landing_position_matches_the_throw_target() -> void:
	var item := _spawn("pistol", Vector3.ZERO, Vector3(4, 0, 1))
	item._advance(ThrownItem.FLIGHT_DURATION_S)
	assert_true(item.net_position.is_equal_approx(Vector3(4, 0, 1)))
