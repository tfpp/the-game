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
	for number: int in range(1, RouletteWheel.POCKET_COUNT):
		if RouletteWheel.color_for(number) == "red":
			reds += 1
		else:
			blacks += 1
	assert_eq(reds, 18)
	assert_eq(blacks, 18)


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


func test_round_table_can_be_used_from_either_side() -> void:
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
