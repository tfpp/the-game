extends GutTest

const Scene := preload("res://features/scumm_arcade/cabinet.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var cabinet: ScummArcadeCabinet


func before_each() -> void:
	cabinet = Scene.instantiate() as ScummArcadeCabinet
	cabinet.position = Vector3.ZERO
	add_child_autofree(cabinet)
	cabinet.set_process(false)


func test_unknown_peers_cannot_control_restart_or_submit_inputs() -> void:
	cabinet.request_control()
	cabinet.request_input(1, [1, 100, 100, 0])
	cabinet.request_restart()
	assert_eq(cabinet.state["owner"], 0)
	assert_eq(cabinet.state["epoch"], 1)
	assert_eq(cabinet.session.pending, [])


func test_interaction_checks_distance_front_facing_and_occlusion() -> void:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(2)
	player.position = Vector3(0, 0.9144, 2.5)
	player.net_position = player.position
	add_child_autofree(player)
	await get_tree().physics_frame
	assert_true(cabinet.can_use(player))
	player.net_yaw = PI
	assert_false(cabinet.can_use(player))
	player.net_yaw = 0
	player.net_position.z = -2
	assert_false(cabinet.can_use(player))
	player.net_position.z = 6
	assert_false(cabinet.can_use(player))


func test_disconnect_releases_controls_and_retains_game_history() -> void:
	cabinet.state["owner"] = 42
	cabinet.state["operator"] = "Alice"
	cabinet.session.enqueue([1, 20, 30, 0])
	cabinet.session.advance()
	cabinet._peer_left(42)
	assert_eq(cabinet.state["owner"], 0)
	assert_eq(cabinet.state["operator"], "")
	assert_eq(cabinet.session.tick, 1)
	assert_eq(cabinet.session.history[0], [[1, 20, 30, 0]])
	assert_eq(cabinet.session.pending[0][0], 2)


func test_floor_has_independent_games_and_display_rejects_input() -> void:
	var FloorScene := preload("res://features/scumm_arcade/feature.tscn")
	var floor_node := FloorScene.instantiate()
	add_child_autofree(floor_node)
	assert_eq(floor_node.get_child_count(), 5)
	var signatures: Dictionary = {}
	for machine: ScummArcadeCabinet in floor_node.get_children():
		machine.set_process(false)
		signatures[machine._runtime_id] = true
		assert_eq(machine.session.tick, 0)
		assert_ne(machine.session, cabinet.session)
	assert_eq(signatures.size(), 5, "Demo data is part of each runtime identity")
	var display := floor_node.get_node("DayOfTheTentacle") as ScummArcadeCabinet
	display.state["owner"] = 1
	display.request_input(1, [1, 100, 100, 0])
	assert_eq(display.session.pending, [], "Display cannot accept gameplay input")
	var other := floor_node.get_node("SamAndMax") as ScummArcadeCabinet
	other.session.advance()
	display.request_restart()
	assert_eq(display.state["epoch"], 2)
	assert_eq(other.state["epoch"], 1)
	assert_eq(other.session.tick, 1, "Restarting another cabinet preserves this game")


func test_world_screen_input_releases_outside_and_look_does_not_click() -> void:
	var player := PlayerScene.instantiate() as Player
	player.position = Vector3(0, 0.9144, 2.5)
	add_child_autofree(player)
	player.set_process(false)
	player.set_physics_process(false)
	var view := cabinet._view
	var camera := player.get_node("Camera") as Camera3D
	var original_fov := camera.fov
	view.open()
	assert_lt(camera.fov, original_fov)
	view.open()  # Reopening must not compound the zoom or overwrite its original value.
	camera.look_at(view._world_screen.global_position)
	await get_tree().physics_frame
	cabinet.state["owner"] = 1
	var point := camera.unproject_position(view._world_screen.global_position)
	assert_eq(view._screen_point(point), Vector2i(160, 100))
	var down := InputEventMouseButton.new()
	down.position = point
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	view._unhandled_input(down)
	assert_eq(cabinet.session.pending.back()[0], 1)
	var up := InputEventMouseButton.new()
	up.position = Vector2(-50, -50)
	up.button_index = MOUSE_BUTTON_LEFT
	view._input(up)
	assert_eq(cabinet.session.pending.back()[0], 2)
	assert_true(view._held_buttons.is_empty())
	var count := cabinet.session.pending.size()
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	view._unhandled_input(middle)
	var motion := InputEventMouseMotion.new()
	motion.screen_relative = Vector2(100, 20)
	view._input(motion)
	assert_lt(player.yaw, 0.0)
	assert_lt(player.pitch, 0.0)
	assert_false(Controls.gameplay_active())
	assert_eq(cabinet.session.pending.size(), count, "Looking does not send game clicks")
	view.close(false)
	assert_eq(camera.fov, original_fov)
	assert_false(view._look_drag)
	assert_eq(cabinet.state["owner"], 0)


func test_world_screen_is_blocked_by_foreground_geometry() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.position = Vector3(0, 1.774, 2.5)
	camera.look_at(cabinet._view._world_screen.global_position)
	camera.make_current()
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 3, 0.1)
	collision.shape = shape
	wall.add_child(collision)
	wall.position = Vector3(0, 1.5, 1.5)
	add_child_autofree(wall)
	await get_tree().physics_frame
	var point := camera.unproject_position(cabinet._view._world_screen.global_position)
	assert_eq(cabinet._view._screen_point(point), Vector2i(-1, -1))


func test_enter_waits_for_runtime_then_takes_free_controls_and_leave_releases() -> void:
	var player := PlayerScene.instantiate() as Player
	player.position = Vector3(0, 0.9144, 2.5)
	add_child_autofree(player)
	player.set_process(false)
	player.set_physics_process(false)
	await get_tree().physics_frame
	var view := cabinet._view
	view.set_process(false)
	view.open()
	view._process(1.0)
	assert_eq(cabinet.state["owner"], 0, "Wait until the interpreter is ready")
	cabinet.local_tick = 10
	cabinet.state["tick"] = 10
	cabinet._ready_peers[1] = 10
	cabinet.state["owner"] = 42
	view._process(1.0)
	assert_eq(cabinet.state["owner"], 42, "Watching cannot steal another player's turn")
	cabinet.state["owner"] = 0
	view._process(1.0)
	assert_eq(cabinet.state["owner"], 1, "A free cabinet is claimed automatically")
	view._process(0.1)
	assert_eq(view._panel.text, "Release controls & leave")
	view._panel.pressed.emit()
	assert_eq(cabinet.state["owner"], 0)
	assert_false(view._panel.visible)
	assert_false(view.is_in_group(&"modal_ui"))
	view._process(2.0)
	assert_eq(cabinet.state["owner"], 0, "Leaving stops automatic control requests")
	Controls.pause()
