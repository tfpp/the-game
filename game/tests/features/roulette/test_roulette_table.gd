extends GutTest

const TableScene := preload("res://features/roulette/table.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _table: RouletteTable


func before_each() -> void:
	_table = TableScene.instantiate() as RouletteTable
	add_child_autofree(_table)
	_table.set_process(false)


func test_wheel_covers_every_pocket_with_correct_colors() -> void:
	var wheel := RouletteWheel.new()
	var seen: Dictionary = {}
	for _spin: int in 2000:
		var result := wheel.next_result()
		assert_between(result, 0, RouletteWheel.POCKET_COUNT - 1)
		seen[result] = true
	assert_eq(seen.size(), RouletteWheel.POCKET_COUNT, "every pocket should eventually appear")
	assert_eq(RouletteWheel.color_for(0), "green")
	assert_eq(RouletteWheel.color_for(1), "red")
	assert_eq(RouletteWheel.color_for(2), "black")
	var reds := 0
	var blacks := 0
	for number: int in range(1, 37):
		if RouletteWheel.color_for(number) == "red":
			reds += 1
		else:
			blacks += 1
	assert_eq(reds, 18)
	assert_eq(blacks, 18)


func test_wheel_has_a_green_double_zero() -> void:
	assert_eq(RouletteWheel.POCKET_COUNT, 38)
	assert_eq(RouletteWheel.color_for(RouletteWheel.DOUBLE_ZERO), "green")
	assert_eq(RouletteWheel.label_for(RouletteWheel.DOUBLE_ZERO), "00")
	assert_eq(RouletteWheel.label_for(0), "0")
	assert_eq(RouletteWheel.label_for(17), "17")


func test_ball_spins_then_settles_once() -> void:
	_table._begin_spin(1, "Alice")
	assert_true(_table.state["spinning"])
	_table._advance(1.0)
	assert_true(_table.state["spinning"])
	assert_between(int(_table.state["ball"]), 0, RouletteWheel.POCKET_COUNT - 1)
	_table._advance(2.5)
	assert_false(_table.state["spinning"])
	assert_eq(int(_table.state["ball"]), int(_table.state["number"]))
	assert_eq(str(_table.state["color"]), RouletteWheel.color_for(int(_table.state["number"])))


func test_unknown_player_cannot_start_a_spin() -> void:
	_table.request_spin()
	assert_eq(_table.state["spin"], 0)


func test_busy_table_rejects_requests_without_consuming_another_spin() -> void:
	_table._begin_spin(1, "Alice")
	_table.request_spin()
	assert_eq(_table.state["spin"], 1)
	assert_eq(_table.state["operator"], "Alice")


func test_server_checks_range_facing_and_obstructions() -> void:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(2)
	player.position = Vector3(0, 0.9144, 2.5)
	player.net_position = player.position
	add_child_autofree(player)
	await get_tree().physics_frame
	assert_true(_table.can_use(player))
	player.net_position.z = 10
	assert_false(_table.can_use(player))
	player.net_position.z = 2.5
	player.net_yaw = PI
	assert_false(_table.can_use(player))
	player.net_yaw = 0
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 0.2)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(0, 1.0, 1.7)
	add_child_autofree(wall)
	await get_tree().physics_frame
	assert_false(_table.can_use(player), "Cannot use through a wall")


func test_table_can_be_used_from_either_long_side() -> void:
	var south := PlayerScene.instantiate() as Player
	south.set_multiplayer_authority(2)
	south.position = Vector3(0, 0.9144, 2.5)
	south.net_position = south.position
	south.net_yaw = 0
	add_child_autofree(south)
	var north := PlayerScene.instantiate() as Player
	north.set_multiplayer_authority(3)
	north.position = Vector3(0, 0.9144, -2.5)
	north.net_position = north.position
	north.net_yaw = PI
	add_child_autofree(north)
	await get_tree().physics_frame
	assert_true(_table.can_use(south))
	assert_true(_table.can_use(north))


func test_switching_sessions_clears_old_state() -> void:
	_table._begin_spin(1, "Alice")
	_table._advance(4.0)
	_table._on_mode_changed(Network.Mode.OFFLINE)
	assert_eq(_table.state, RouletteTable.initial_state())


func test_wheel_order_lists_every_pocket_once_with_00_opposite_0() -> void:
	var order := RouletteWheel.WHEEL_ORDER
	assert_eq(order.size(), RouletteWheel.POCKET_COUNT)
	for number: int in RouletteWheel.POCKET_COUNT:
		assert_true(order.has(number), "pocket %d is on the wheel" % number)
	assert_eq(RouletteWheel.wheel_index(0), 0)
	assert_eq(RouletteWheel.wheel_index(RouletteWheel.DOUBLE_ZERO), RouletteWheel.POCKET_COUNT / 2)
	for index: int in order.size():
		var here := RouletteWheel.color_for(order[index])
		var next := RouletteWheel.color_for(order[(index + 1) % order.size()])
		if here != "green" and next != "green":
			assert_ne(here, next, "red and black alternate around the wheel")


func test_view_shows_the_model_with_a_rotor_and_ball() -> void:
	var view := _table.get_node("View") as RouletteTableView
	assert_not_null(view.rotor)
	assert_not_null(view.ball)
	assert_eq(
		view.ball.get_parent(), view.rotor.get_parent(), "ball orbits separately from the rotor"
	)


func test_ball_rolls_then_settles_in_the_winning_pocket() -> void:
	var view := _table.get_node("View") as RouletteTableView
	_table._begin_spin(1, "Alice")
	view._process(0.0)
	var start := view.ball.position
	var start_basis := view.ball.basis
	view.animate(0.5)
	assert_gt(Vector2(view.ball.position.x, view.ball.position.z).length(), 0.3, "on the track")
	assert_ne(view.ball.position, start)
	assert_ne(view.ball.basis, start_basis, "the ball rolls as it moves")
	_table._advance(4.0)
	var number := int(_table.state["number"])
	view._process(0.0)
	for _frame: int in 60:
		view.animate(1.0 / 30.0)
	var angle := view.pocket_angle(number)
	var expected := Vector3(sin(angle), 0, -cos(angle)) * RouletteTableView.POCKET_RADIUS_M
	expected.y = RouletteTableView.ball_height(RouletteTableView.POCKET_RADIUS_M)
	assert_almost_eq(view.ball.position, expected, Vector3.ONE * 0.001)
	view.animate(0.5)
	angle = view.pocket_angle(number)
	assert_almost_eq(view.ball.position.x, sin(angle) * RouletteTableView.POCKET_RADIUS_M, 0.001)
	assert_almost_eq(view.ball.position.z, -cos(angle) * RouletteTableView.POCKET_RADIUS_M, 0.001)


func test_late_joiner_sees_the_ball_already_in_the_winning_pocket() -> void:
	var view := _table.get_node("View") as RouletteTableView
	_table.state = {
		"spin": 4, "spinning": false, "ball": 17, "number": 17, "color": "black", "operator": "Bob"
	}
	view._process(0.0)
	var angle := view.pocket_angle(17)
	assert_almost_eq(view.ball.position.x, sin(angle) * RouletteTableView.POCKET_RADIUS_M, 0.001)
	assert_almost_eq(view.ball.position.z, -cos(angle) * RouletteTableView.POCKET_RADIUS_M, 0.001)
