extends GutTest

const FELT := preload("res://features/casino_hub/textures/felt_albedo.png")
const WORLD_TEXTURES: Array[Texture2D] = [
	preload("res://features/casino_hub/textures/surface_atlas.png"),
	preload("res://features/casino_hub/textures/prop_grain.png"),
	preload("res://features/casino_hub/textures/ceiling_albedo.png"),
	FELT,
	preload("res://features/casino_hub/textures/landscape_painting.png"),
	preload("res://features/casino_hub/textures/carpet_albedo.png"),
	preload("res://features/casino_hub/textures/wallpaper_albedo.png"),
	preload("res://features/casino_hub/textures/walnut_albedo.png"),
	preload("res://features/slot_machine/textures/reel_symbols.png"),
	preload("res://assets/kenney/prototype-textures/PNG/Dark/texture_01.png"),
	preload("res://assets/kenney/prototype-textures/PNG/Dark/texture_08.png"),
	preload("res://assets/kenney/prototype-textures/PNG/Orange/texture_09.png"),
	preload("res://assets/kenney/skyboxes/skybox-day.png"),
	preload("res://assets/kenney/skyboxes/skybox-night.png"),
]


func test_imported_world_textures_fit_budget_and_keep_mipmaps() -> void:
	for texture: Texture2D in WORLD_TEXTURES:
		assert_lte(texture.get_width(), 128, texture.resource_path)
		assert_lte(texture.get_height(), 128, texture.resource_path)
		assert_true(texture.get_image().has_mipmaps(), texture.resource_path)


func test_mobile_render_budget_handles_portrait_landscape_and_retina() -> void:
	for size: Vector2 in [Vector2(844, 390), Vector2(390, 844), Vector2(2532, 1170)]:
		var scale := RetroStyle.mobile_scale(size)
		assert_lte(size.y * scale, 540.0)
		assert_lte(scale, 0.85)
		assert_gt(scale, 0.1)


