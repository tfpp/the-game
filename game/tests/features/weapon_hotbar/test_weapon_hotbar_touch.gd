extends GutTest
## features/weapon_hotbar/weapon_hotbar_hud.gd as a touch hotbar: every slot is a
## button that equips through weapon_hotbar.gd, the picked slot highlights, compact
## layouts keep 52-unit slots in a sideways scroll row, and the pause menu hides it.

const FeatureScene := preload("res://features/weapon_hotbar/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const HandScene := preload("res://features/holdables/hand.tscn")

var _player: Player
var _hand: Hand
var _hotbar: Node
var _hud: CanvasLayer
var _device: Controls.Device


func before_each() -> void:
	_device = Controls.device
	_player = PlayerScene.instantiate() as Player
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_hand = HandScene.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hotbar = FeatureScene.instantiate()
	add_child_autofree(_hotbar)
	_hud = _hotbar.get_node("Hud") as CanvasLayer


func after_each() -> void:
	Controls.device = _device
	Controls.pause()
	await get_tree().process_frame


func test_tapping_a_slot_equips_it_and_highlights_it() -> void:
	Controls.device = Controls.Device.TOUCH
	Controls.start()
	_hand.inventory().backpack[2] = "pistol"
	var tap := _hud._cells[3].get_node("Tap") as Button
	tap.pressed.emit()
	var overlay := _player.get_node("FirstPersonView") as FirstPersonView
	overlay._advance_swap(FirstPersonView.SWAP_LOWER_SECONDS + FirstPersonView.SWAP_RAISE_SECONDS)
	assert_eq(_hand.net_item_id, "pistol", "The tap went through the hotbar's equip")
	_hud._process(0.0)
	assert_eq(_hud._cells[3].theme_type_variation, &"HudSlotActive")
	assert_eq(_hud._cells[1].theme_type_variation, &"HudSlot")


func test_taps_do_nothing_while_gameplay_is_paused() -> void:
	Controls.pause()
	_hand.inventory().backpack[2] = "pistol"
	(_hud._cells[3].get_node("Tap") as Button).pressed.emit()
	assert_eq(_hotbar.selected, -1)
	assert_eq(_hand.inventory().backpack[2], "pistol")


func test_touch_layout_keeps_big_slots_in_a_scroll_row_with_short_names() -> void:
	Controls.device = Controls.Device.TOUCH
	_hand.inventory().backpack[0] = "pistol"
	_hud._process(0.0)
	assert_true(_hud._compact)
	var scroll := _hud._panel.find_child("Scroll", true, false) as ScrollContainer
	assert_not_null(scroll)
	assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED)
	for slot: int in range(1, _hud.SLOT_COUNT):
		var cell: PanelContainer = _hud._cells[slot]
		assert_gte(cell.custom_minimum_size.x, HudLayout.TOUCH_SLOT)
		assert_gte(cell.custom_minimum_size.y, HudLayout.TOUCH_SLOT)
		assert_eq(_hud._cells[slot].visible, slot == 1, "Only occupied touch slots are shown")
	assert_eq(_hud._labels[1].text, "Pistol")
	assert_eq(_hud.short_name("Golden Revolver"), "Golden")


func test_pause_menu_hides_the_panel() -> void:
	_hand.inventory().backpack[0] = "pistol"
	var menu := Node.new()
	add_child_autofree(menu)
	menu.add_to_group(HudLayout.PAUSE_GROUP)
	_hud._process(0.0)
	assert_false(_hud._panel.visible)
	menu.remove_from_group(HudLayout.PAUSE_GROUP)
	_hud._process(0.0)
	assert_true(_hud._panel.visible)
