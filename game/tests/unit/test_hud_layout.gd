extends GutTest
## ui/hud_layout.gd: where the weapon panel, money chip, HP bar and VOICE plate sit on
## each screen shape, and that nothing overlaps (each other or the touch controls).

const W := HudLayout.Piece.WEAPON
const M := HudLayout.Piece.MONEY
const H := HudLayout.Piece.HEALTH

## Window sizes in physical pixels: 16:9, ultrawide, tablet, small laptop, iPhone
## portrait and landscape (CSS and device pixels).
const SCREENS := [
	Vector2(1920, 1080),
	Vector2(2560, 1080),
	Vector2(1024, 768),
	Vector2(1180, 820),
	Vector2(800, 600),
	Vector2(390, 844),
	Vector2(1170, 2532),
	Vector2(844, 390),
	Vector2(2532, 1170),
]


## canvas_items + expand stretch of the 1280x720 design canvas.
func _canvas(window: Vector2) -> Dictionary:
	var stretch := minf(window.x / 1280.0, window.y / 720.0)
	return {"canvas": window / stretch, "scale": HudLayout.hud_scale(stretch)}


## The touch controls' fixed targets in canvas units (features/touch_controls, ui_scale
## 1 for these canvases): stick bases, FIRE/USE/JUMP, and pause + CAM.
func _touch_rects(canvas: Vector2, scale: float) -> Array[Rect2]:
	var stick := Vector2.ONE * 76.0
	var action := Vector2.ONE * 34.0
	var aim := canvas - Vector2(132, 132)
	var use := aim - Vector2(0, 168)
	var top := maxf(72.0, HudLayout.voice_rect(canvas, scale).end.y + HudLayout.GAP)
	return [
		Rect2(Vector2(132, canvas.y - 132) - stick, stick * 2.0),
		Rect2(aim - stick, stick * 2.0),
		Rect2(use - action, action * 2.0),
		Rect2(use - Vector2(82, 0) - action, action * 2.0),
		Rect2(use + Vector2(82, 0) - action, action * 2.0),
		Rect2(canvas.x - 176, top, 152, 48),
	]


func test_no_hud_piece_overlaps_or_leaves_the_screen_on_any_device() -> void:
	for window: Vector2 in SCREENS:
		var view := _canvas(window)
		var canvas: Vector2 = view.canvas
		var scale: float = view.scale
		for touch: bool in [false, true]:
			var rects: Array[Rect2] = [HudLayout.voice_rect(canvas, scale)]
			for piece: HudLayout.Piece in [W, M, H]:
				rects.append(HudLayout.rect_for(piece, canvas, scale, touch))
			if touch:
				rects.append_array(_touch_rects(canvas, scale))
			var screen := Rect2(Vector2.ZERO, canvas)
			for i: int in rects.size():
				assert_true(screen.encloses(rects[i]), "%s on %s" % [rects[i], window])
				for j: int in range(i + 1, rects.size()):
					assert_false(
						rects[i].intersects(rects[j]),
						"%s / %s overlap on %s touch=%s" % [rects[i], rects[j], window, touch]
					)


func test_center_stays_clear_for_aiming() -> void:
	for window: Vector2 in SCREENS:
		var view := _canvas(window)
		var canvas: Vector2 = view.canvas
		var center := Rect2(canvas * 0.5 - Vector2(120, 120), Vector2(240, 240))
		for touch: bool in [false, true]:
			for piece: HudLayout.Piece in [W, M, H]:
				var rect := HudLayout.rect_for(piece, canvas, view.scale, touch)
				assert_false(rect.intersects(center), "%s clear of the crosshair" % rect)


func test_money_is_a_small_top_left_chip_apart_from_hp() -> void:
	for window: Vector2 in SCREENS:
		var view := _canvas(window)
		for touch: bool in [false, true]:
			var money := HudLayout.rect_for(M, view.canvas, view.scale, touch)
			var health := HudLayout.rect_for(H, view.canvas, view.scale, touch)
			assert_eq(money.position, Vector2.ONE * HudLayout.MARGIN)
			assert_lt(money.size.x, view.canvas.x * 0.4, "Compact on %s" % window)
			assert_gt(health.position.y, view.canvas.y * 0.5, "HP stays at the bottom")


func test_wide_screens_put_weapon_bottom_center_and_hp_bottom_right() -> void:
	for canvas: Vector2 in [Vector2(1280, 720), Vector2(1680, 720), Vector2(1280, 960)]:
		var weapon := HudLayout.rect_for(W, canvas, 1.0, false)
		var health := HudLayout.rect_for(H, canvas, 1.0, false)
		assert_almost_eq(weapon.get_center().x, canvas.x * 0.5, 0.01)
		assert_almost_eq(weapon.end.y, canvas.y - HudLayout.MARGIN, 0.01)
		assert_almost_eq(health.end, canvas - Vector2.ONE * HudLayout.MARGIN, Vector2.ONE * 0.01)
		assert_false(HudLayout.is_compact(canvas, 1.0, false))


func test_touch_puts_weapon_slots_at_the_top_with_44pt_targets() -> void:
	for window: Vector2 in [Vector2(390, 844), Vector2(844, 390), Vector2(1024, 768)]:
		var stretch := minf(window.x / 1280.0, window.y / 720.0)
		var view := _canvas(window)
		var weapon := HudLayout.rect_for(W, view.canvas, view.scale, true)
		assert_lt(weapon.end.y, view.canvas.y * 0.5, "Top half on %s" % window)
		assert_true(HudLayout.is_compact(view.canvas, view.scale, true))
		assert_gte(HudLayout.TOUCH_SLOT * view.scale * stretch, 44.0, "Slot on %s" % window)


func test_narrow_desktop_spans_the_bottom_and_keeps_hp_above_it() -> void:
	var view := _canvas(Vector2(800, 600))
	var weapon := HudLayout.rect_for(W, view.canvas, view.scale, false)
	var health := HudLayout.rect_for(H, view.canvas, view.scale, false)
	assert_true(HudLayout.is_compact(view.canvas, view.scale, false))
	assert_almost_eq(weapon.position.x, HudLayout.MARGIN, 0.01)
	assert_lt(health.end.y, weapon.position.y)


func test_safe_inset_keeps_pieces_off_the_edges() -> void:
	var health := HudLayout.rect_for(H, Vector2(1280, 720), 1.0, false, 30.0)
	assert_almost_eq(health.end.x, 1280.0 - HudLayout.MARGIN - 30.0, 0.01)
	var money := HudLayout.rect_for(M, Vector2(1280, 720), 1.0, true, 30.0)
	assert_eq(money.position, Vector2.ONE * (HudLayout.MARGIN + 30.0))


func test_phone_canvas_scales_the_hud_up_but_never_shrinks_it() -> void:
	assert_eq(HudLayout.hud_scale(1.0), 1.0)
	assert_eq(HudLayout.hud_scale(1.5), 1.0)
	assert_gt(HudLayout.hud_scale(0.4), 1.5)
	assert_eq(HudLayout.hud_scale(0.1), 3.0)
