extends GutTest

const SCREEN := preload("res://features/inventory/inventory_screen.gd")
const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const PICKUP := preload("res://features/holdables/item_pickup.tscn")
const THROWN := preload("res://features/holdables/thrown_item.tscn")

var _hand: Hand
var _inventory: PlayerInventory
var _player: Player


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
	_inventory = _hand.inventory()


func after_each() -> void:
	await get_tree().process_frame


func test_new_inventory_starts_empty_and_clothing_has_to_be_collected() -> void:
	assert_eq(_inventory.shirt, "")
	assert_eq(_inventory.pants, "")
	assert_eq(_hand.net_item_id, "")
	assert_eq(_inventory.backpack.count(""), 8)
	assert_true(_inventory.collect("shirt:2"))
	assert_true(_inventory.collect("pants:3"))
	assert_eq(_inventory.shirt, "shirt:2")
	assert_eq(_inventory.pants, "pants:3")
	assert_eq(_inventory.backpack.count(""), 8)


func test_full_hand_collects_into_bag_and_equip_swaps_without_losing_items() -> void:
	assert_true(_inventory.collect("pistol"))
	assert_true(_inventory.collect("banana"))
	assert_eq(_hand.net_item_id, "pistol")
	assert_eq(_inventory.backpack[0], "banana")
	_inventory.request_equip(0)
	assert_eq(_hand.net_item_id, "banana")
	assert_eq(_inventory.backpack[0], "pistol")
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")
	assert_eq(_inventory.backpack[0], "pistol", "Eating consumes only the held item")


func test_holster_weapon_stows_the_held_weapon_and_leaves_the_hand_empty() -> void:
	_inventory.collect("pistol")
	_inventory.holster_weapon()
	assert_eq(_hand.net_item_id, "")
	assert_eq(_inventory.backpack[0], "pistol")


func test_holster_weapon_ignores_a_held_non_weapon() -> void:
	_inventory.collect("banana")
	_inventory.holster_weapon()
	assert_eq(_hand.net_item_id, "banana")


func test_holster_weapon_drops_the_weapon_when_the_backpack_is_full() -> void:
	var sink := DropSink.new()
	sink.add_to_group(&"holdables_root")
	add_child_autofree(sink)
	_inventory.collect("pistol")
	for index: int in 8:
		assert_true(_inventory.collect("banana"))
	_inventory.holster_weapon()
	assert_eq(_hand.net_item_id, "")
	assert_eq(sink.items, ["pistol"])


func test_clothing_swaps_preserve_colors_and_stow_removes_equipment() -> void:
	_inventory.collect("shirt:2")
	_inventory.collect("shirt:4")
	_inventory.request_equip(0)
	assert_eq(_inventory.shirt, "shirt:4")
	assert_eq(_inventory.backpack[0], "shirt:2")
	_inventory.request_stow(-2)
	assert_eq(_inventory.shirt, "")
	assert_eq(_inventory.backpack[1], "shirt:4")
	_inventory.request_equip(1)
	assert_eq(_inventory.shirt, "shirt:4")
	assert_eq(_inventory.backpack[1], "")


func test_full_backpack_rejects_pickup_and_stow_but_allows_equipment_swap() -> void:
	_inventory.collect("pistol")
	for index: int in 8:
		assert_true(_inventory.collect("banana"))
	assert_false(_inventory.can_collect("ball"))
	assert_false(_inventory.collect("ball"))
	_inventory.request_stow(-1)
	assert_eq(_hand.net_item_id, "pistol")
	_inventory.request_equip(3)
	assert_eq(_hand.net_item_id, "banana")
	assert_eq(_inventory.backpack[3], "pistol")
	assert_true(_inventory.collect("shirt:0"), "An empty equipment slot still accepts clothing")


func test_invalid_ids_indices_and_foreign_owners_cannot_mutate_inventory() -> void:
	for id: String in ["shirt:-1", "shirt:12", "shirt:foo", "shirt:02", "pants:2:3", "unknown"]:
		assert_false(_inventory.collect(id))
	_inventory.collect("shirt:2")
	_inventory.collect("pants:1")
	_inventory.collect("pistol")
	_inventory.collect("banana")
	for index: int in [-100, -1, 8, 100]:
		_inventory.request_equip(index)
	assert_eq(_inventory.shirt, "shirt:2")
	_hand.peer_id = 99
	_inventory.request_equip(0)
	_inventory.request_stow(-2)
	_inventory.request_drop(-2)
	assert_eq(_inventory.shirt, "shirt:2")
	assert_eq(_inventory.pants, "pants:1")
	assert_eq(_hand.net_item_id, "pistol")
	assert_eq(_inventory.backpack[0], "banana")


func test_drop_preserves_color_and_cannot_duplicate_on_repeated_requests() -> void:
	var sink := DropSink.new()
	sink.add_to_group(&"holdables_root")
	add_child_autofree(sink)
	_inventory.collect("shirt:8")
	_inventory.request_drop(-2)
	_inventory.request_drop(-2)
	assert_eq(sink.items, ["shirt:8"])
	assert_eq(_inventory.shirt, "")
	var thrown := THROWN.instantiate() as ThrownItem
	thrown.item_id = sink.items[0]
	thrown.net_landed = true
	add_child_autofree(thrown)
	thrown.set_physics_process(false)
	thrown.request_pickup()
	thrown.request_pickup()
	assert_eq(_inventory.shirt, "shirt:8")
	assert_eq(_inventory.backpack.count(""), 8, "Queued pickups cannot be collected twice")


func test_failed_drop_keeps_item() -> void:
	_inventory.collect("pants:3")
	_inventory.request_drop(-3)
	assert_eq(_inventory.pants, "pants:3")


