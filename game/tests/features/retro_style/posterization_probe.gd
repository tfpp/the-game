extends Node3D
## Run with a real Compatibility renderer, not --headless. Verifies framebuffer pixels.

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
	# World surface and a distinct equipped-item render layer, both authored shaders.
	_quad(Vector3(-0.9, 0.0, -3.0), 1)
	_quad(Vector3(0.9, 0.0, -2.0), 1 << 2)
	# Actual equipped item view meshes, unchanged by the viewport effect.
	var banana := preload("res://features/holdables/items/banana_view.tscn").instantiate() as Node3D
	banana.position = Vector3(0, -0.65, -1.0)
	banana.scale = Vector3.ONE * 2.0
	add_child(banana)
	var pistol := preload("res://features/holdables/items/pistol_view.tscn").instantiate() as Node3D
	pistol.position = Vector3(0, 0.65, -1.0)
	add_child(pistol)
	_effect = Posterization.new()
	add_child(_effect)
	var hud := CanvasLayer.new()
	hud.layer = 1
	add_child(hud)
	var patch := ColorRect.new()
	patch.color = SOURCE
	patch.position = Vector2(8, 8)
	patch.size = Vector2(30, 30)
	hud.add_child(patch)
	_run.call_deferred()


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


func _capture() -> Image:
	for frame: int in 3:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _run() -> void:
	var off: Image = await _capture()
	_effect.set_strength(1.0)
	var on: Image = await _capture()
	_check(off.get_pixel(20, 20).is_equal_approx(on.get_pixel(20, 20)), "HUD unchanged")
	var changed := 0
	for y: int in range(40, on.get_height()):
		for x: int in on.get_width():
			var color := on.get_pixel(x, y)
			for component: float in [color.r, color.g, color.b]:
				_check(absf(component * 3.0 - roundf(component * 3.0)) < 0.025, "RGB steps")
			if _difference(color, off.get_pixel(x, y)) > 0.05:
				changed += 1
	_check(changed > 500, "World and item pixels change")
	for x: int in [88, 232]:
		_check(_difference(on.get_pixel(x, 120), off.get_pixel(x, 120)) > 0.05, "Both 3D layers")
	_effect.set_strength(0.0)
	var restored: Image = await _capture()
	_check(off.get_data() == restored.get_data(), "Off restores exact original framebuffer")
	get_window().size = Vector2i(480, 360)
	_effect.set_strength(1.0)
	var resized: Image = await _capture()
	_check(resized.get_size() == Vector2i(480, 360), "Resize follows native viewport")
	_check(_effect._effect.size == Vector2(480, 360), "Pass fills resized viewport")
	SettingsStore.save_text(Posterization.STORE_NAME, _prior_store)
	print("Posterization pixel probe: ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


static func _difference(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))


func _check(ok: bool, reason: String) -> void:
	if not ok and not _failed:
		push_error(reason)
	if not ok:
		_failed = true
