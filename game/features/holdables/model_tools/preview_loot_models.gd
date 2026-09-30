extends Node3D
## Actual catalog models rendered by the same icon service used by inventory and stashes.

const DUMPSTER := preload("res://features/slum_alley/dumpster.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const SCREEN := preload("res://features/inventory/inventory_screen.gd")

var _renderer: ModelIconRenderer
var _canvas: CanvasLayer
var _caption: Label
var _icons: Dictionary[String, TextureRect] = {}
var _received := 0
var _screen: CanvasLayer
var _hand: Hand


func _ready() -> void:
	get_tree().root.size = Vector2i(1200, 800)
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	var background := ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color("202a32")
	_canvas.add_child(background)
	_caption = Label.new()
	_caption.position = Vector2(24, 24)
	_caption.add_theme_font_size_override("font_size", 24)
	_caption.text = "LOOT MODEL KIT / ICONS RENDERED FROM THE ACTUAL MODELS"
	_canvas.add_child(_caption)
	_renderer = ModelIconRenderer.for_control(_caption)
	_renderer.rendered.connect(_icon_ready)
	var keys: Array[String] = ["scene:dumpster", "item:scrap", "item:stolen_wallet"]
	var titles: Array[String] = ["DUMPSTER", "SCRAP METAL", "WALLET"]
	for index: int in keys.size():
		var panel := ColorRect.new()
		panel.color = Color("30404c")
		panel.position = Vector2(30 + index * 390, 170)
		panel.size = Vector2(360, 420)
		_canvas.add_child(panel)
		var icon := TextureRect.new()
		icon.position = panel.position + Vector2(20, 10)
		icon.size = Vector2(320, 320)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_canvas.add_child(icon)
		_icons[keys[index]] = icon
		var label := Label.new()
		label.text = titles[index] + "\n128 x 128 MODEL RENDER"
		label.position = panel.position + Vector2(20, 345)
		label.add_theme_font_size_override("font_size", 20)
		_canvas.add_child(label)
	_renderer.request_scene("dumpster", DUMPSTER)
	_renderer.request_item("scrap")
	_renderer.request_item("stolen_wallet")
	var hint := Label.new()
	hint.text = "Same mesh and 128px albedo in world, hand and inventory. "
	hint.text += "Press I to inspect the backpack."
	hint.position = Vector2(24, 740)
	hint.add_theme_font_size_override("font_size", 20)
	_canvas.add_child(hint)
	_build_inventory()


func _build_inventory() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	add_child(player)
	player.set_physics_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child(_hand)
	_hand.set_process(false)
	var money := PlayerMoney.new()
	add_child(money)
	money.set_process(false)
	money.balances = {1: 4250}
	_screen = SCREEN.new()
	add_child(_screen)
	for index: int in 5:
		_hand.inventory().collect_into_slot(
			["scrap", "stolen_wallet", "shirt:2", "pistol", "banana"][index], index
		)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_I:
		_screen.esc_menu_open()


func _icon_ready(key: String, texture: Texture2D) -> void:
	if not _icons.has(key):
		return
	_validate_thumbnail(key, texture)
	_icons[key].texture = texture
	_received += 1
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0].path_join("icons"))
		assert(
			(
				texture.get_image().save_png(
					args[0].path_join("icons/" + key.replace(":", "-") + ".png")
				)
				== OK
			)
		)
	if _received == 3:
		_capture.call_deferred()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	await get_tree().create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	assert(
		(
			get_viewport().get_texture().get_image().save_png(
				args[0].path_join("loot-model-icons.png")
			)
			== OK
		)
	)
	_screen.esc_menu_open()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	assert(
		(
			get_viewport().get_texture().get_image().save_png(
				args[0].path_join("inventory-model-icons.png")
			)
			== OK
		)
	)
	var stash := preload("res://features/loot/loot_container.tscn").instantiate() as LootContainer
	add_child(stash)
	stash.net_searched = true
	stash.net_contents = PackedStringArray(["scrap", "stolen_wallet"])
	_screen.open_stash(stash)
	await get_tree().create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	assert(
		(
			get_viewport().get_texture().get_image().save_png(
				args[0].path_join("stash-model-icons.png")
			)
			== OK
		)
	)
	print("LOOT_ICONS_CAPTURE PASS")
	get_tree().quit()


func _validate_thumbnail(key: String, texture: Texture2D) -> void:
	var image := texture.get_image()
	assert(image.get_size() == Vector2i(128, 128))
	var ink := 0
	var clear := 0
	for y: int in 128:
		for x: int in 128:
			var alpha := image.get_pixel(x, y).a
			if alpha > .1:
				ink += 1
			else:
				clear += 1
			if x < 2 or y < 2 or x > 125 or y > 125:
				assert(alpha < .1, "Thumbnail must fit without cropping " + key)
	assert(ink > 200 and clear > 200, "Model and transparent background must both be present")
	if key.begins_with("item:"):
		assert(
			_renderer.request_item(key.trim_prefix("item:")) == texture,
			"Repeated requests reuse the same texture"
		)
	else:
		assert(_renderer.request_scene("dumpster", DUMPSTER) == texture)
