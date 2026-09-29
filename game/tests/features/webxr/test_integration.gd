extends GutTest

const Rig := preload("res://features/webxr/vr_rig.gd")
const Interaction := preload("res://features/interaction/interaction.gd")
const ThirdPerson := preload("res://features/third_person/third_person.gd")
const PLAYER := preload("res://core/player/player.tscn")

var player: Player
var rig: Rig
var saved_device: int
var saved_playing: bool


func before_each() -> void:
	saved_device = Controls.device
	saved_playing = Controls.playing
	Controls.device = Controls.Device.XR
	Controls.start()
	player = PLAYER.instantiate() as Player
	add_child_autofree(player)
	player.set_physics_process(false)
	rig = Rig.new()
	add_child_autofree(rig)
	rig.attach(player)
	rig.set_physics_process(false)


func after_each() -> void:
	rig.release_actions()
	Controls.clear_input()
	Controls.device = saved_device
	Controls.playing = saved_playing
	get_viewport().use_xr = false


func test_trigger_reuses_loot_server_request_and_prompt_range() -> void:
	var interaction := Interaction.new()
	add_child_autofree(interaction)
	var hand := preload("res://features/holdables/hand.tscn").instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	var loot := preload("res://features/loot/loot_container.tscn").instantiate() as LootContainer
	add_child_autofree(loot)
	assert_eq(interaction.target_text(), "Search container")
	rig._button(&"trigger_click", true)
	assert_true(loot.net_searched, "Use still runs the validated offline server request")
	assert_eq(interaction.target_text(), "Searched container (empty)")
	loot.reset()
	loot.position = Vector3(100, 0, 0)
	assert_eq(interaction.target_text(), "")
	rig._button(&"trigger_click", true)
	assert_false(loot.net_searched, "XR cannot bypass the existing interaction range")
	loot.request_search()
	assert_false(loot.net_searched, "Server range check remains in force")


func test_third_person_yields_during_vr_and_returns_afterwards() -> void:
	var third := ThirdPerson.new()
	add_child_autofree(third)
	third.enabled = true
	get_viewport().use_xr = true
	third._process(0.0)
	assert_false((player.get_node("Body") as Node3D).visible)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F3
	key.pressed = true
	third._unhandled_input(key)
	assert_true(third.enabled, "VR leaves the saved F3 preference alone")
	get_viewport().use_xr = false
	third._process(0.0)
	assert_true((player.get_node("Body") as Node3D).visible)


func test_mobile_resize_preserves_xr_render_size_and_restores_phone_budget() -> void:
	var style := RetroStyle.new()
	add_child_autofree(style)
	style.mobile = true
	var window := get_window()
	var old_ui_size := window.content_scale_size
	var old_scale := get_viewport().scaling_3d_scale
	get_viewport().use_xr = true
	style._configure_viewport()
	assert_eq(get_viewport().scaling_3d_scale, 1.0)
	get_viewport().use_xr = false
	style._configure_viewport()
	assert_almost_eq(
		get_viewport().scaling_3d_scale, RetroStyle.mobile_scale(Vector2(window.size)), 0.001
	)
	window.content_scale_size = old_ui_size
	get_viewport().scaling_3d_scale = old_scale


func test_grip_release_pause_and_tracking_loss_clear_held_actions() -> void:
	Controls.ensure_action(&"primary_action", [])
	Controls.ensure_action(&"gun_fire", [])
	rig._button(&"grip_click", true)
	assert_true(Input.is_action_pressed(&"gun_fire"))
	assert_true(Input.is_action_pressed(&"primary_action"))
	Controls.pause()
	assert_false(Input.is_action_pressed(&"gun_fire"))
	assert_false(Input.is_action_pressed(&"primary_action"))
	Controls.start()
	rig._button(&"grip_click", true)
	rig._physics_process(0.0)  # No head tracker in CI.
	assert_false(Input.is_action_pressed(&"gun_fire"))
	rig._button(&"grip_click", true)
	rig._released(&"grip_click")
	assert_false(Input.is_action_pressed(&"gun_fire"))
