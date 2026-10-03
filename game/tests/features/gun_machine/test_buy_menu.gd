extends GutTest

const FEATURE := preload("res://features/gun_machine/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const RIG := preload("res://features/gun_machine/gun_rig.tscn")
const CHAT := preload("res://features/chat_box/chat_box.gd")

var _machine: GunMachine
var _menu: CanvasLayer
var _player: Player
var _hand: Hand
var _rig: GunRig
var _wallet: PlayerMoney


class DelayedWallet:
	extends PlayerMoney
	signal finish
	var calls := 0

	func charge(peer: int, id: String, amount: int) -> Dictionary:
		calls += 1
		await finish
		return await super.charge(peer, id, amount)


class DropSink:
	extends Node
	var items: Array[String] = []

	func spawn_thrown_item(id: String, _from: Vector3, _to: Vector3) -> void:
		items.append(id)


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_rig = RIG.instantiate() as GunRig
	_rig.peer_id = 1
	add_child_autofree(_rig)
	_rig.set_process(false)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 20000}
	_machine = FEATURE.instantiate() as GunMachine
	add_child_autofree(_machine)
	_menu = _machine.get_node("BuyMenu")


func after_each() -> void:
	_menu.close_menu(false)
	Controls.pause()
	await get_tree().process_frame


func test_catalog_covers_every_player_weapon_and_all_valid_generated_variants() -> void:
	var fixed: Array[String] = []
	for definition: ItemDefinition in ItemCatalog.DEFINITIONS:
		if definition.category == ItemDefinition.Category.WEAPON:
			fixed.append(definition.id)
	assert_eq(fixed.size(), GunBuyCatalog.entries(0).size())
	for id: String in fixed:
		assert_false(GunBuyCatalog.find(id).is_empty())
	var rng := RandomNumberGenerator.new()
	rng.seed = 393
	var seen: Array[String] = []
	for category: int in GunBuyCatalog.CATEGORIES.size():
		var entries := GunBuyCatalog.entries(category)
		assert_between(entries.size(), 1, 8)
		for entry: Dictionary in entries:
			assert_false(seen.has(entry["id"]))
			seen.append(entry["id"])
			if not entry.has("ammo"):
				continue
			for roll: int in 20:
				var stats := GunBuyCatalog.stats(entry, rng)
				assert_eq(stats["ammo_type"], entry["ammo"])
				assert_eq(stats["barrel_count"], entry["barrels"])
				assert_eq(stats["is_automatic"], entry["automatic"] == 1)
				assert_gte(stats["magazine_size"], stats["barrel_count"])
	assert_true(GunBuyCatalog.find("generated:3:4:1").is_empty(), "rockets max out at 2")
	assert_true(GunBuyCatalog.find("cheat").is_empty())
	var shop := preload("res://features/pawn_shop/feature.tscn").instantiate()
	for rack: WallGun in shop.get_node("GunWall").get_children():
		assert_eq(GunBuyCatalog.find(rack.item_id)["price"], rack.price_cents)
	shop.free()


func test_requested_classic_prices_are_exact_and_ammo_prices_are_unchanged() -> void:
	var expected := {"pistol": 150000, "smg": 555000, "shotgun": 555000, "awp": 1500000}
	for id: String in expected:
		assert_eq(GunBuyCatalog.find(id)["price"], expected[id])
		_wallet.balances[1] = expected[id] - 1
		assert_ne(await _machine.purchase(1, id), "")
		assert_eq(_wallet.balances[1], expected[id] - 1)
		assert_eq(_hand.net_item_id, "")
	assert_eq(GunBuyCatalog.find("ammo:pistol:20")["price"], 1000)
	assert_eq(GunBuyCatalog.find("ammo:smg:40")["price"], 2000)
	assert_eq(GunBuyCatalog.find("ammo:shotgun:8")["price"], 2000)
	assert_eq(GunBuyCatalog.find("ammo:awp:5")["price"], 2500)


