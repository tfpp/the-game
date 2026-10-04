extends CanvasLayer
## The weapon panel: what's in hand and its ammo on top, then every slot below — the 8
## backpack slots (features/inventory, keys 1-8) and the gun machine's rig
## (features/gun_machine, key 9) — so "which weapon is in which slot" is visible, not
## just something the number keys and scroll wheel (weapon_hotbar.gd) have to be
## memorized. Every slot is a button: tapping or clicking it equips that slot, and the
## picked slot stays highlighted while something is held. Placed by ui/hud_layout.gd
## (bottom-center, or top on touch) and hidden under the pause menu. On narrow and touch
## layouts the slots keep a 52-unit (44pt+) size with short names and the row scrolls
## sideways (swipe or drag) instead of shrinking. Built in code, since nine near-identical
## slot cells would make feature.tscn noisy to review.

const GunStatsPanel := preload("res://features/gun_machine/gun_stats_panel.gd")
const HUD_THEME := preload("res://ui/theme/hud_theme.tres")

## Label order: the hand (the panel's header), then one per backpack slot, then the rig.
const HAND_SLOT := 0
const RIG_SLOT := PlayerInventory.CAPACITY + 1
const SLOT_COUNT := PlayerInventory.CAPACITY + 2
## Short slot names keep this many characters on compact layouts.
const SHORT_NAME_LENGTH := 7

const ACTIVE_COLOR := Color(0.93, 0.8, 0.52, 1.0)
const IDLE_COLOR := Color(0.94, 0.89, 0.77, 0.6)

## Slot index (see the consts above) -> its name Label.
var _labels: Array[Label] = []
## Slot index -> its cell (null for the header).
var _cells: Array[PanelContainer] = []
var _panel: PanelContainer
var _scroll: ScrollContainer
var _ammo: Label
var _placed_for := ""
var _compact := false


func _ready() -> void:
	_build()


func _process(_delta: float) -> void:
	_panel.visible = not HudLayout.paused(get_tree())
	var key := HudLayout.layout_key(self)
	if key != _placed_for:
		_placed_for = key
		HudLayout.place(_panel, HudLayout.Piece.WEAPON)
		var m := HudLayout.metrics(self)
		_set_compact(HudLayout.is_compact(m.canvas, m.scale, m.touch))
	var peer := multiplayer.get_unique_id()
	var hand := Hand.for_peer(get_tree(), peer)
	var hand_def := ItemCatalog.find(hand.net_item_id if hand != null else "")
	var holding_weapon := hand_def != null and hand_def.category == ItemDefinition.Category.WEAPON
	var rig := GunRig.for_peer(get_tree(), peer)
	var rig_active := rig != null and rig.is_active()
	var rig_name := (
		str(rig.net_stats["display_name"]) if rig != null and not rig.net_stats.is_empty() else ""
	)
	var held := hand_def.display_name if hand_def != null else ""
	if rig_active and held.is_empty():
		held = rig_name
	_set_slot(HAND_SLOT, held, holding_weapon or rig_active)
	var selected := _selected_slot()
	var holding := hand_def != null and not rig_active
	var backpack := hand.inventory().backpack if hand != null else PackedStringArray()
	for slot: int in PlayerInventory.CAPACITY:
		var id := backpack[slot] if slot < backpack.size() else ""
		_set_slot(slot + 1, _display_name(id), holding and selected == slot + 1)
	_set_slot(RIG_SLOT, rig_name, rig_active)
	var ammo := GunStatsPanel.ammo_text(get_tree(), peer)
	if _ammo.text != ammo:
		_ammo.text = ammo


## The HUD slot index weapon_hotbar.gd last equipped, or -1.
func _selected_slot() -> int:
	var hotbar := get_parent()
	if hotbar == null or not "selected" in hotbar:
		return -1
	var cycle: int = hotbar.selected
	if cycle < 0:
		return -1
	return RIG_SLOT if cycle >= PlayerInventory.CAPACITY else cycle + 1


func _on_slot_pressed(slot: int) -> void:
	var hotbar := get_parent()
	if hotbar == null or not hotbar.has_method("equip_slot"):
		return
	hotbar.equip_slot(PlayerInventory.CAPACITY if slot == RIG_SLOT else slot - 1)


## Compact: fixed touch-sized cells in a sideways-scrolling row; otherwise the cells
## share the panel's width.
func _set_compact(compact: bool) -> void:
	_compact = compact
	for slot: int in range(1, SLOT_COUNT):
		var cell := _cells[slot]
		cell.custom_minimum_size = (
			Vector2.ONE * HudLayout.TOUCH_SLOT if compact else Vector2(0, 0)
		)
		cell.size_flags_horizontal = (
			Control.SIZE_SHRINK_BEGIN if compact else Control.SIZE_EXPAND_FILL
		)
		_labels[slot].text = ""


func _set_slot(slot: int, text: String, active: bool) -> void:
	var label := _labels[slot]
	var display := text if not text.is_empty() else "—"
	if _compact and slot != HAND_SLOT:
		display = short_name(display)
	if label.text != display:
		label.text = display
	var color := ACTIVE_COLOR if active else IDLE_COLOR
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)
	var cell := _cells[slot]
	var variation := &"HudSlotActive" if active else &"HudSlot"
	if cell != null and cell.theme_type_variation != variation:
		cell.theme_type_variation = variation


## "Revolver" -> "Revolve", the first word cut to fit a 52-unit touch slot.
static func short_name(text: String) -> String:
	var word := text.get_slice(" ", 0)
	return word.left(SHORT_NAME_LENGTH)


func _display_name(id: String) -> String:
	if id.is_empty():
		return ""
	var def := ItemCatalog.find(id)
	return def.display_name if def != null else id


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.theme = HUD_THEME
	_panel.theme_type_variation = &"HudPlate"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_to_group(&"touch_hud")
	add_child(_panel)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 3)
	_panel.add_child(column)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	var held := _label("Weapon", &"HudTitle", "—")
	held.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	held.clip_text = true
	held.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(held)
	_labels.append(held)
	_cells.append(null)
	_ammo = _label("Ammo", &"HudTitle", "")
	_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo.add_theme_color_override("font_color", ACTIVE_COLOR)
	header.add_child(_ammo)
	# Swipe or drag sideways when the slots don't fit; the bar itself stays hidden.
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_scroll)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 3)
	_scroll.add_child(row)
	for slot: int in range(1, SLOT_COUNT):
		row.add_child(_build_slot(slot))


func _build_slot(slot: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.name = "Rig" if slot == RIG_SLOT else "Slot%d" % slot
	cell.theme_type_variation = &"HudSlot"
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	cell.add_child(box)
	var key := _label("Key", &"HudAccent", str(slot))
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(key)
	var name_label := _label("Name", &"HudDetail", "—")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.custom_minimum_size.x = 1
	name_label.add_theme_font_size_override("font_size", 10)
	box.add_child(name_label)
	# A flat, transparent button over the cell: tap or click to equip. Drags pass through
	# to the scroll row so a swipe scrolls instead of equipping.
	var tap := Button.new()
	tap.name = "Tap"
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.mouse_filter = Control.MOUSE_FILTER_PASS
	tap.tooltip_text = ""
	tap.pressed.connect(_on_slot_pressed.bind(slot))
	cell.add_child(tap)
	_labels.append(name_label)
	_cells.append(cell)
	return cell


func _label(label_name: String, variation: StringName, text: String) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = text
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
