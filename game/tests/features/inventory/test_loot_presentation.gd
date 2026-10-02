extends GutTest

const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const SCREEN := preload("res://features/inventory/inventory_screen.gd")
const CONTAINER := preload("res://features/loot/loot_container.tscn")
const PICKUP := preload("res://features/holdables/item_pickup.tscn")
const INTERACTION := preload("res://features/interaction/interaction.gd")

var _hand: Hand
var _player: Player
var _saved_device: int
var _saved_playing: bool


func before_each() -> void:
	_saved_device = Controls.device
	_saved_playing = Controls.playing
	Controls.device = Controls.Device.GAMEPAD
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)


func after_each() -> void:
	Controls.pause()
	Controls.device = _saved_device
	Controls.playing = _saved_playing
	await get_tree().process_frame


func test_icon_color_tracks_item_changes_without_tinting_the_model() -> void:
	var icon := InventoryIcon.new()
	icon.size = Vector2(36, 36)
	add_child_autofree(icon)
	icon.set_item("jewelry")
	assert_eq(icon.rarity_color(), Color("e5bf72"))
	assert_eq(icon.modulate, Color.WHITE)
	icon.set_item("scrap")
	assert_eq(icon.rarity_color(), Color("c5c7c9"))
	icon.set_item("banana")
	assert_eq(icon.rarity_color(), Color.WHITE)
	icon.set_item("")
	assert_eq(icon.rarity_color(), Color.WHITE)


func test_stash_claim_and_inventory_selection_show_the_same_tier_and_price() -> void:
	var screen: CanvasLayer = SCREEN.new()
	add_child_autofree(screen)
	var stash := CONTAINER.instantiate() as LootContainer
	add_child_autofree(stash)
	stash.net_searched = true
	stash.net_contents = PackedStringArray(["watch", "banana"])
	screen.open_stash(stash)
	var buttons: Array = screen.get("_stash_buttons")
	assert_string_contains((buttons[0] as Button).text, "Epic · $10.00")
	assert_string_contains((buttons[0] as Button).text, "Watch")
	assert_eq((buttons[0].get_child(0) as InventoryIcon).rarity_color(), Color("c7a0e8"))
	assert_false((buttons[1] as Button).text.contains("$"))
	screen.call("_take_stash_item", 0)
	screen.call("_process", 0.0)
	screen.call("_select", 0)
	assert_eq(_hand.inventory().backpack[0], "watch")
	assert_eq(stash.net_contents, PackedStringArray(["banana"]))
	assert_string_contains((screen.get("_description") as Label).text, "Epic · $10.00")
	assert_string_contains((screen.get("_description") as Label).text, "pawn counter")
	var bag: Array = screen.get("_slots")
	assert_string_contains((bag[0] as Button).tooltip_text, "Epic · $10.00")
	screen.call("_close", false)


func test_restored_inventory_ids_keep_tiers_and_legacy_cash_without_new_state() -> void:
	_hand.inventory().restore({"hand": "watch", "backpack": ["jewelry", "cash_bundle"]})
	var screen: CanvasLayer = SCREEN.new()
	add_child_autofree(screen)
	screen.esc_menu_open()
	screen.call("_select", -1)
	assert_string_contains((screen.get("_description") as Label).text, "Epic · $10.00")
	screen.call("_select", 0)
	assert_string_contains((screen.get("_description") as Label).text, "Legendary · $15.00")
	screen.call("_select", 1)
	assert_string_contains((screen.get("_description") as Label).text, "Cash · $5.00")
	assert_eq(_hand.inventory().snapshot()["backpack"][1], "cash_bundle")
	screen.call("_close", false)


func test_prompt_color_returns_to_white_for_other_interactables_and_no_target() -> void:
	var interaction: CanvasLayer = INTERACTION.new()
	add_child_autofree(interaction)
	var pickup := PICKUP.instantiate() as ItemPickup
	pickup.item_id = "electronics"
	add_child_autofree(pickup)
	Controls.start()
	interaction.call("_physics_process", 0.0)
	assert_eq(interaction.call("target_color"), Color("8ebcf0"))
	var prompt := interaction.get("_prompt") as Label
	assert_eq(prompt.get_theme_color("font_color"), Color("8ebcf0"))
	assert_string_contains(prompt.text, "Rare · $7.00")
	pickup.net_taken = true
	var stash := CONTAINER.instantiate() as LootContainer
	add_child_autofree(stash)
	interaction.call("_physics_process", 0.0)
	assert_eq(interaction.call("target_color"), Color.WHITE)
	assert_string_contains(str(interaction.call("target_text")), "Search container")
	_player.net_position = Vector3(100, 0, 0)
	interaction.call("_physics_process", 0.0)
	assert_eq(interaction.call("target_text"), "")
	assert_eq(interaction.call("target_color"), Color.WHITE)
	assert_false(prompt.visible)