func test_world_pickups_enforce_range_and_single_ownership_with_a_backpack() -> void:
	var pickup := PICKUP.instantiate() as ItemPickup
	pickup.item_id = "shirt:4"
	pickup.position = Vector3(20, 0, 0)
	add_child_autofree(pickup)
	pickup.request_pickup()
	assert_false(pickup.net_taken)
	pickup.position = _player.position
	pickup.request_pickup()
	pickup.request_pickup()
	assert_true(pickup.net_taken)
	assert_eq(_inventory.shirt, "shirt:4")
	assert_eq(_inventory.backpack.count(""), 8)


func test_avatar_uses_underwear_until_equipped_and_materials_are_per_player() -> void:
	var model := BlockPlayerModel.new()
	var other := BlockPlayerModel.new()
	add_child_autofree(model)
	add_child_autofree(other)
	assert_eq(model.sleeve_color(), PlayerSkin.TONES[0])
	assert_false(bool(model.human.material.get_shader_parameter("pants_equipped")))
	assert_false(bool(model.human.material.get_shader_parameter("shirt_equipped")))
	model.set_clothing("shirt:4", "pants:1")
	assert_eq(model.sleeve_color(), ClothingCatalog.COLORS[4])
	assert_eq(model.pants_color, ClothingCatalog.COLORS[1])
	assert_true(bool(model.human.material.get_shader_parameter("pants_equipped")))
	assert_true(bool(model.human.material.get_shader_parameter("shirt_equipped")))
	assert_eq(other.sleeve_color(), PlayerSkin.TONES[0])
	assert_ne(model.human.material, other.human.material)
	assert_false(bool(other.human.material.get_shader_parameter("shirt_equipped")))
	model.set_clothing("", "")
	assert_false(bool(model.human.material.get_shader_parameter("pants_equipped")))
	assert_eq(model.pants_color, PlayerSkin.TONES[0])


func test_inventory_screen_reads_wallet_without_using_a_slot_and_blocks_gameplay() -> void:
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {1: 4250}
	var screen: CanvasLayer = SCREEN.new()
	add_child_autofree(screen)
	_hand.skin_index = 6
	screen.esc_menu_open()
	assert_true(screen.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_eq(screen._wallet.text, "$42.50")
	assert_eq(screen._preview.model.skin_color, PlayerSkin.TONES[6])
	assert_eq(_inventory.backpack.count(""), 8)
	wallet.balances = {1: 5250}
	screen._process(0.0)
	assert_eq(screen._wallet.text, "$52.50", "Open inventory follows wallet updates")
	_inventory.collect("shirt:4")
	screen._process(0.0)
	assert_eq(screen._preview.model.shirt_id, "shirt:4")
	assert_false(screen._stow.disabled)
	screen._action("stow")
	assert_eq(_inventory.shirt, "")
	assert_eq(_inventory.backpack[0], "shirt:4")
	screen._select(0)
	screen._action("equip")
	assert_eq(_inventory.shirt, "shirt:4")
	assert_eq(_inventory.backpack[0], "")
	screen._close(false)
	assert_false(screen.is_in_group(&"modal_ui"))
	assert_false(screen._panel.visible)


func test_inventory_refreshes_preview_when_owner_instance_changes_with_same_items() -> void:
	_hand.skin_index = 2
	var screen: CanvasLayer = SCREEN.new()
	add_child_autofree(screen)
	screen.set_process(false)
	screen.esc_menu_open()
	screen._process(0.0)
	_hand.remove_from_group(&"hands")
	var replacement := HAND.instantiate() as Hand
	replacement.peer_id = 1
	replacement.skin_index = 7
	add_child_autofree(replacement)
	screen._process(0.0)
	assert_eq(screen._preview.model.skin_color, PlayerSkin.TONES[7])
	screen._close(false)


func test_inventory_closes_without_resuming_when_menu_or_network_context_changes() -> void:
	var screen: CanvasLayer = SCREEN.new()
	add_child_autofree(screen)
	screen.esc_menu_open()
	Controls.menu_requested.emit()
	assert_false(screen._panel.visible, "The main menu must not stack over an active inventory")
	assert_false(screen.is_in_group(&"modal_ui"))
	assert_false(Controls.playing)
	screen.esc_menu_open()
	Network.mode_changed.emit(Network.mode)
	assert_false(screen._panel.visible, "Old inventory cannot stay open across a connection change")
	assert_false(Controls.playing)
	screen._close(false)


func test_narrow_inventory_keeps_wallet_and_close_button_inside_viewport() -> void:
	var window := Window.new()
	window.size = Vector2i(320, 700)
	add_child_autofree(window)
	var wallet := PlayerMoney.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {1: 123456789}
	var screen: CanvasLayer = SCREEN.new()
	window.add_child(screen)
	screen.esc_menu_open()
	for frame: int in 4:
		await get_tree().process_frame
	for control: Control in [screen._wallet, screen._close_button]:
		var rect: Rect2 = (
			control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
		)
		assert_gte(rect.position.x, 0.0)
		assert_lte(rect.end.x, window.get_visible_rect().size.x)
	assert_eq(screen._wallet.text, "$1.23M", "Compact balances must keep a magnitude suffix")
	assert_eq(screen._wallet.tooltip_text, "Wallet: $1234567.89", "The full amount stays available")
	screen._close(false)


func test_compact_wallet_keeps_units_at_rounding_boundaries() -> void:
	assert_eq(SCREEN.compact_money(100000), "$1.00k")
	assert_eq(SCREEN.compact_money(99999999), "$1.00M")
	assert_eq(SCREEN.compact_money(123456789), "$1.23M")
	assert_eq(SCREEN.compact_money(99999999999), "$1.00B")