func test_streamed_mesh_gets_cheap_shading_without_touching_custom_screen_shader() -> void:
	var style := RetroStyle.new()
	var prop := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	var finish := StandardMaterial3D.new()
	finish.metallic = 0.9
	finish.normal_enabled = true
	mesh.material = finish
	prop.mesh = mesh
	style.style_node(prop)
	assert_eq(finish.shading_mode, BaseMaterial3D.SHADING_MODE_PER_VERTEX)
	assert_eq(finish.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
	assert_same(finish.albedo_texture, RetroStyle.PROP_GRAIN)
	assert_false(finish.normal_enabled)
	assert_eq(finish.metallic, 0.0)
	assert_lte(mesh.radial_segments, 12)
	assert_lte(mesh.rings, 6)
	var screen := ShaderMaterial.new()
	screen.shader = load("res://features/slot_machine/reel.gdshader")
	prop.material_override = screen
	style.style_node(prop)
	assert_same(prop.material_override, screen)
	prop.free()
	style.free()


func test_mobile_disables_shadow_maps_and_post_effects() -> void:
	var style := RetroStyle.new()
	style.mobile = true
	var light := OmniLight3D.new()
	light.shadow_enabled = true
	style.style_node(light)
	assert_false(light.shadow_enabled)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.glow_enabled = true
	style.style_node(world)
	assert_false(world.environment.glow_enabled)
	light.free()
	world.free()
	style.free()


func test_baked_decor_preserves_architecture_collision() -> void:
	var source := preload("res://features/casino_hub/tools/interior_source.tscn").instantiate()
	var baked := preload("res://features/casino_hub/interior.tscn").instantiate()
	var colliders := 0
	for node: Node in source.get_children():
		if node is CSGShape3D and node.use_collision:
			colliders += 1
			var counterpart := baked.get_node_or_null(NodePath(str(node.name))) as CSGShape3D
			assert_not_null(counterpart, str(node.name))
			if counterpart != null:
				assert_true(counterpart.use_collision)
				assert_eq(counterpart.transform, node.transform)
	assert_gt(colliders, 50)
	assert_lt(baked.get_child_count(), source.get_child_count() - 100)
	assert_lt(baked.get_node("DecorBatches").get_child_count(), 70)
	source.free()
	baked.free()


func test_mobile_light_budget_covers_streaming_and_unloading() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	var style := RetroStyle.new()
	viewport.add_child(style)
	style.mobile = true
	var lights: Array[OmniLight3D] = []
	for index: int in 7:
		var light := OmniLight3D.new()
		light.position.x = index + 1.0
		viewport.add_child(light)
		style.style_node(light)
		lights.append(light)
	style._update_light_budget()
	var visible_count := 0
	for light: OmniLight3D in lights:
		visible_count += int(light.light_cull_mask != 0)
	assert_eq(visible_count, RetroStyle.MOBILE_LOCAL_LIGHTS)
	assert_ne(lights[0].light_cull_mask, 0)
	assert_eq(lights[6].light_cull_mask, 0)
	var dead := OmniLight3D.new()
	dead.visible = false
	viewport.add_child(dead)
	style.style_node(dead)
	style._update_light_budget()
	assert_false(dead.visible, "Budget must not revive a dead fixture")
	assert_eq(dead.light_cull_mask, 0)
	dead.free()
	lights[0].free()
	style._update_light_budget()
	assert_eq(style._lights.size(), 6, "Unloaded room lights leave the budget")
	assert_ne(lights[4].light_cull_mask, 0, "Next nearest light replaces an unloaded light")


func test_room_unloading_before_style_batch_is_safe() -> void:
	var style := RetroStyle.new()
	var prop := MeshInstance3D.new()
	style._queue_node(prop)
	prop.free()
	style._process(0.0)
	assert_true(style._pending.is_empty())
	assert_false(style.is_processing())
	style.free()


func test_casino_models_stay_within_geometry_and_material_budgets() -> void:
	var models: Array[PackedScene] = [
		preload("res://features/casino_hub/models/slot_cabinet.tscn"),
		preload("res://features/casino_hub/models/casino_stool.tscn"),
		preload("res://features/casino_hub/models/lounge_bench.tscn"),
		preload("res://features/casino_hub/models/ceramic_planter.tscn"),
		preload("res://features/casino_hub/models/brass_chandelier.tscn"),
		preload("res://features/casino_hub/models/salon_card_table.glb"),
		preload("res://features/casino_hub/models/salon_dealer.glb"),
		preload("res://features/casino_hub/models/salon_guest.glb"),
		preload("res://features/casino_hub/models/salon_seated.glb"),
		preload("res://features/casino_hub/models/salon_lady.glb"),
		preload("res://features/casino_hub/models/salon_bar.glb"),
		preload("res://features/casino_hub/models/salon_architecture.glb"),
		preload("res://features/casino_hub/models/salon_sconce.glb"),
	]
	for scene: PackedScene in models:
		var instance := scene.instantiate()
		var triangles := 0
		var surfaces := 0
		for node: Node in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = node.mesh
			surfaces += mesh.get_surface_count()
			for surface: int in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				triangles += int(
					(indices.size() if not indices.is_empty() else vertices.size()) / 3.0
				)
				if node.name == &"Palette":
					var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
					var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					assert_eq(uvs.size(), vertices.size(), "Every palette vertex has texture UVs")
					assert_eq(
						colors.size(), vertices.size(), "Palette tints are baked into vertices"
					)
		var surface_budget := 3 if "card_table" in scene.resource_path else 2
		var triangle_budget := 2000
		if "card_table" in scene.resource_path:
			triangle_budget = 6500
		elif "salon_bar" in scene.resource_path:
			triangle_budget = 5500
		elif "salon_architecture" in scene.resource_path:
			triangle_budget = 4000
		elif "salon_" in scene.resource_path:
			triangle_budget = 1400
		assert_lte(surfaces, surface_budget, scene.resource_path)
		assert_lte(triangles, triangle_budget, scene.resource_path)
		assert_gt(triangles, 0, scene.resource_path)
		instance.free()


func test_touch_targets_fit_portrait_and_landscape_without_overlapping() -> void:
	var controls := preload("res://features/touch_controls/touch_controls.gd").new()
	for bounds: Vector2 in [Vector2(480, 1039), Vector2(1168, 540)]:
		controls.size = bounds
		controls._resize_layout()
		assert_gt(controls.use_center().x - 54.0, 132.0 + 76.0, "Use clears joystick")
		assert_gt(controls.jump_center().x - 62.0, controls.use_center().x + 54.0)
		assert_lt(controls.jump_center().x + 62.0, controls.ui_size.x)
		assert_lt(controls.jump_center().y + 62.0, controls.ui_size.y - 70.0, "Clear wallet HUD")
		assert_true(Rect2(Vector2.ZERO, controls.ui_size).encloses(controls.pause_button()))
	controls.free()


func test_authored_textures_keep_their_uv_mapping() -> void:
	var style := RetroStyle.new()
	var finish := StandardMaterial3D.new()
	finish.albedo_texture = FELT
	finish.uv1_scale = Vector3(3, 4, 1)
	style._style_material(finish)
	assert_same(finish.albedo_texture, FELT)
	assert_eq(finish.uv1_scale, Vector3(3, 4, 1))
	assert_false(finish.uv1_triplanar)
	style.free()
