extends GutTest

const InspectScene := preload("res://features/gun_inspect/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const HandScene := preload("res://features/holdables/hand.tscn")
const RigScene := preload("res://features/gun_machine/gun_rig.tscn")

var _inspect: Node
var _player: Player
var _hand: Hand
var _device: Controls.Device
var _playing: bool


func before_each() -> void:
	_device = Controls.device
	_playing = Controls.playing
	Controls.device = Controls.Device.GAMEPAD
	Controls.playing = true
	_player = PlayerScene.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	_hand = HandScene.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hand.set_process(false)
	_inspect = InspectScene.instantiate()
	add_child_autofree(_inspect)
	_inspect.set_process(false)


func after_each() -> void:
	Controls.device = _device
	Controls.playing = _playing
	await get_tree().process_frame


func test_each_fixed_gun_inspects_without_changing_its_grip_or_recoil_transform() -> void:
	for id: String in ["pistol", "smg", "shotgun", "awp"]:
		_hand.net_item_id = id
		_hand._process(0.0)
		var view := _hand.held_view()
		var rest := view.transform
		assert_true(_inspect.try_inspect(), id)
		_inspect._process(0.7)
		_hand._process(0.0)
		assert_false(_hand.inspect_transform.is_equal_approx(Transform3D.IDENTITY), id)
		assert_true(view.transform.is_equal_approx(rest), "Recoil owns the nested view transform")
		assert_true(
			_hand.global_transform.is_equal_approx(
				_hand._mount_transform(_player) * _hand.inspect_transform
			)
		)
		_inspect._process(10.0)
		assert_true(_hand.inspect_transform.is_equal_approx(Transform3D.IDENTITY))


func test_f_key_starts_inspection_and_firing_cancels_it() -> void:
	var flashlight := preload("res://features/flashlight/feature.tscn").instantiate()
	add_child_autofree(flashlight)
	_hand.net_item_id = "pistol"
	var inspect_event := InputEventKey.new()
	inspect_event.physical_keycode = KEY_F
	inspect_event.pressed = true
	flashlight._unhandled_input(inspect_event)
	assert_true(flashlight.enabled_peers.is_empty(), "F must not toggle the flashlight")
	_inspect._unhandled_input(inspect_event)
	_inspect._process(0.7)
	assert_false(_hand.inspect_transform.is_equal_approx(Transform3D.IDENTITY))
	var fire := InputEventAction.new()
	fire.action = &"primary_action"
	fire.pressed = true
	_inspect._input(fire)
	assert_true(_hand.inspect_transform.is_equal_approx(Transform3D.IDENTITY))


func test_switch_menu_and_third_person_cancel_and_non_weapons_do_not_inspect() -> void:
	_hand.net_item_id = "banana"
	assert_false(_inspect.try_inspect())
	_hand.net_item_id = "awp"
	assert_true(_inspect.try_inspect())
	_inspect._process(0.7)
	_hand.net_item_id = "smg"
	_inspect._process(0.0)
	assert_true(_hand.inspect_transform.is_equal_approx(Transform3D.IDENTITY))
	assert_true(_inspect.try_inspect())
	_inspect._process(0.7)
	Controls.playing = false
	_inspect._process(0.0)
	assert_true(_hand.inspect_transform.is_equal_approx(Transform3D.IDENTITY))
	assert_false(_inspect.try_inspect())
	Controls.playing = true
	(_player.get_node("Body") as Node3D).visible = true
	assert_false(_inspect.try_inspect())


func test_generated_families_inspect_and_reload_or_holster_cancel() -> void:
	var rig := RigScene.instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	rig.set_process(false)
	for ammo_type: int in GunGenerator.AmmoType.size():
		var stats := GunGenerator.generate(RandomNumberGenerator.new())
		stats["ammo_type"] = ammo_type
		rig.equip(stats)
		assert_true(_inspect.try_inspect())
		_inspect._process(0.7)
		assert_false(rig.inspect_transform.is_equal_approx(Transform3D.IDENTITY))
		var reload_event := InputEventAction.new()
		reload_event.action = &"gun_reload"
		reload_event.pressed = true
		_inspect._input(reload_event)
		assert_true(rig.inspect_transform.is_equal_approx(Transform3D.IDENTITY))
	assert_true(_inspect.try_inspect())
	_inspect._process(0.7)
	rig.holster()
	_inspect._process(0.0)
	assert_true(rig.inspect_transform.is_equal_approx(Transform3D.IDENTITY))


func test_remote_hand_is_never_animated_and_repeated_inspect_does_not_restart() -> void:
	var remote := HandScene.instantiate() as Hand
	remote.peer_id = 2
	remote.net_item_id = "awp"
	add_child_autofree(remote)
	remote.set_process(false)
	_hand.net_item_id = "pistol"
	assert_true(_inspect.try_inspect())
	_inspect._process(0.7)
	assert_false(_inspect.try_inspect())
	assert_true(remote.inspect_transform.is_equal_approx(Transform3D.IDENTITY))
