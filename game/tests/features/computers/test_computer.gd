extends GutTest

const SCENE := preload("res://features/computers/computer.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var computer: ArcadeComputer
var player: Player


func before_each() -> void:
	computer = SCENE.instantiate() as ArcadeComputer
	add_child_autofree(computer)
	computer.set_process(false)
	player = PLAYER.instantiate() as Player
	player.position = Vector3(0, 0.9144, 2.5)
	player.net_position = player.position
	add_child_autofree(player)
	player.set_process(false)
	player.set_physics_process(false)
	await wait_physics_frames(2)


func after_each() -> void:
	if computer._view != null:
		computer._view.close(false)
	Controls.pause()


func _claim() -> void:
	computer.request_open()
	assert_eq(computer.state.owner, 1)


func test_server_start_punch_cooldown_miss_and_round_end() -> void:
	_claim()
	var epoch := int(computer.state.epoch)
	computer.request_click(epoch, Vector2i(160, 100))
	assert_false(computer.state.running, "Turkey cannot start a round")
	computer.request_click(epoch, Vector2i(160, 170))
	assert_true(computer.state.running)
	computer.request_click(epoch, Vector2i(-1, 100))
	computer.request_click(epoch, Vector2i(400, 100))
	assert_eq(computer.state.score, 0)
	computer.request_click(epoch, Vector2i(160, 100))
	computer.request_click(epoch, Vector2i(160, 100))
	assert_eq(computer.state.score, 10, "Spam is rate limited")
	computer.advance(30)
	assert_false(computer.state.running)
	assert_eq(computer.state.best, 10)
	computer.request_click(epoch, Vector2i(160, 100))
	assert_eq(computer.state.score, 10, "No punches after time expires")
	computer.request_click(epoch, Vector2i(160, 170))
	assert_eq(computer.state.score, 0)
	assert_eq(computer.state.best, 10)


func test_unknown_wrong_owner_stale_epoch_and_expired_lease_rejected() -> void:
	player.set_multiplayer_authority(2)
	computer.request_open()
	assert_eq(computer.state.owner, 0)
	player.set_multiplayer_authority(1)
	_claim()
	var epoch := int(computer.state.epoch)
	computer.request_click(epoch - 1, Vector2i(160, 170))
	assert_false(computer.state.running)
	computer.state.owner = 2
	computer.request_click(epoch, Vector2i(160, 170))
	computer.request_close(epoch)
	assert_eq(computer.state.owner, 2)
	assert_false(computer.state.running)
	computer.state.owner = 1
	computer._lease = -1
	computer.keep_alive(epoch)
	computer.request_click(epoch, Vector2i(160, 170))
	assert_false(computer.state.running)
	computer.advance(0)
	assert_eq(computer.state.owner, 0)


func test_range_facing_occlusion_and_respawn_release() -> void:
	assert_true(computer.can_use(player))
	player.net_yaw = PI
	assert_false(computer.can_use(player))
	player.net_yaw = 0
	player.net_position.z = -2
	assert_false(computer.can_use(player))
	player.net_position.z = 20
	computer.request_open()
	assert_eq(computer.state.owner, 0)
	player.net_position.z = 2.5
	_claim()
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3, 3, 0.1)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector3(0, 1.5, 1)
	add_child_autofree(wall)
	await wait_physics_frames(2)
	assert_false(computer.can_use(player))
	computer.request_click(int(computer.state.epoch), Vector2i(160, 170))
	assert_false(computer.state.running)
	player.net_position = Vector3(2, 1, 5)
	computer.advance(0)
	assert_eq(computer.state.owner, 0)


func test_handoff_retains_best_and_old_session_cannot_close_new_one() -> void:
	_claim()
	var epoch := int(computer.state.epoch)
	computer.state.best = 100
	computer._peer_left(1)
	assert_eq(computer.state.owner, 0)
	assert_eq(computer.state.best, 100)
	computer._view.close(false)
	_claim()
	assert_gt(int(computer.state.epoch), epoch)
	computer.request_close(epoch)
	assert_eq(computer.state.owner, 1)
	computer._mode_changed(Network.Mode.OFFLINE)
	assert_eq(computer.state, ArcadeComputer.initial_state())


func test_competing_claim_does_not_steal_or_restart_session() -> void:
	_claim()
	computer.state.owner = 2
	var epoch := int(computer.state.epoch)
	computer.request_open()
	assert_eq(computer.state.owner, 2)
	assert_eq(computer.state.epoch, epoch)


func test_world_click_modal_and_camera_restore() -> void:
	var camera := player.get_node("Camera") as Camera3D
	camera.make_current()
	_claim()
	var view: Node3D = computer._view
	assert_true(view.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_eq(get_viewport().get_camera_3d(), view.camera)
	var center: Vector2 = view.camera.unproject_position(view.screen.global_position)
	assert_eq(view.screen_point(center), Vector2i(160, 100))
	computer.request_click(int(computer.state.epoch), Vector2i(160, 170))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = center
	view._unhandled_input(click)
	assert_eq(computer.state.score, 10)
	view.close(false)
	assert_eq(get_viewport().get_camera_3d(), camera)
	assert_false(view.is_in_group(&"modal_ui"))
	assert_eq(computer.state.owner, 0)


func test_snapshot_contains_late_join_presentation_without_hit_replay() -> void:
	var screen := preload("res://features/computers/turkey_screen.gd").new()
	add_child_autofree(screen)
	var snapshot := ArcadeComputer.initial_state()
	snapshot.score = 120
	snapshot.best = 200
	snapshot.hits = 12
	snapshot.seconds = 14
	snapshot.running = true
	screen.set_state(snapshot)
	assert_eq(screen.state, snapshot)
	assert_eq(screen.flash, 0.0, "Late join must not replay old punches")
	var sync := computer.get_node("Sync") as MultiplayerSynchronizer
	assert_true(sync.replication_config.property_get_spawn(^".:state"))


func test_touch_and_controller_activate_the_same_screen_regions() -> void:
	_claim()
	var view: Node3D = computer._view
	var start_world: Vector3 = view.screen.to_global(Vector3(0, -0.31, 0))
	var touch := InputEventScreenTouch.new()
	touch.position = view.camera.unproject_position(start_world)
	touch.pressed = true
	view._unhandled_input(touch)
	assert_true(computer.state.running)
	view.cursor = Vector2(160, 100)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	view._input(button)
	assert_eq(computer.state.score, 10)
	view._focus_lost()
	assert_false(view.is_in_group(&"modal_ui"))
	assert_eq(computer.state.owner, 0)


func test_two_computers_keep_independent_games() -> void:
	var second := SCENE.instantiate() as ArcadeComputer
	second.position.x = 8
	add_child_autofree(second)
	second.set_process(false)
	_claim()
	computer.request_click(int(computer.state.epoch), Vector2i(160, 170))
	computer.request_click(int(computer.state.epoch), Vector2i(160, 100))
	assert_eq(second.state, ArcadeComputer.initial_state())
