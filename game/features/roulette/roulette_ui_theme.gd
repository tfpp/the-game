class_name RouletteUiTheme
extends RefCounted
## Golden Crown table furniture for the roulette screens: a mahogany-and-brass panel
## over green felt, a burgundy velvet title plaque, cream enamel buttons with brass
## rims and a brass pointer over the selected chip. The textures in
## assets/roulette/ui/ are small pixel-art 9-slices; draw them with nearest filtering.

const PANEL := preload("res://assets/roulette/ui/panel.png")
const PLAQUE := preload("res://assets/roulette/ui/plaque.png")
const BUTTON := preload("res://assets/roulette/ui/button.png")
const CHIP_POINTER := preload("res://assets/roulette/ui/chip_pointer.png")
## Where the pointer sits above a 64-pixel chip icon at the top of its button.
const POINTER_RECT := Rect2(20, -18, 24, 17)
## Round chip faces baked by tools/bake_chip_icons.gd, in RouletteBets.DENOMINATIONS order.
const CHIP_ICONS: Array[Texture2D] = [
	preload("res://assets/roulette/ui/chip_1_icon.png"),
	preload("res://assets/roulette/ui/chip_5_icon.png"),
	preload("res://assets/roulette/ui/chip_50_icon.png"),
	preload("res://assets/roulette/ui/chip_100_icon.png"),
	preload("res://assets/roulette/ui/chip_500_icon.png"),
	preload("res://assets/roulette/ui/chip_1000_icon.png"),
	preload("res://assets/roulette/ui/chip_5000_icon.png"),
	preload("res://assets/roulette/ui/chip_25000_icon.png"),
]
const BODY_FONT := preload("res://assets/fonts/barlow/Barlow-SemiBold.ttf")
const HEADING_FONT := preload("res://assets/fonts/exo2/Exo2-Bold.ttf")

const CREAM := Color("f1e4c3")
const BRASS := Color("e0b85a")
const MAHOGANY := Color("3a1a10")
const MUTED := Color("b9ab8c")

## Theme type variations: the title bar and the borderless chip slots.
const PLAQUE_TYPE := &"RoulettePlaque"
const CHIP_TYPE := &"RouletteChip"

static var _theme: Theme


## The shared theme; build once and reuse on every screen.
static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _build() -> Theme:
	var theme := Theme.new()
	theme.default_font = BODY_FONT
	theme.default_font_size = 16
	theme.set_stylebox(&"panel", &"PanelContainer", _slice(PANEL, 12, Vector4(20, 14, 20, 14)))
	theme.set_type_variation(PLAQUE_TYPE, &"PanelContainer")
	theme.set_stylebox(&"panel", PLAQUE_TYPE, _slice(PLAQUE, 10, Vector4(22, 8, 22, 8)))
	theme.set_color(&"font_color", &"Label", CREAM)
	theme.set_color(&"font_outline_color", &"Label", Color(0, 0, 0, 0.6))
	theme.set_constant(&"outline_size", &"Label", 2)
	theme.set_type_variation(&"HeadingLabel", &"Label")
	theme.set_font(&"font", &"HeadingLabel", HEADING_FONT)
	theme.set_color(&"font_color", &"HeadingLabel", BRASS)
	var states := {
		&"normal": Color.WHITE,
		&"hover": Color(1.12, 1.1, 1.02),
		&"pressed": Color(0.78, 0.74, 0.66),
		&"hover_pressed": Color(0.86, 0.82, 0.74),
		&"disabled": Color(0.55, 0.52, 0.48, 0.8),
	}
	for state: StringName in states:
		var box := _slice(BUTTON, 8, Vector4(16, 6, 16, 6))
		box.modulate_color = states[state]
		theme.set_stylebox(state, &"Button", box)
	theme.set_stylebox(&"focus", &"Button", StyleBoxEmpty.new())
	theme.set_color(&"font_color", &"Button", MAHOGANY)
	theme.set_color(&"font_hover_color", &"Button", MAHOGANY)
	theme.set_color(&"font_pressed_color", &"Button", MAHOGANY)
	theme.set_color(&"font_hover_pressed_color", &"Button", MAHOGANY)
	theme.set_color(&"font_disabled_color", &"Button", Color(MAHOGANY, 0.55))
	theme.set_type_variation(CHIP_TYPE, &"Button")
	for state: StringName in states:
		theme.set_stylebox(state, CHIP_TYPE, StyleBoxEmpty.new())
	for color: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color"]:
		theme.set_color(color, CHIP_TYPE, CREAM)
	theme.set_color(&"font_hover_pressed_color", CHIP_TYPE, BRASS)
	theme.set_color(&"font_disabled_color", CHIP_TYPE, Color(MUTED, 0.5))
	theme.set_color(&"icon_disabled_color", CHIP_TYPE, Color(0.45, 0.45, 0.45, 0.6))
	theme.set_color(&"font_outline_color", CHIP_TYPE, Color(0, 0, 0, 0.7))
	theme.set_constant(&"outline_size", CHIP_TYPE, 2)
	return theme


## A root control for a roulette screen: themed, full-rect, pixel-crisp.
static func root() -> Control:
	var control := Control.new()
	control.theme = get_theme()
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return control


## A brass pointer shown above the selected chip in the rack; add it to the chip's button.
static func chip_pointer() -> TextureRect:
	var pointer := TextureRect.new()
	pointer.name = "Selection"
	pointer.texture = CHIP_POINTER
	pointer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pointer.stretch_mode = TextureRect.STRETCH_SCALE
	pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer.position = POINTER_RECT.position
	pointer.size = POINTER_RECT.size
	pointer.visible = false
	return pointer


## A small brass-rimmed square showing a seat's colour; set it with `color_swatch`.
static func seat_swatch() -> Panel:
	var swatch := Panel.new()
	swatch.name = "SeatSwatch"
	swatch.custom_minimum_size = Vector2(16, 16)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return swatch


static func color_swatch(swatch: Control, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = BRASS
	box.set_border_width_all(2)
	swatch.add_theme_stylebox_override(&"panel", box)


## Nine-slice box: `margin` texture pixels of border, `content` (left, top, right,
## bottom) padding inside it.
static func _slice(texture: Texture2D, margin: int, content: Vector4) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = margin
	box.texture_margin_top = margin
	box.texture_margin_right = margin
	box.texture_margin_bottom = margin
	box.content_margin_left = content.x
	box.content_margin_top = content.y
	box.content_margin_right = content.z
	box.content_margin_bottom = content.w
	return box
