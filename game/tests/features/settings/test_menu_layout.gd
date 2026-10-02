extends GutTest

const Login := preload("res://ui/login/login_screen.gd")


func test_portrait_and_landscape_forms_fit_and_scroll() -> void:
	for dimensions: Vector2i in [Vector2i(320, 568), Vector2i(640, 320), Vector2i(320, 240)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		add_child_autofree(viewport)
		var menu := Login.new()
		viewport.add_child(menu)
		menu._open()
		menu._show_sign_up()
		await wait_frames(5)
		var bounds := menu._panel.get_global_rect()
		assert_gte(bounds.position.x, 0.0)
		assert_gte(bounds.position.y, 0.0)
		assert_lte(bounds.end.x, float(dimensions.x))
		assert_lte(bounds.end.y, float(dimensions.y))
		if dimensions.y < 400:
			assert_gt(menu._scroll.get_v_scroll_bar().max_value, menu._scroll.size.y)
			menu._scroll.scroll_vertical = 10000
			await wait_frames(3)
			assert_gt(menu._scroll.scroll_vertical, 0)
		for child: Node in menu._box.get_children():
			if child is Button or child is LineEdit:
				assert_gte((child as Control).size.y, 48.0)


func test_stretched_phone_canvas_keeps_readable_physical_targets() -> void:
	var window := Window.new()
	window.size = Vector2i(360, 640)
	window.content_scale_size = Vector2i(1280, 720)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	add_child_autofree(window)
	var menu := Login.new()
	window.add_child(menu)
	menu._open()
	menu._show_offline_menu()
	await wait_frames(5)
	menu._resize_panel()
	await wait_frames(5)
	var scale := window.get_stretch_transform().get_scale().x
	assert_lt(scale, 1.0, "Exercise the project's scaled design canvas")
	assert_gte(menu._theme.default_font_size * scale, 18.0)
	assert_lte(menu._panel.size.x * scale, 360.0)
	assert_lte(menu._panel.size.y * scale, 640.0)
	for child: Node in menu._box.get_children():
		if child is Button:
			assert_gte((child as Button).size.y * scale, 47.9)
	window.size = Vector2i(640, 360)
	await wait_frames(5)
	var landscape_scale := window.get_stretch_transform().get_scale().x
	assert_lte(menu._panel.size.x * landscape_scale, 640.0)
	assert_lte(menu._panel.size.y * landscape_scale, 360.0)
	for child: Node in menu._box.get_children():
		if child is Button:
			assert_gte((child as Button).size.y * landscape_scale, 47.9)
	assert_eq(Login.UI_THEME.default_font_size, 19, "Do not resize the shared theme")


func test_page_change_resets_scroll_and_focus_can_follow_buttons() -> void:
	var menu := Login.new()
	add_child_autofree(menu)
	menu._show_sign_up()
	await wait_frames(2)
	menu._scroll.scroll_vertical = 500
	menu._show_offline_menu()
	assert_eq(menu._scroll.scroll_vertical, 0)
	assert_true(menu._scroll.follow_focus)
	for child: Node in menu._box.get_children():
		if child is Button:
			assert_eq((child as Button).autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
