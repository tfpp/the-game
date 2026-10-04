extends GutTest
## ui/hud_layout.gd: where the weapon panel, wallet and HP bar sit on each screen shape.

const W := HudLayout.Piece.WEAPON
const M := HudLayout.Piece.MONEY
const H := HudLayout.Piece.HEALTH


func test_wide_screens_put_weapon_bottom_center_and_money_over_hp_bottom_right() -> void:
	for canvas: Vector2 in [Vector2(1280, 720), Vector2(1680, 720), Vector2(1280, 960)]:
		var weapon := HudLayout.rect_for(W, canvas, 1.0, false)
		var money := HudLayout.rect_for(M, canvas, 1.0, false)
		var health := HudLayout.rect_for(H, canvas, 1.0, false)
		assert_almost_eq(weapon.get_center().x, canvas.x * 0.5, 0.01)
		assert_almost_eq(weapon.end.y, canvas.y - HudLayout.MARGIN, 0.01)
		assert_almost_eq(health.end, canvas - Vector2.ONE * HudLayout.MARGIN, Vector2.ONE * 0.01)
		assert_lt(money.end.y, health.position.y, "Money sits above the HP bar")
		assert_almost_eq(money.end.x, health.end.x, 0.01)
		assert_false(weapon.intersects(money) or weapon.intersects(health))


func test_narrow_and_touch_screens_stack_one_centered_column_on_screen() -> void:
	# 4:3 small laptop, phone portrait/landscape canvases, each scaled up for touch.
	for canvas: Vector2 in [Vector2(800, 600), Vector2(1280, 2275), Vector2(1280, 590)]:
		for touch: bool in [false, true]:
			var scale := 1.0 if canvas.x < 960 else 2.0
			var rects: Array[Rect2] = []
			for piece: HudLayout.Piece in [W, M, H]:
				rects.append(HudLayout.rect_for(piece, canvas, scale, touch))
			for rect: Rect2 in rects:
				assert_true(Rect2(Vector2.ZERO, canvas).encloses(rect), "%s on screen" % rect)
				assert_almost_eq(rect.get_center().x, canvas.x * 0.5, 0.01)
			assert_false(rects[0].intersects(rects[1]) or rects[1].intersects(rects[2]))
			assert_false(rects[0].intersects(rects[2]))
			if touch:
				assert_lt(rects[0].position.y, rects[1].position.y, "Weapon on top for touch")
			else:
				assert_gt(rects[0].position.y, rects[2].position.y, "Weapon at the bottom")


func test_safe_inset_keeps_pieces_off_the_edges() -> void:
	var health := HudLayout.rect_for(H, Vector2(1280, 720), 1.0, false, 30.0)
	assert_almost_eq(health.end.x, 1280.0 - HudLayout.MARGIN - 30.0, 0.01)


func test_phone_canvas_scales_the_hud_up_but_never_shrinks_it() -> void:
	assert_eq(HudLayout.hud_scale(1.0), 1.0)
	assert_eq(HudLayout.hud_scale(1.5), 1.0)
	assert_gt(HudLayout.hud_scale(0.4), 1.5)
	assert_eq(HudLayout.hud_scale(0.1), 3.0)


func test_weapon_panel_shrinks_to_fit() -> void:
	var size := HudLayout.piece_size(W, Vector2(320, 568), 1.0)
	assert_lte(size.x, 320.0 - HudLayout.MARGIN * 2.0)
