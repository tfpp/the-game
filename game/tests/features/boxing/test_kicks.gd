extends GutTest

const BOXING := preload("res://features/boxing/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const TARGET := preload("res://features/shooting_gallery/humanoid_target.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const COMBAT := preload("res://features/combat/feature.tscn")

var boxing: Boxing
var player: Player
var target: HumanoidTarget
var combat: Combat


func before_each() -> void:
	combat = COMBAT.instantiate() as Combat
	add_child_autofree(combat)
	combat.set_process(false)
	boxing = BOXING.instantiate() as Boxing
	add_child_autofree(boxing)
	player = PLAYER.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_physics_process(false)
	target = TARGET.instantiate() as HumanoidTarget
	add_child_autofree(target)
	target.global_position = player.net_position + Vector3(0, -0.9, -1)
	await wait_physics_frames(2)


func test_quick_and_charged_kicks_use_existing_dummy_rules() -> void:
	assert_eq(boxing.punch(1, 0.0, true), target)
	assert_false(target.net_ragdoll)
	boxing._ready_at_ms.clear()
	assert_eq(boxing.punch(1, 1.0, true), target)
	assert_true(target.net_ragdoll)
	assert_almost_eq(target.net_fall_dir, Vector3.FORWARD, Vector3.ONE * 0.001)


func test_kicks_work_with_items_but_punches_still_do_not() -> void:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.net_item_id = "pistol"
	assert_null(boxing.punch(1, 1.0))
	assert_eq(boxing.punch(1, 1.0, true), target)


func test_release_requires_matching_press_and_server_times_charge() -> void:
	boxing.request_punch(true)
	assert_false(target.net_ragdoll)
	assert_true(boxing.leg_pose(1).is_empty())
	boxing.request_wind_up(true)
	boxing._wind_up_ms[1] -= 1000
	var started: int = boxing._wind_up_ms[1]
	boxing.request_wind_up(true)
	assert_eq(boxing._wind_up_ms[1], started, "Repeat presses cannot reset the charge")
	boxing.request_punch(false)
	assert_false(target.net_ragdoll, "Punch cannot release a kick charge")
	boxing.request_punch(true)
	assert_true(target.net_ragdoll)
	assert_false(boxing._wind_up_ms.has(1))
	assert_false(boxing.leg_pose(1).is_empty())


func test_local_action_only_works_during_gameplay_and_pause_cancels_charge() -> void:
	var saved_device := Controls.device
	var saved_playing := Controls.playing
	var saved_mouse := Input.mouse_mode
	Controls.device = Controls.Device.TOUCH
	Controls.pause()
	var press := InputEventAction.new()
	press.action = &"kick"
	press.pressed = true
	var release := InputEventAction.new()
	release.action = &"kick"
	boxing._unhandled_input(press)
	assert_false(boxing._wind_up_ms.has(1), "Menus cannot begin a kick")
	Controls.start()
	boxing._unhandled_input(press)
	assert_true(boxing._wind_up_ms.has(1))
	boxing._wind_up_ms[1] -= 1000
	Controls.pause()
	boxing._unhandled_input(release)
	assert_false(boxing._wind_up_ms.has(1))
	assert_false(target.net_ragdoll, "Pause cancels instead of releasing a hidden kick")
	Controls.start()
	boxing._unhandled_input(press)
	boxing._wind_up_ms[1] -= 1000
	boxing._unhandled_input(release)
	assert_true(target.net_ragdoll, "A fresh press/release still works offline")
	Controls.pause()
	Controls.device = saved_device
	Controls.playing = saved_playing
	Input.mouse_mode = saved_mouse


func test_punch_and_kick_share_cooldown() -> void:
	boxing.punch(1, 0.0, true)
	assert_null(boxing.punch(1, 1.0))
	assert_null(boxing.punch(1, 1.0, true))
	boxing.request_wind_up(true)
	assert_false(boxing._wind_up_ms.has(1))


func test_absent_or_dead_sender_cannot_kick_and_respawn_clears_charge() -> void:
	assert_null(boxing.punch(7, 1.0, true))
	boxing.request_wind_up(true)
	combat.apply_damage(1, 100.0, 7)
	assert_false(boxing._wind_up_ms.has(1))
	assert_null(boxing.punch(1, 1.0, true))
	boxing.request_wind_up(true)
	assert_false(boxing._wind_up_ms.has(1))
	combat._announce_respawn(1)
	boxing.request_punch(true)
	assert_false(target.net_ragdoll, "Old charge cannot survive respawn")
	boxing.request_wind_up(true)
	assert_true(boxing._wind_up_ms.has(1))


func test_cancel_disconnect_and_session_clear_pending_kicks() -> void:
	boxing.request_wind_up(true)
	boxing.request_cancel()
	boxing.request_punch(true)
	assert_true(boxing.leg_pose(1).is_empty())
	boxing.request_wind_up(true)
	boxing._forget_peer(1)
	assert_false(boxing._wind_up_kick.has(1))
	boxing._kicks.swing(1, true)
	boxing._on_mode_changed(Network.Mode.OFFLINE)
	assert_true(boxing.leg_pose(1).is_empty())


func test_kick_cannot_reach_through_a_wall_or_beyond_range() -> void:
	target.global_position.z = -1.8
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 4, 0.1)
	collision.shape = shape
	wall.add_child(collision)
	add_child_autofree(wall)
	wall.position = Vector3(0, 0, -1.0)
	await wait_physics_frames(2)
	assert_null(boxing.punch(1, 1.0, true))
	assert_false(target.net_ragdoll)
	wall.position.z = 10
	target.position.z = -5
	boxing._ready_at_ms.clear()
	await wait_physics_frames(2)
	assert_null(boxing.punch(1, 1.0, true))


func test_damage_increases_with_hold_through_existing_combat() -> void:
	target.position.z = 10
	var victim := PLAYER.instantiate() as Player
	victim.name = "2"
	victim.set_multiplayer_authority(2)
	add_child_autofree(victim)
	victim.set_physics_process(false)
	victim.position = Vector3(0, 0, -1)
	await wait_physics_frames(2)
	boxing.punch(1, 0.0, true)
	assert_eq(combat.health_for(2), 93.75)
	boxing._ready_at_ms.clear()
	boxing.punch(1, 1.0, true)
	assert_eq(combat.health_for(2), 68.75)
