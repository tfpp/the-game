class_name HudLayout
extends RefCounted
## Shared placement for the gameplay HUD pieces owned by different features: the weapon
## panel (features/weapon_hotbar), the wallet chip (features/money), the HP bar
## (features/combat) and the VOICE plate (ui/hud.gd). Each HUD calls `place()` on resize
## so the pieces never overlap without knowing about each other. features/touch_controls
## reads `voice_rect()` to keep its pause and CAM buttons under the VOICE plate.
##
## Layouts, in canvas units (the project stretches a 1280x720 design canvas):
## - every layout: a small money chip top-left and the VOICE plate top-right, inside the
##   safe area; the center stays clear for aiming.
## - wide: weapon panel bottom-center; HP bar alone in the bottom-right corner.
## - narrow (small windows without touch): the weapon panel spans the bottom with
##   scrollable 44pt+ slots, and the HP bar sits above it on the right.
## - touch: the weapon panel at the top between the money chip and the VOICE plate (or
##   in a second row under the chip when that gap is too small), away from the thumb
##   sticks; the HP bar bottom-center, between the joystick and the action buttons.
## `hud_scale()` enlarges everything when the canvas is shrunk onto a small screen.
## Everything hides while the pause menu (ui/login) is open: see `paused()`.

enum Piece { WEAPON, MONEY, HEALTH }

const MARGIN := 16.0
const GAP := 8.0
const NARROW_WIDTH := 960.0
## Group the pause menu joins while open.
const PAUSE_GROUP := &"pause_menu"
## Base (unscaled) sizes of each piece. The weapon panel grows taller when its slots
## become 52-unit touch targets (`COMPACT_WEAPON_HEIGHT`) and stretches to fit.
const SIZES := {
	Piece.WEAPON: Vector2(460, 66),
	Piece.MONEY: Vector2(132, 28),
	Piece.HEALTH: Vector2(200, 20),
}
const COMPACT_WEAPON_HEIGHT := 92.0
## Slot cells on narrow and touch layouts; at hud_scale >= 0.9/stretch this stays above
## 44 physical pixels (52 * 0.9 = 46.8).
const TOUCH_SLOT := 52.0
## Narrowest useful top-row weapon panel (about three touch slots).
const MIN_TOUCH_WEAPON_WIDTH := 190.0
## The VOICE plate: fixed width so its corner is predictable, two text lines.
const VOICE_SIZE := Vector2(190, 42)


## Multiplier for HUD pieces so they keep a readable physical size when the design
## canvas is stretched down (phones), without growing on desktop.
static func hud_scale(stretch: float) -> float:
	return clampf(0.9 / maxf(stretch, 0.01), 1.0, 3.0)


static func is_narrow(canvas: Vector2, scale: float) -> bool:
	return canvas.x / scale < NARROW_WIDTH


## Weapon slots become big, scrollable touch targets on narrow and touch layouts.
static func is_compact(canvas: Vector2, scale: float, touch: bool) -> bool:
	return touch or is_narrow(canvas, scale)


## The VOICE plate's rectangle (scaled size), top-right inside the margin.
static func voice_rect(canvas: Vector2, scale: float, inset: float = 0.0) -> Rect2:
	var margin := MARGIN + inset
	var size := VOICE_SIZE * scale
	return Rect2(Vector2(canvas.x - margin - size.x, margin), size)


## The piece's on-screen rectangle (position and *scaled* size) in a canvas of size
## `canvas`, keeping `inset` extra canvas units clear of each edge (device safe area).
static func rect_for(
	piece: Piece, canvas: Vector2, scale: float, touch: bool, inset: float = 0.0
) -> Rect2:
	var margin := MARGIN + inset
	var size := piece_size(piece, canvas, scale, touch, inset) * scale
	var gap := GAP * scale
	match piece:
		Piece.MONEY:
			return Rect2(Vector2(margin, margin), size)
		Piece.WEAPON:
			if touch:
				return Rect2(_touch_weapon_origin(canvas, scale, inset), size)
			return Rect2(Vector2((canvas.x - size.x) * 0.5, canvas.y - margin - size.y), size)
	# Health.
	if touch:
		return Rect2(Vector2((canvas.x - size.x) * 0.5, canvas.y - margin - size.y), size)
	var corner := canvas - Vector2(margin, margin)
	if not is_narrow(canvas, scale):
		return Rect2(corner - size, size)
	var weapon := rect_for(Piece.WEAPON, canvas, scale, touch, inset)
	return Rect2(Vector2(corner.x - size.x, weapon.position.y - gap - size.y), size)


