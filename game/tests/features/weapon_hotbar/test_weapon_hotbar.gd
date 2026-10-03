extends GutTest
## Integration coverage for features/weapon_hotbar/weapon_hotbar.gd: hotbar equip and
## scroll cycling reuse features/inventory's request_equip, and recoil hooks into
## features/holdables/hand.gd's `fired` signal. Runs single-process, so RPCs resolve
## to peer 1 the same way test_holdables.gd's do.

const PlayerScene := preload("res://core/player/player.tscn")
const HandScene := preload("res://features/holdables/hand.tscn")
const WeaponHotbarScene := preload("res://features/weapon_hotbar/feature.tscn")
const GunRigScene := preload("res://features/gun_machine/gun_rig.tscn")

var _player: Player
var _hand: Hand
var _hotbar: Node


func before_each() -> void:
	_player = PlayerScene.instantiate() as Player
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_hand = HandScene.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hotbar = WeaponHotbarScene.instantiate()
	add_child_autofree(_hotbar)
	await get_tree().physics_frame
	# Force the lazy fired-signal hookup now instead of waiting for an engine frame.
	_hotbar._process(0.0)


func after_each() -> void:
	# View replacements queue old meshes for deletion; flush before orphan checks.
	await get_tree().process_frame


func test_equip_slot_swaps_the_backpack_item_into_the_hand() -> void:
	_hand.inventory().backpack[2] = "pistol"
	_hotbar._equip_slot(_hand, 2)
	_finish_swap()
	assert_eq(_hand.net_item_id, "pistol")
	assert_eq(_hand.inventory().backpack[2], "")


func test_cycle_advances_through_every_occupied_slot_and_stashes_the_previous_item() -> void:
	_hand.inventory().backpack[1] = "pistol"
	_hand.inventory().backpack[4] = "smg"
	_hotbar._cycle(_hand, 1)
	_finish_swap()
	assert_eq(_hand.net_item_id, "pistol")
	_hotbar._cycle(_hand, 1)
	_finish_swap()
	assert_eq(_hand.net_item_id, "smg")
	assert_eq(
		_hand.inventory().backpack[4], "pistol", "The slot just pulled from holds what was in hand"
	)


func test_cycle_backward_wraps_to_the_previous_occupied_slot() -> void:
	_hand.inventory().backpack[1] = "pistol"
	_hand.inventory().backpack[4] = "smg"
	_hotbar._cycle(_hand, -1)
	_finish_swap()
	assert_eq(_hand.net_item_id, "smg")


func test_cycle_does_nothing_with_an_empty_backpack() -> void:
	_hotbar._cycle(_hand, 1)
	assert_eq(_hand.net_item_id, "")


func test_equip_rig_selects_a_holstered_gun_machine_gun() -> void:
	var rig := _spawn_rig()
	rig.equip(GunGenerator.generate(RandomNumberGenerator.new()))
	rig.holster()
	_hotbar._equip_rig(_hand)
	_finish_swap()
	assert_true(rig.is_active())


func test_equip_rig_does_nothing_without_a_rolled_gun() -> void:
	var rig := _spawn_rig()
	_hotbar._equip_rig(_hand)
	assert_false(rig.is_active())


func test_cycle_reaches_the_rig_slot_after_the_backpack_and_holsters_the_hand() -> void:
	var rig := _spawn_rig()
	rig.equip(GunGenerator.generate(RandomNumberGenerator.new()))
	_hand.inventory().backpack[1] = "pistol"
	_hotbar._cycle(_hand, 1)
	_finish_swap()
	assert_eq(_hand.net_item_id, "pistol")
	_hotbar._cycle(_hand, 1)
	_finish_swap()
	assert_eq(_hand.net_item_id, "", "The rig gun took over the hand")
	assert_true(rig.is_active())
	assert_true(_hand.inventory().backpack.has("pistol"), "The pistol was stowed, not lost")


func _finish_swap() -> void:
	var overlay := _player.get_node("FirstPersonView") as FirstPersonView
	overlay._advance_swap(FirstPersonView.SWAP_LOWER_SECONDS + FirstPersonView.SWAP_RAISE_SECONDS)


func test_fps_swap_defers_equip_and_blocks_firing_until_raised() -> void:
	_hand.inventory().backpack[2] = "pistol"
	_hotbar._equip_slot(_hand, 2)
	var overlay := _player.get_node("FirstPersonView") as FirstPersonView
	overlay.set_process(false)
	assert_eq(_hand.net_item_id, "", "Equip waits for the lowering phase")
	assert_true(FirstPersonView.firing_blocked(get_tree(), 1))
	overlay._advance_swap(FirstPersonView.SWAP_LOWER_SECONDS)
	assert_eq(_hand.net_item_id, "pistol")
	assert_eq(_hand.inventory().backpack[2], "")
	assert_true(FirstPersonView.firing_blocked(get_tree(), 1), "Still raising the new item")
	overlay._advance_swap(FirstPersonView.SWAP_RAISE_SECONDS)
	assert_false(FirstPersonView.firing_blocked(get_tree(), 1))
	assert_eq(FirstPersonView.swap_pose(_player), Transform3D.IDENTITY)


func test_rapid_fps_selections_replace_the_pending_request() -> void:
	_hand.inventory().backpack[1] = "pistol"
	_hand.inventory().backpack[4] = "smg"
	_hotbar._cycle(_hand, 1)
	_hotbar._cycle(_hand, 1)
	_finish_swap()
	assert_eq(_hand.net_item_id, "smg")
	assert_eq(_hand.inventory().backpack[1], "pistol", "Superseded selection stays stored")
	assert_eq(_hand.inventory().backpack[4], "")


func test_third_person_equips_without_waiting_for_fps_animation() -> void:
	(_player.get_node("Body") as Node3D).visible = true
	_hand.inventory().backpack[2] = "pistol"
	_hotbar._equip_slot(_hand, 2)
	assert_eq(_hand.net_item_id, "pistol")
	assert_false(FirstPersonView.firing_blocked(get_tree(), 1))


func _spawn_rig() -> GunRig:
	var rig := GunRigScene.instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	rig.set_process(false)
	return rig


func test_firing_starts_a_recoil_kick_that_moves_the_held_view() -> void:
	_hand.net_item_id = "pistol"
	_hand.inventory().collect("ammo:pistol:1")
	_hand._process(0.0)
	var view := _hand.held_view()
	assert_not_null(view)
	var base := view.transform
	_hand.request_primary_action()
	assert_true(_hotbar._recoil.has(_hand))
	_hotbar._update_recoil(_hand, 0.01)
	assert_false(view.transform.is_equal_approx(base))


func test_recoil_settles_back_to_the_rest_pose_once_it_finishes() -> void:
	_hand.net_item_id = "pistol"
	_hand.inventory().collect("ammo:pistol:1")
	_hand._process(0.0)
	var view := _hand.held_view()
	var base := view.transform
	_hand.request_primary_action()
	_hotbar._update_recoil(_hand, 10.0)
	assert_true(view.transform.is_equal_approx(base))
	assert_false(_hotbar._recoil.has(_hand))


func test_process_connects_the_fired_signal_of_every_hand_in_the_scene() -> void:
	assert_true(_hotbar._connected.has(_hand))
	assert_eq(_hand.fired.get_connections().size(), 1)


func test_process_does_not_reconnect_a_hand_it_already_knows_about() -> void:
	_hotbar._process(0.0)
	_hotbar._process(0.0)
	assert_eq(_hand.fired.get_connections().size(), 1)
