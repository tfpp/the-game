class_name LootToast
extends CanvasLayer
## A short local "Picked up <name> ($<value>)" message near the top of the
## screen. Created on demand by `show_text()`; newer pickups replace the text
## and restart the timer, so rapid looting never stacks overlapping toasts.

const GROUP := &"loot_toast"
const DURATION_S := 2.5
const FADE_S := 0.4

var _label := Label.new()
var _remaining := 0.0


## Pure text for one claimed item, e.g. "Picked up Watch ($10)".
static func pickup_message(id: String) -> String:
	var definition := ItemCatalog.find(id)
	var item_name := definition.display_name if definition != null else id
	var cents := definition.sale_value_cents if definition != null else 0
	if cents <= 0:
		return "Picked up %s" % item_name
	if cents % 100 == 0:
		return "Picked up %s ($%d)" % [item_name, cents / 100]
	return "Picked up %s ($%d.%02d)" % [item_name, cents / 100, cents % 100]


## Shows `text` for this client only, reusing one toast per scene tree.
static func show_text(
	tree: SceneTree, text: String, color := Color.WHITE, duration := DURATION_S
) -> LootToast:
	var toast := tree.get_first_node_in_group(GROUP) as LootToast
	if toast == null:
		toast = LootToast.new()
		tree.root.add_child(toast)
	toast.display(text, color, duration)
	return toast


func _init() -> void:
	layer = 20
	add_to_group(GROUP)
	_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_label.offset_top = 96
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", 22)
	_label.add_theme_constant_override(&"outline_size", 6)
	_label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	_label.visible = false
	add_child(_label)


func display(text: String, color := Color.WHITE, duration := DURATION_S) -> void:
	_label.text = text
	_label.add_theme_color_override(&"font_color", color)
	_label.modulate.a = 1.0
	_label.visible = true
	_remaining = duration


func shown_text() -> String:
	return _label.text if _label.visible else ""


func _process(delta: float) -> void:
	if not _label.visible:
		return
	_remaining -= delta
	_label.modulate.a = clampf(_remaining / FADE_S, 0.0, 1.0)
	if _remaining <= 0.0:
		_label.visible = false
