extends GutTest

const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const MACHINE := preload("res://features/gun_machine/feature.tscn")

var _hand: Hand
var _player: Player
var _machine: GunMachine
var _wallet: PlayerMoney
var _shots: Array[String] = []


func before_each() -> void:
	_shots.clear()
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hand.set_process(false)
	_hand.fired.connect(func(id: String) -> void: _shots.append(id))
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 100000}
	_machine = MACHINE.instantiate() as GunMachine
	add_child_autofree(_machine)


func test_every_stock_gun_is_empty_until_matching_ammo_is_purchased() -> void:
	for weapon: String in ItemCatalog.AMMO_PACKS:
		_hand.net_item_id = weapon
		_hand._fire_cooldown = 0.0
		_shots.clear()
		_hand.request_primary_action()
		assert_true(_shots.is_empty())
		assert_eq(_hand._fire_cooldown, 0.0)
		var pack: Dictionary = ItemCatalog.AMMO_PACKS[weapon]
		var id := ItemCatalog.ammo_id(weapon, pack["rounds"])
		var balance: int = _wallet.balances[1]
		assert_eq(await _machine.purchase(1, id), "")
		assert_eq(_wallet.balances[1], balance - int(pack["price"]))
		_hand.request_primary_action()
		assert_eq(_shots, [weapon] as Array[String])
		assert_eq(_hand.inventory().ammo_for(weapon), int(pack["rounds"]) - 1)
		_hand.request_primary_action()
		assert_eq(_shots.size(), 1, "cooldown consumes nothing")
		assert_eq(_hand.inventory().ammo_for(weapon), int(pack["rounds"]) - 1)
		_hand.inventory().backpack = PackedStringArray(["", "", "", "", "", "", "", ""])


func test_wrong_ammo_loading_foreign_and_missing_player_requests_do_not_spend() -> void:
	_hand.net_item_id = "pistol"
	assert_true(_hand.inventory().collect("ammo:awp:5"))
	_hand.request_primary_action()
	assert_eq(_hand.inventory().ammo_for("awp"), 5)
	assert_true(_hand.inventory().collect("ammo:pistol:2"))
	_hand.inventory().loading = true
	_hand.request_primary_action()
	_hand.inventory().loading = false
	_hand.peer_id = 2
	_hand.request_primary_action()
	_hand.peer_id = 1
	_player.name = "absent"
	_hand.request_primary_action()
	assert_eq(_hand.inventory().ammo_for("pistol"), 2)
	assert_true(_shots.is_empty())


func test_last_shell_is_one_shot_not_one_round_per_pellet() -> void:
	_hand.net_item_id = "shotgun"
	assert_true(_hand.inventory().collect("ammo:shotgun:1"))
	_hand.request_primary_action()
	assert_eq(_shots, ["shotgun"] as Array[String])
	assert_eq(_hand.inventory().ammo_for("shotgun"), 0)
	assert_eq(_hand.inventory().backpack[0], "")
	_hand._fire_cooldown = 0.0
	_hand.request_primary_action()
	assert_eq(_shots.size(), 1)
	assert_eq(_hand.net_item_id, "shotgun", "empty gun is retained")


func test_ammo_collects_to_backpack_and_partial_ids_survive_store_and_restore() -> void:
	assert_true(_hand.inventory().collect("ammo:pistol:20"))
	assert_eq(_hand.net_item_id, "")
	_hand.net_item_id = "pistol"
	_hand.request_primary_action()
	assert_eq(_hand.inventory().backpack[0], "ammo:pistol:19")
	_hand.inventory().request_equip(0)
	assert_eq(_hand.net_item_id, "ammo:pistol:19")
	_hand.inventory().request_stow(-1)
	var saved := _hand.inventory().snapshot()
	var restored := HAND.instantiate() as Hand
	restored.peer_id = 3
	add_child_autofree(restored)
	restored.inventory().restore(saved)
	assert_eq(restored.inventory().snapshot(), saved)
	assert_eq(restored.inventory().ammo_for("pistol"), 19)
	assert_string_contains(ItemCatalog.find("ammo:pistol:19").display_name, "19 rounds")
	assert_eq(ItemCatalog.find("ammo:pistol:19").sale_value_cents, 0)


func test_bad_pack_ids_cannot_be_bought_or_restored_and_no_free_ammo_with_guns() -> void:
	for id: String in ["ammo:pistol:0", "ammo:pistol:21", "ammo:pistol:01", "ammo:ray:5"]:
		assert_null(ItemCatalog.find(id))
		assert_ne(await _machine.purchase(1, id), "")
	assert_eq(_wallet.balances[1], 100000)
	assert_eq(await _machine.purchase(1, "pistol"), "")
	assert_eq(_wallet.balances[1], 97000)
	assert_eq(_hand.inventory().ammo_for("pistol"), 0)
	_hand.inventory().loading = true
	assert_ne(await _machine.purchase(1, "ammo:pistol:20"), "")
	_hand.inventory().loading = false
	_wallet.balances[1] = 999
	assert_ne(await _machine.purchase(1, "ammo:pistol:20"), "")
	assert_eq(_hand.inventory().ammo_for("pistol"), 0)


func test_partial_pack_pickup_keeps_rounds_and_multiple_packs_feed_one_gun() -> void:
	_hand.net_item_id = "pistol"
	var pickup := preload("res://features/holdables/item_pickup.tscn").instantiate() as ItemPickup
	pickup.item_id = "ammo:pistol:1"
	add_child_autofree(pickup)
	pickup.global_position = _player.global_position
	pickup.request_pickup()
	assert_true(pickup.net_taken)
	assert_eq(_hand.inventory().ammo_for("pistol"), 1)
	assert_true(_hand.inventory().collect("ammo:pistol:2"))
	for shot: int in 3:
		_hand._fire_cooldown = 0.0
		_hand.request_primary_action()
		assert_eq(_hand.inventory().ammo_for("pistol"), 2 - shot)
	assert_eq(_shots.size(), 3)
	assert_eq(_hand.inventory().take_first_valuable(), "", "ammo cannot be pawned")


func test_ammo_needs_a_free_backpack_slot_even_with_empty_hand() -> void:
	_hand.inventory().backpack.fill("banana")
	assert_false(_hand.inventory().can_collect("ammo:pistol:20"))
	assert_ne(await _machine.purchase(1, "ammo:pistol:20"), "")
	assert_eq(_wallet.balances[1], 100000)
	assert_eq(_hand.net_item_id, "")
