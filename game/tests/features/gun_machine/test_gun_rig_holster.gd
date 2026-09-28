extends GutTest
## Coverage for gun_rig.gd's mutual exclusion with a held holdable weapon
## (features/holdables): equipping or collecting one holsters the other, so only
## one weapon is ever in hand. Runs single-process, so
## `multiplayer.get_remote_sender_id()` is 0 and every RPC here resolves to peer 1 —
## the same trick test_holdables.gd uses to call server RPCs directly.

const GunRigScene := preload("res://features/gun_machine/gun_rig.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const HandScene := preload("res://features/holdables/hand.tscn")

var _player: Player
var _rig: GunRig


class _MachineStub:
	extends Node
	var spawned: Array[Dictionary] = []

	func spawn_projectile(data: Dictionary) -> void:
		spawned.append(data)


func _sample_stats(seed_value: int = 7) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return GunGenerator.generate(rng)


func before_each() -> void:
	_player = PlayerScene.instantiate() as Player
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_rig = GunRigScene.instantiate() as GunRig
	_rig.peer_id = 1
	add_child_autofree(_rig)
	_rig.set_process(false)
	await get_tree().physics_frame


func test_equip_holsters_a_held_holdable_weapon_into_the_backpack() -> void:
	var hand := HandScene.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.inventory().collect("pistol")
	assert_eq(hand.net_item_id, "pistol")
	_rig.equip(_sample_stats())
	assert_eq(hand.net_item_id, "", "The rig takes over the hand")
	assert_eq(hand.inventory().backpack[0], "pistol", "The pistol is stowed, not lost")
	assert_true(_rig.is_active())


func test_equip_does_not_disturb_a_held_non_weapon() -> void:
	var hand := HandScene.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.inventory().collect("banana")
	_rig.equip(_sample_stats())
	assert_eq(hand.net_item_id, "banana", "Only weapons are mutually exclusive with the rig")


func test_holster_hides_the_gun_without_losing_its_stats() -> void:
	var stats := _sample_stats()
	_rig.equip(stats)
	_rig.holster()
	assert_false(_rig.is_active())
	assert_eq(_rig.net_stats["ammo_type"], stats["ammo_type"], "Stats survive a holster")


func test_request_equip_rig_brings_a_holstered_gun_back_and_holsters_the_hand() -> void:
	var hand := HandScene.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	_rig.equip(_sample_stats())
	_rig.holster()
	hand.inventory().collect("pistol")
	assert_true(hand.net_item_id == "pistol")
	_rig.request_equip_rig()
	assert_true(_rig.is_active())
	assert_eq(hand.net_item_id, "", "Re-equipping the rig holsters the holdable weapon")
	assert_eq(hand.inventory().backpack[0], "pistol")


func test_request_equip_rig_does_nothing_with_no_gun_rolled() -> void:
	_rig.request_equip_rig()
	assert_false(_rig.is_active())


func test_collecting_a_weapon_holsters_an_active_rig() -> void:
	var hand := HandScene.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	_rig.equip(_sample_stats())
	assert_true(_rig.is_active())
	hand.inventory().collect("pistol")
	assert_false(_rig.is_active(), "Picking up a weapon holsters the rig's gun")


func test_collecting_a_non_weapon_leaves_the_rig_active() -> void:
	var hand := HandScene.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	_rig.equip(_sample_stats())
	hand.inventory().collect("banana")
	assert_true(_rig.is_active())


func test_firing_and_reloading_are_blocked_while_holstered() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	_rig.equip(_sample_stats())
	_rig.holster()
	_rig.request_fire()
	assert_true(stub.spawned.is_empty(), "A holstered gun cannot fire")
	_rig.net_ammo_in_mag = 0
	_rig.request_reload()
	assert_eq(_rig.net_ammo_in_mag, 0, "A holstered gun cannot reload either")
