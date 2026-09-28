extends GutTest
## Coverage for the machine kiosk, the trash can, and gun_machine.gd's purchase flow
## (charging the wallet and equipping a rig). Runs single-process, so RPCs here
## resolve to peer 1 directly, the same trick test_slot_machine.gd uses.

const KioskScene := preload("res://features/gun_machine/kiosk.tscn")
const TrashCanScene := preload("res://features/gun_machine/trash_can.tscn")
const GunRigScene := preload("res://features/gun_machine/gun_rig.tscn")
const FeatureScene := preload("res://features/gun_machine/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _player: Player
var _rig: GunRig


class _MachineStub:
	extends Node3D
	var purchases: Array[int] = []
	var discards: Array[int] = []

	func price_cents() -> int:
		return 2500

	func purchase(peer: int) -> String:
		purchases.append(peer)
		return ""

	func discard(peer: int) -> void:
		discards.append(peer)


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


func test_kiosk_in_range_asks_the_machine_to_sell_a_gun() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	var kiosk := KioskScene.instantiate() as GunMachineKiosk
	add_child_autofree(kiosk)
	kiosk.global_position = _player.global_position
	await get_tree().physics_frame
	await kiosk.request_purchase()
	assert_eq(stub.purchases, [1])


func test_kiosk_out_of_range_does_nothing() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	var kiosk := KioskScene.instantiate() as GunMachineKiosk
	add_child_autofree(kiosk)
	kiosk.global_position = (
		_player.global_position + Vector3(0, 0, GunMachineKiosk.USE_RANGE + 5.0)
	)
	await get_tree().physics_frame
	await kiosk.request_purchase()
	assert_true(stub.purchases.is_empty())


func test_trash_can_discards_only_once_a_gun_is_held_and_in_range() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	var can := TrashCanScene.instantiate() as GunMachineTrashCan
	add_child_autofree(can)
	can.global_position = _player.global_position
	await get_tree().physics_frame
	can.request_discard()
	assert_true(stub.discards.is_empty(), "nothing to trash yet")
	_rig.net_stats = {"ammo_type": GunGenerator.AmmoType.RIFLE}
	can.request_discard()
	assert_eq(stub.discards, [1])


func test_trash_can_out_of_range_does_nothing() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	_rig.net_stats = {"ammo_type": GunGenerator.AmmoType.RIFLE}
	var can := TrashCanScene.instantiate() as GunMachineTrashCan
	add_child_autofree(can)
	can.global_position = (
		_player.global_position + Vector3(0, 0, GunMachineTrashCan.USE_RANGE + 5.0)
	)
	await get_tree().physics_frame
	can.request_discard()
	assert_true(stub.discards.is_empty())


func test_purchase_charges_the_wallet_and_equips_the_rig() -> void:
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {1: GunMachine.PRICE_CENTS + 500}
	var feature := FeatureScene.instantiate() as GunMachine
	add_child_autofree(feature)
	await get_tree().physics_frame
	var error: String = await feature.purchase(1)
	assert_eq(error, "")
	assert_eq(int(wallet.balances[1]), 500)
	assert_false(_rig.net_stats.is_empty())
	assert_true(_rig.net_ammo_in_mag > 0)


func test_purchase_without_enough_money_does_not_equip_anything() -> void:
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {1: 0}
	var feature := FeatureScene.instantiate() as GunMachine
	add_child_autofree(feature)
	await get_tree().physics_frame
	var error: String = await feature.purchase(1)
	assert_ne(error, "")
	assert_true(_rig.net_stats.is_empty())
	assert_eq(int(wallet.balances[1]), 0)
