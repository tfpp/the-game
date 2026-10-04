class_name HudLayout
extends RefCounted
## Shared placement for the gameplay HUD pieces owned by different features: the weapon
## panel (features/weapon_hotbar), the wallet (features/money) and the HP bar
## (features/combat). Each HUD calls `place()` on resize so they line up in one corner
## without knowing about each other.
##
## Layouts, in canvas units (the project stretches a 1280x720 design canvas):
## - wide: weapon panel bottom-center; money above HP in the bottom-right corner.
## - narrow (small windows, phones without touch): one centered column at the bottom,
##   money and HP stacked above the weapon panel.
## - touch: the same column at the top-center, clear of the thumb sticks and buttons.
## `hud_scale()` enlarges everything when the canvas is shrunk onto a small screen.

enum Piece { WEAPON, MONEY, HEALTH }

const MARGIN := 16.0
const GAP := 6.0
const NARROW_WIDTH := 960.0
## Base (unscaled) sizes of each piece.
const SIZES := {
	Piece.WEAPON: Vector2(460, 66),
	Piece.MONEY: Vector2(200, 32),
	Piece.HEALTH: Vector2(200, 20),
}


## Multiplier for HUD pieces so they keep a readable physical size when the design
## canvas is stretched down (phones), without growing on desktop.
static func hud_scale(stretch: float) -> float:
	return clampf(0.9 / maxf(stretch, 0.01), 1.0, 3.0)


static func is_narrow(canvas: Vector2, scale: float) -> bool:
	return canvas.x / scale < NARROW_WIDTH


## The piece's on-screen rectangle (position and *scaled* size) in a canvas of size
## `canvas`, keeping `inset` extra canvas units clear of each edge (device safe area).
static func rect_for(
	piece: Piece, canvas: Vector2, scale: float, touch: bool, inset: float = 0.0
) -> Rect2:
	var margin := MARGIN + inset
	var size := piece_size(piece, canvas, scale, inset) * scale
	var gap := GAP * scale
	var weapon := piece_size(Piece.WEAPON, canvas, scale, inset) * scale
	var health := (SIZES[Piece.HEALTH] as Vector2) * scale
	var money := (SIZES[Piece.MONEY] as Vector2) * scale
	if not touch and not is_narrow(canvas, scale):
		var corner := canvas - Vector2(margin, margin)
		match piece:
			Piece.WEAPON:
				return Rect2(Vector2((canvas.x - size.x) * 0.5, corner.y - size.y), size)
			Piece.HEALTH:
				return Rect2(corner - size, size)
			_:
				return Rect2(corner - size - Vector2(0, health.y + gap), size)
	# Stacked column, centered: weapon, money, HP from the screen edge inwards when on
	# top (touch); HP, money, weapon from the top down when at the bottom.
	var x := (canvas.x - size.x) * 0.5
	if touch:
		match piece:
			Piece.WEAPON:
				return Rect2(Vector2(x, margin), size)
			Piece.MONEY:
				return Rect2(Vector2(x, margin + weapon.y + gap), size)
			_:
				return Rect2(Vector2(x, margin + weapon.y + money.y + gap * 2.0), size)
	var bottom := canvas.y - margin
	match piece:
		Piece.WEAPON:
			return Rect2(Vector2(x, bottom - size.y), size)
		Piece.HEALTH:
			return Rect2(Vector2(x, bottom - weapon.y - gap - size.y), size)
		_:
			return Rect2(Vector2(x, bottom - weapon.y - health.y - gap * 2.0 - size.y), size)


## Unscaled size; the weapon panel shrinks to fit narrow canvases.
static func piece_size(piece: Piece, canvas: Vector2, scale: float, inset: float = 0.0) -> Vector2:
	var size: Vector2 = SIZES[piece]
	if piece == Piece.WEAPON:
		size.x = minf(size.x, maxf(160.0, canvas.x / scale - (MARGIN + inset) * 2.0))
	return size


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


## Positions `control` (anchored top-left, unscaled size = piece_size) for `piece`.
static func place(control: Control, piece: Piece) -> void:
	var viewport := control.get_viewport()
	if viewport == null:
		return
	var canvas := viewport.get_visible_rect().size
	var scale := hud_scale(viewport.get_stretch_transform().get_scale().x)
	var inset := safe_inset(viewport)
	var rect := rect_for(piece, canvas, scale, uses_touch_layout(), inset)
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.scale = Vector2.ONE * scale
	control.position = rect.position
	control.size = piece_size(piece, canvas, scale, inset)


static func uses_touch_layout() -> bool:
	return Controls.device == Controls.Device.TOUCH


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