## Unscaled size. The weapon panel fits the space its layout leaves it.
static func piece_size(
	piece: Piece, canvas: Vector2, scale: float, touch: bool = false, inset: float = 0.0
) -> Vector2:
	var size: Vector2 = SIZES[piece]
	if piece != Piece.WEAPON:
		return size
	if is_compact(canvas, scale, touch):
		size.y = COMPACT_WEAPON_HEIGHT
	var margin := MARGIN + inset
	if touch:
		size.x = _touch_weapon_span(canvas, scale, inset).y / scale
	else:
		size.x = minf(size.x, maxf(160.0, canvas.x / scale - margin * 2.0))
		if is_narrow(canvas, scale):
			size.x = maxf(160.0, (canvas.x - margin * 2.0) / scale)
	return size


## Whether the touch weapon panel fits in the top row beside the money chip.
static func touch_weapon_in_top_row(canvas: Vector2, scale: float, inset: float = 0.0) -> bool:
	var left := MARGIN + inset + (SIZES[Piece.MONEY].x + GAP) * scale
	var right := voice_rect(canvas, scale, inset).position.x - GAP * scale
	return right - left >= MIN_TOUCH_WEAPON_WIDTH * scale


## x start and width (canvas units) of the touch weapon panel.
static func _touch_weapon_span(canvas: Vector2, scale: float, inset: float) -> Vector2:
	var margin := MARGIN + inset
	var right := voice_rect(canvas, scale, inset).position.x - GAP * scale
	var left := margin
	if touch_weapon_in_top_row(canvas, scale, inset):
		left += (SIZES[Piece.MONEY].x + GAP) * scale
	return Vector2(left, maxf(right - left, 0.0))


static func _touch_weapon_origin(canvas: Vector2, scale: float, inset: float) -> Vector2:
	var span := _touch_weapon_span(canvas, scale, inset)
	var y := MARGIN + inset
	if not touch_weapon_in_top_row(canvas, scale, inset):
		y += (SIZES[Piece.MONEY].y + GAP) * scale
	return Vector2(span.x, y)


## Extra canvas units to keep clear of notches and rounded corners, from the OS safe
## area. Browsers report the full window here; touch controls read the CSS safe area.
static func safe_inset(viewport: Viewport) -> float:
	var window := viewport.get_window()
	if window == null or window.mode != Window.MODE_FULLSCREEN:
		return 0.0
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if screen.x <= 0 or safe.size.x <= 0:
		return 0.0
	var px := maxf(
		maxf(float(safe.position.x), float(safe.position.y)),
		maxf(float(screen.x - safe.end.x), float(screen.y - safe.end.y))
	)
	var stretch := viewport.get_stretch_transform().get_scale().x
	return px / maxf(stretch, 0.01)


## Current canvas size, HUD scale, touch layout and safe inset for `node`'s viewport.
static func metrics(node: Node) -> Dictionary:
	var viewport := node.get_viewport()
	return {
		"canvas": viewport.get_visible_rect().size,
		"scale": hud_scale(viewport.get_stretch_transform().get_scale().x),
		"touch": uses_touch_layout(),
		"inset": safe_inset(viewport),
	}


## Positions `control` (anchored top-left, unscaled size = piece_size) for `piece`.
static func place(control: Control, piece: Piece) -> void:
	if control.get_viewport() == null:
		return
	var m := metrics(control)
	var rect := rect_for(piece, m.canvas, m.scale, m.touch, m.inset)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.scale = Vector2.ONE * m.scale
	control.position = rect.position
	control.size = piece_size(piece, m.canvas, m.scale, m.touch, m.inset)


## Positions the VOICE plate (anchored top-left, unscaled size VOICE_SIZE).
static func place_voice(control: Control) -> void:
	if control.get_viewport() == null:
		return
	var m := metrics(control)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.pivot_offset = Vector2.ZERO
	control.scale = Vector2.ONE * m.scale
	control.position = voice_rect(m.canvas, m.scale, m.inset).position
	control.size = VOICE_SIZE


static func uses_touch_layout() -> bool:
	return Controls.device == Controls.Device.TOUCH


## True while the pause menu is open: every gameplay HUD piece hides under it.
static func paused(tree: SceneTree) -> bool:
	return tree != null and tree.get_first_node_in_group(PAUSE_GROUP) != null


## Changes whenever the HUD needs re-placing: viewport size, stretch or input device.
## Cheap enough to compare every frame instead of wiring resize and device signals.
static func layout_key(node: Node) -> String:
	var viewport := node.get_viewport()
	if viewport == null:
		return ""
	return (
		"%s|%s|%d"
		% [
			viewport.get_visible_rect().size,
			viewport.get_stretch_transform().get_scale().x,
			int(uses_touch_layout()),
		]
	)
