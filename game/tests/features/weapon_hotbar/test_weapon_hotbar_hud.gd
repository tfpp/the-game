extends GutTest
## Coverage for features/weapon_hotbar/weapon_hotbar_hud.gd: the on-screen strip
## showing which weapon slot (hand, backpack 1-8, or the gun machine's rig) is
## currently held.

const FeatureScene := preload("res://features/weapon_hotbar/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const HandScene := preload("res://features/holdables/hand.tscn")
const GunRigScene := preload("res://features/gun_machine/gun_rig.tscn")

var _player: Player
var _hand: Hand
var _hud: CanvasLayer


func before_each() -> void:
	_player = PlayerScene.instantiate() as Player
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_hand = HandScene.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	var feature := FeatureScene.instantiate()
	add_child_autofree(feature)
	_hud = feature.get_node("Hud") as CanvasLayer


func after_each() -> void:
	await get_tree().process_frame


func test_backpack_slots_show_their_contents_by_number() -> void:
	_hand.inventory().backpack[2] = "pistol"
	_hud._process(0.0)
	assert_eq(_hud._labels[3].text, "Pistol", "Backpack slot 2 (0-indexed) is column 3")
	assert_eq(_hud._labels[1].text, "")
	assert_false(_hud._cells[1].visible)
	assert_true(_hud._cells[3].visible)


func test_holding_a_weapon_highlights_the_hand_slot() -> void:
	_hand.net_item_id = "pistol"
	_hud._process(0.0)
	var label: Label = _hud._labels[_hud.HAND_SLOT]
	assert_eq(label.text, "Pistol")
	assert_eq(label.get_theme_color("font_color"), _hud.ACTIVE_COLOR)


func test_holding_a_non_weapon_does_not_highlight_the_hand_slot() -> void:
	_hand.net_item_id = "banana"
	_hud._process(0.0)
	var label: Label = _hud._labels[_hud.HAND_SLOT]
	assert_eq(label.text, "Banana")
	assert_eq(label.get_theme_color("font_color"), _hud.IDLE_COLOR)


func test_the_gun_machines_rig_slot_highlights_only_while_active() -> void:
	var rig := GunRigScene.instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	rig.set_process(false)
	rig.equip(GunGenerator.generate(RandomNumberGenerator.new()))
	_hud._process(0.0)
	var label: Label = _hud._labels[_hud.RIG_SLOT]
	assert_eq(label.get_theme_color("font_color"), _hud.ACTIVE_COLOR)
	rig.holster()
	_hud._process(0.0)
	assert_eq(label.get_theme_color("font_color"), _hud.IDLE_COLOR)


func test_empty_slots_hide_labels_and_collapse_strip() -> void:
	_hand.net_item_id = ""
	_hand.inventory().backpack.fill("")
	_hud._process(0.0)
	assert_eq(_hud._labels[_hud.HAND_SLOT].text, "")
	assert_eq(_hud._labels[_hud.RIG_SLOT].text, "")
	assert_false(_hud._panel.visible)
	_hand.inventory().backpack[7] = "pistol"
	_hud._process(0.0)
	assert_true(_hud._panel.visible)
	assert_true(_hud._cells[8].visible)
	assert_false(_hud._cells[1].visible)
	assert_eq((_hud._labels[8].get_parent().get_child(0) as Label).text, "8")
