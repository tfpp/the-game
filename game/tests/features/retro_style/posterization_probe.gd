extends Node3D
## Real Compatibility framebuffer regression, including composition before quantization.

const Posterization := preload("res://features/retro_style/posterization.gd")
const SOURCE := Color(0.18, 0.43, 0.72)
var _effect: Posterization
var _prior_store := ""
var _failed := false


func _ready() -> void:
	_prior_store = SettingsStore.load_text(Posterization.STORE_NAME)
	SettingsStore.save_data(Posterization.STORE_NAME, {})
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_size = Vector2i.ZERO
	get_window().size = Vector2i(320, 240)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	camera.cull_mask = 1 | (1 << 2)
	add_child(camera)
	# World and equipped-item layers: neither shader uses a texture.
	_quad(Vector3(-0.9, 0.0, -3.0), 1)
	_quad(Vector3(0.9, 0.0, -2.0), 1 << 2)
	_add_lighting_and_transparency()
	var banana := preload("res://features/holdables/items/banana_view.tscn").instantiate() as Node3D
	banana.position = Vector3(0, -0.65, -1.0)
	banana.scale = Vector3.ONE * 2.0
	add_child(banana)
	var pistol := preload("res://features/holdables/items/pistol_view.tscn").instantiate() as Node3D
	pistol.position = Vector3(0, 0.65, -1.0)
	add_child(pistol)
	# Force an earlier automatic screen copy. The final pass must refresh it after UI.
	var earlier := CanvasLayer.new()
	earlier.layer = 0
	add_child(earlier)
	var reader := ColorRect.new()
	reader.size = Vector2(4, 4)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = (
		"shader_type canvas_item; render_mode unshaded, blend_disabled; "
		+ "uniform sampler2D screen : hint_screen_texture, filter_nearest; "
		+ "void fragment() { COLOR = textureLod(screen, SCREEN_UV, 0.0); }"
	)
	material.shader = shader
	reader.material = material
	earlier.add_child(reader)
	_patch(1, Vector2(8, 8), SOURCE)
	_patch(9, Vector2(48, 8), Color(0.7, 0.2, 0.5, 0.5))
	_patch(30, Vector2(88, 8), SOURCE)
	_effect = Posterization.new()
	add_child(_effect)
	_run.call_deferred()


func _patch(canvas_layer: int, at: Vector2, color: Color) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = canvas_layer
	add_child(canvas)
	var patch := ColorRect.new()
	patch.color = color
	patch.position = at
	patch.size = Vector2(30, 30)
	canvas.add_child(patch)


func _quad(at: Vector3, mask: int) -> void:
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.position = at
	quad.layers = mask
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = (
		"shader_type spatial; render_mode unshaded; "
		+ "void fragment() { ALBEDO = vec3(0.18, 0.43, 0.72); }"
	)
	material.shader = shader
	quad.material_override = material
	add_child(quad)


func _add_lighting_and_transparency() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.12, 0.24, 0.38)
	add_child(world)
	var sphere := MeshInstance3D.new()
	sphere.mesh = SphereMesh.new()
	sphere.position = Vector3(-1.4, 0.9, -3.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.6, 0.5, 0.4)
	sphere.material_override = material
	add_child(sphere)
	var light := OmniLight3D.new()
	light.position = Vector3(-1.0, 1.5, -1.5)
	light.light_color = Color(1.0, 0.7, 0.4)
	add_child(light)
	var glass := MeshInstance3D.new()
	glass.mesh = QuadMesh.new()
	glass.position = Vector3(0.9, -0.35, -1.5)
	var transparent := StandardMaterial3D.new()
	transparent.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	transparent.albedo_color = Color(0.8, 0.2, 0.3, 0.4)
	glass.material_override = transparent
	add_child(glass)


func _capture() -> Image:
	for frame: int in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _run() -> void:
	var off: Image = await _capture()
	var lighting_colors: Dictionary[Color, bool] = {}
	for y: int in range(42, 60):
		for x: int in range(42, 58):
			lighting_colors[off.get_pixel(x, y)] = true
	_check(lighting_colors.size() > 16, "Fixture contains an untextured lighting gradient")
	_effect.set_strength(1.0)
	var on: Image = await _capture()
	_check_composition(off, on, 4)
	for x: int in [20, 60, 100]:
		_check(
			_difference(on.get_pixel(x, 20), off.get_pixel(x, 20)) > 0.05,
			"HUD, translucent menu and topmost emote layer included after earlier screen read"
		)
	for x: int in [88, 232]:
		_check(_difference(on.get_pixel(x, 120), off.get_pixel(x, 120)) > 0.05, "Both 3D layers")
	_effect.set_strength(0.5)
	_check_composition(off, await _capture(), 32)
	_effect.set_strength(0.0)
	var restored: Image = await _capture()
	_check(off.get_data() == restored.get_data(), "Off restores exact original framebuffer")
	get_window().size = Vector2i(480, 360)
	var resized_off: Image = await _capture()
	_effect.set_strength(1.0)
	var resized: Image = await _capture()
	_check(resized.get_size() == Vector2i(480, 360), "Resize follows native viewport")
	_check(_effect._effect.size == Vector2(480, 360), "Pass fills resized viewport")
	_check_composition(resized_off, resized, 4)
	SettingsStore.save_text(Posterization.STORE_NAME, _prior_store)
	print("Posterization pixel probe: ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


func _check_composition(off: Image, on: Image, levels: int) -> void:
	var changed := 0
	var steps := float(levels - 1)
	for y: int in on.get_height():
		for x: int in on.get_width():
			var source := off.get_pixel(x, y)
			var color := on.get_pixel(x, y)
			for channel: int in 3:
				# Readback is 8-bit: tolerate rounding at a palette-bin boundary.
				var component: float = color[channel]
				_check(
					absf(component - roundf(component * steps) / steps) < 0.004,
					"Every final pixel lies on the RGB palette"
				)
				_check(
					absf(component - source[channel]) <= 0.5 / steps + 0.004,
					"Quantize final composed RGB, not a stale copy or individual texture"
				)
			if _difference(color, source) > 0.01:
				changed += 1
	_check(changed > 500, "Untextured world, lighting, background, items and UI change")


static func _difference(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _check(ok: bool, reason: String) -> void:
	if not ok and not _failed:
		push_error(reason)
	if not ok:
		_failed = true
