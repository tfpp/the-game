extends GutTest


func test_chip_icons_are_round_with_transparent_corners() -> void:
	assert_eq(RouletteUiTheme.CHIP_ICONS.size(), RouletteBets.DENOMINATIONS.size())
	for texture: Texture2D in RouletteUiTheme.CHIP_ICONS:
		var image := texture.get_image()
		assert_eq(image.get_size(), Vector2i(64, 64))
		assert_eq(image.get_pixel(0, 0).a, 0.0, "corner is cut away")
		assert_eq(image.get_pixel(63, 63).a, 0.0)
		assert_eq(image.get_pixel(32, 32).a, 1.0, "face is opaque")
		assert_eq(image.get_pixel(32, 4).a, 1.0, "rim is kept")


func test_theme_skins_panels_buttons_and_chips() -> void:
	var theme := RouletteUiTheme.get_theme()
	var panel := theme.get_stylebox(&"panel", &"PanelContainer") as StyleBoxTexture
	assert_eq(panel.texture, RouletteUiTheme.PANEL)
	var plaque := theme.get_stylebox(&"panel", RouletteUiTheme.PLAQUE_TYPE) as StyleBoxTexture
	assert_eq(plaque.texture, RouletteUiTheme.PLAQUE)
	var normal := theme.get_stylebox(&"normal", &"Button") as StyleBoxTexture
	var pressed := theme.get_stylebox(&"pressed", &"Button") as StyleBoxTexture
	assert_eq(normal.texture, RouletteUiTheme.BUTTON)
	assert_ne(normal.modulate_color, pressed.modulate_color, "pressed reads darker")
	assert_is(theme.get_stylebox(&"normal", RouletteUiTheme.CHIP_TYPE), StyleBoxEmpty)
	var root := RouletteUiTheme.root()
	assert_eq(root.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "pixel-crisp")
	root.free()
