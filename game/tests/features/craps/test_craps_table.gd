extends GutTest

const TABLE := preload("res://features/craps/table.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _table: CrapsTable


func before_each() -> void:
	_table = TABLE.instantiate() as CrapsTable
	add_child_autofree(_table)
	_table.set_process(false)


func test_all_36_come_out_combinations() -> void:
	var wins := 0
	var losses := 0
	var points := 0
	for a: int in range(1, 7):
		for b: int in range(1, 7):
			var result := CrapsTable.resolve_roll(0, a + b)
			if a + b in [7, 11]:
				assert_eq(result, {"point": 0, "outcome": "win"})
				wins += 1
			elif a + b in [2, 3, 12]:
				assert_eq(result, {"point": 0, "outcome": "lose"})
				losses += 1
			else:
				assert_eq(result, {"point": a + b, "outcome": "point"})
				points += 1
	assert_eq(wins, 8)
	assert_eq(losses, 4)
	assert_eq(points, 24)


func test_every_point_and_total() -> void:
	for point: int in [4, 5, 6, 8, 9, 10]:
		for total: int in range(2, 13):
			var result := CrapsTable.resolve_roll(point, total)
			if total == point:
				assert_eq(result, {"point": 0, "outcome": "win"})
			elif total == 7:
				assert_eq(result, {"point": 0, "outcome": "lose"})
			else:
				assert_eq(result, {"point": point, "outcome": "continue"})


func test_roll_timing_point_continuation_and_new_round() -> void:
	_table._begin_roll("Alice")
	_table._dice = Vector2i(2, 3)
	_table._advance(1.0)
	assert_true(_table.state["rolling"])
	assert_eq(_table.state["point"], 0, "No early result")
	_table._advance(1.1)
	assert_eq(_table.state["point"], 5)
	_table._begin_roll("Bob")
	_table._dice = Vector2i(6, 5)
	_table._advance(2.1)
	assert_eq(_table.state["point"], 5, "Eleven does not win after come-out")
	assert_eq(_table.state["operator"], "Bob", "Anyone may continue the round")
	_table._begin_roll("Bob")
	_table._dice = Vector2i(1, 4)
	_table._advance(2.1)
	assert_eq(_table.state["outcome"], "win")
	assert_eq(_table.state["point"], 0)
	var settled := _table.state.duplicate(true)
	_table._advance(20.0)
	assert_eq(_table.state, settled, "Settlement happens only once")
	_table._begin_roll("Carol")
	_table._dice = Vector2i(1, 1)
	_table._advance(2.1)
	assert_eq(_table.state["outcome"], "lose", "Next roll is a new come-out")


func test_requests_reject_unknown_player_and_busy_table() -> void:
	_table.request_roll()
	assert_eq(_table.state["roll"], 0)
	_table._begin_roll("Alice")
	_table.request_roll()
	_table._begin_roll("Bob")
	assert_eq(_table.state["roll"], 1)
	assert_eq(_table.state["operator"], "Alice")
	assert_between(_table._dice.x, 1, 6)
	assert_between(_table._dice.y, 1, 6)


func test_use_contract_and_server_request_validation() -> void:
	var player := PLAYER.instantiate() as Player
	player.position = Vector3(0, 0.9144, 2.5)
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	await wait_physics_frames(2)
	assert_true(_table.is_in_group(&"interactables"))
	assert_true(_table.can_use(player))
	assert_string_contains(_table.interaction_text(), "come-out")
	player.net_position.z = 10
	_table.request_roll()
	assert_eq(_table.state["roll"], 0)
	player.net_position.z = 2.5
	player.net_yaw = PI
	_table.request_roll()
	assert_eq(_table.state["roll"], 0)
	player.net_yaw = 0
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 0.2)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(0, 1, 1.7)
	add_child_autofree(wall)
	await wait_physics_frames(2)
	_table.request_roll()
	assert_eq(_table.state["roll"], 0, "Wall blocks requests")
	wall.queue_free()
	await wait_physics_frames(2)
	_table.request_roll()
	assert_eq(_table.state["roll"], 1, "Eligible sender can roll")


func test_snapshot_replication_and_session_reset() -> void:
	var sync := _table.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:state")))
	_table._begin_roll("Alice")
	_table._on_mode_changed(Network.Mode.OFFLINE)
	_table._advance(10.0)
	assert_eq(_table.state, CrapsTable.initial_state())


func test_feature_placement_has_floor_and_clears_existing_attractions() -> void:
	var room := preload("res://world/room.tscn").instantiate() as Node3D
	add_child_autofree(room)
	var feature := preload("res://features/craps/feature.tscn").instantiate() as Node3D
	add_child_autofree(feature)
	await wait_physics_frames(3)
	var table := feature.get_node("Table") as CrapsTable
	assert_eq(table.global_position, Vector3(-6, -1.5, 0))
	var query := PhysicsRayQueryParameters3D.create(Vector3(-6, -1.4, 0), Vector3(-6, -2, 0))
	var hit := room.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "Casino floor supports the table")
	for z: float in [-2.5, 2.5]:
		var player := PLAYER.instantiate() as Player
		player.set_multiplayer_authority(20 if z > 0 else 21)
		player.position = Vector3(-6, -0.5856, z)
		player.net_position = player.position
		player.net_yaw = 0 if z > 0 else PI
		add_child_autofree(player)
		player.set_physics_process(false)
		await wait_physics_frames(2)
		assert_true(table.can_use(player), "Both long sides are reachable in the casino")
