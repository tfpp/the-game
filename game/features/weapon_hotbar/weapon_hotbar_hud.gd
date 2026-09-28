extends CanvasLayer
## A bottom-center strip showing every weapon slot and which one is currently held:
## the hand itself, the 8 backpack slots (features/inventory, keys 1-8) and the gun
## machine's rig (features/gun_machine, key 9) — so "which weapon is in which slot" is
## visible, not just something the number keys and scroll wheel (weapon_hotbar.gd)
## have to be memorized. Built in code, the way
## features/gun_machine/gun_stats_panel.gd builds its panel, since ten near-identical
## slot columns would make feature.tscn noisy to review.

## Column order: the hand, then one per backpack slot, then the gun machine's rig.
const HAND_SLOT := 0
const RIG_SLOT := PlayerInventory.CAPACITY + 1
const SLOT_COUNT := PlayerInventory.CAPACITY + 2

const ACTIVE_COLOR := Color(1.0, 0.85, 0.35, 1.0)
const IDLE_COLOR := Color(1.0, 1.0, 1.0, 0.6)

## Slot index (see the consts above) -> its name Label.
var _labels: Array[Label] = []

@onready var _row: HBoxContainer = $Row


func _ready() -> void:
	for slot: int in SLOT_COUNT:
		_row.add_child(_build_slot(slot))
	get_viewport().size_changed.connect(_resize_row)
	_resize_row()


func _resize_row() -> void:
	var width := minf(540.0, get_viewport().get_visible_rect().size.x - 24.0)
	_row.offset_left = -width * 0.5
	_row.offset_right = width * 0.5
	for column: Control in _row.get_children():
		column.custom_minimum_size.x = (width - 4.0 * (SLOT_COUNT - 1)) / SLOT_COUNT


func _process(_delta: float) -> void:
	var hand := Hand.for_peer(get_tree(), multiplayer.get_unique_id())
	var hand_def := ItemCatalog.find(hand.net_item_id if hand != null else "")
	var holding_weapon := hand_def != null and hand_def.category == ItemDefinition.Category.WEAPON
	_set_slot(HAND_SLOT, hand_def.display_name if hand_def != null else "", holding_weapon)
	var backpack := hand.inventory().backpack if hand != null else PackedStringArray()
	for slot: int in PlayerInventory.CAPACITY:
		var id := backpack[slot] if slot < backpack.size() else ""
		_set_slot(slot + 1, _display_name(id), false)
	var rig := GunRig.for_peer(get_tree(), multiplayer.get_unique_id())
	var rig_name := (
		str(rig.net_stats["display_name"]) if rig != null and not rig.net_stats.is_empty() else ""
	)
	_set_slot(RIG_SLOT, rig_name, rig != null and rig.is_active())


func _set_slot(slot: int, text: String, active: bool) -> void:
	var label := _labels[slot]
	var display := text if not text.is_empty() else "—"
	if label.text != display:
		label.text = display
	var color := ACTIVE_COLOR if active else IDLE_COLOR
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func _display_name(id: String) -> String:
	if id.is_empty():
		return ""
	var def := ItemCatalog.find(id)
	return def.display_name if def != null else id


func _key_text(slot: int) -> String:
	if slot == HAND_SLOT:
		return "Hand"
	if slot == RIG_SLOT:
		return "9"
	return str(slot)


func _build_slot(slot: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Hand" if slot == HAND_SLOT else ("Rig" if slot == RIG_SLOT else "Slot%d" % slot)
	box.custom_minimum_size = Vector2(50, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key := Label.new()
	key.text = _key_text(slot)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_theme_font_size_override("font_size", 11)
	key.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	key.add_theme_color_override("font_outline_color", Color.BLACK)
	key.add_theme_constant_override("outline_size", 4)
	box.add_child(key)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = "—"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 4)
	box.add_child(name_label)
	_labels.append(name_label)
	return box