func test_chat_command_opens_modal_without_public_or_discord_message() -> void:
	var chat := CHAT.new()
	add_child_autofree(chat)
	watch_signals(chat)
	chat._on_text_submitted(" !GUNS ")
	assert_true(_menu._panel.visible)
	assert_true(_menu.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_signal_not_emitted(chat, "message_accepted")
	assert_eq(chat._log.get_child_count(), 0)
	chat.request_chat_message("!guns")
	assert_signal_not_emitted(chat, "message_accepted")
	assert_eq(chat._log.get_child_count(), 0)
	_menu.close_menu()
	assert_false(_menu.is_in_group(&"modal_ui"))
	assert_false(_menu._panel.visible)


func test_numbered_navigation_and_reset_do_not_change_weapon_hotbar() -> void:
	_menu.open_menu()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_7
	key.pressed = true
	_menu._input(key)
	assert_eq(_menu._category, 6)
	assert_eq(_menu.layer, 9, "buy menu stays above HUD layers")
	assert_eq(_menu._buttons.size(), 8)
	assert_true(_rig.net_stats.is_empty())
	_menu._reset(Network.Mode.OFFLINE)
	assert_false(_menu._panel.visible)
	assert_false(_menu.is_in_group(&"modal_ui"))


func test_server_rejects_unknown_extra_fields_and_nonexistent_players() -> void:
	assert_false(_menu._may_buy(1, {"id": "cheat"}))
	assert_false(_menu._may_buy(1, {"id": "ray", "peer": 99}))
	assert_false(_menu._may_buy(99, {"id": "ray"}))
	assert_false(_menu._may_buy(1, {"id": 5}))
	assert_true(_menu._may_buy(1, {"id": "ray"}))
	assert_ne(await _machine.purchase(1, "cheat"), "")
	assert_eq(_wallet.balances[1], 20000)


func test_paid_generated_selection_holsters_classic_and_replaces_rig() -> void:
	assert_true(_hand.inventory().collect("pistol"))
	_menu.entity.request_action(&"buy", {"id": "generated:5:2:1"})
	assert_eq(_wallet.balances[1], 18000)
	assert_eq(_rig.net_stats["ammo_type"], GunGenerator.AmmoType.PLASMA)
	assert_eq(_rig.net_stats["barrel_count"], 2)
	assert_true(_rig.net_stats["is_automatic"])
	assert_eq(_hand.net_item_id, "")
	assert_eq(_hand.inventory().backpack[0], "pistol")
	assert_eq(await _machine.purchase(1, "ray"), "")
	assert_true(GunGenerator.is_ray_gun(_rig.net_stats))


func test_classic_purchase_uses_inventory_and_higher_prices() -> void:
	_wallet.balances[1] = 2055000
	assert_eq(await _machine.purchase(1, "smg"), "")
	assert_eq(_wallet.balances[1], 1500000)
	assert_eq(_hand.net_item_id, "smg")
	assert_eq(await _machine.purchase(1, "awp"), "")
	assert_eq(_hand.inventory().backpack[0], "awp")
	assert_eq(_wallet.balances[1], 0)


func test_insufficient_funds_full_inventory_and_loading_do_not_charge() -> void:
	_wallet.balances[1] = 0
	assert_ne(await _machine.purchase(1, "ray"), "")
	assert_true(_rig.net_stats.is_empty())
	_wallet.balances[1] = 20000
	_hand.inventory().loading = true
	assert_ne(await _machine.purchase(1, "ray"), "")
	_hand.inventory().loading = false
	_hand.consumption.state = {"item": "beer", "left": 3.0}
	assert_ne(await _machine.purchase(1, "ray"), "")
	_hand.consumption.state = {}
	for index: int in 9:
		assert_true(_hand.inventory().collect("banana"))
	assert_ne(await _machine.purchase(1, "pistol"), "")
	assert_eq(_wallet.balances[1], 20000)


func test_pending_kiosk_and_menu_share_one_lock_and_paid_full_bag_drops_gun() -> void:
	_wallet.remove_from_group(&"player_money")
	var delayed := DelayedWallet.new()
	add_child_autofree(delayed)
	delayed.set_process(false)
	delayed.balances = {1: 150500}
	var sink := DropSink.new()
	sink.add_to_group(&"holdables_root")
	add_child_autofree(sink)
	_menu._select("pistol")
	assert_true(_machine._buying.has(1))
	assert_ne(await _machine.purchase(1), "")
	assert_eq(delayed.calls, 1)
	for index: int in 9:
		assert_true(_hand.inventory().collect("banana"))
	delayed.finish.emit()
	await get_tree().process_frame
	assert_eq(delayed.balances[1], 500)
	assert_eq(sink.items, ["pistol"])
	assert_false(_machine._buying.has(1))
	assert_false(_menu._pending)


func test_paid_ammo_drops_instead_of_disappearing_if_backpack_fills_during_payment() -> void:
	_wallet.remove_from_group(&"player_money")
	var delayed := DelayedWallet.new()
	add_child_autofree(delayed)
	delayed.set_process(false)
	delayed.balances = {1: 20000}
	var sink := DropSink.new()
	sink.add_to_group(&"holdables_root")
	add_child_autofree(sink)
	_menu._select("ammo:shotgun:8")
	assert_true(_machine._buying.has(1))
	assert_ne(await _machine.purchase(1, "ammo:shotgun:8"), "")
	for index: int in 8:
		assert_true(_hand.inventory().collect_into_slot("banana", index))
	delayed.finish.emit()
	await get_tree().process_frame
	assert_eq(delayed.balances[1], 18000)
	assert_eq(sink.items, ["ammo:shotgun:8"])
	assert_eq(_hand.net_item_id, "", "empty hand cannot absorb paid ammo")
	assert_false(_machine._buying.has(1))


func test_session_switch_invalidates_pending_delivery() -> void:
	_wallet.remove_from_group(&"player_money")
	var delayed := DelayedWallet.new()
	add_child_autofree(delayed)
	delayed.set_process(false)
	delayed.balances = {1: 20000}
	_menu._select("ray")
	assert_true(_machine._buying.has(1))
	_machine._on_mode_changed(Network.Mode.OFFLINE)
	_menu._reset(Network.Mode.OFFLINE)
	delayed.finish.emit()
	await get_tree().process_frame
	assert_true(_rig.net_stats.is_empty())
	assert_true((_machine.get_node("Rigs/1") as GunRig).net_stats.is_empty())
	assert_false(_menu._pending)
	assert_false(_menu._panel.visible)
