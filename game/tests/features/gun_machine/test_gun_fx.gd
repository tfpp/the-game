extends GutTest
## Buying and firing must reuse cached materials and never add lights (issue #241).


func test_materials_are_shared_per_color() -> void:
	var red := GunFx.material(Color.RED)
	assert_same(GunFx.material(Color.RED), red)
	assert_ne(GunFx.material(Color.RED, true), red)
	assert_true(GunFx.material(Color.RED, true).emission_enabled)


func test_same_stats_build_views_with_the_same_materials() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stats := GunGenerator.generate(rng)
	var first := GunView.build(stats)
	var second := GunView.build(stats)
	for index: int in first.get_child_count():
		var mesh := first.get_child(index) as MeshInstance3D
		if mesh != null:
			var other := second.get_child(index) as MeshInstance3D
			assert_same(other.material_override, mesh.material_override)
	first.free()
	second.free()


func test_flash_is_an_unshaded_mesh_not_a_light() -> void:
	var flash := GunFx.flash(Color.ORANGE, 0.3)
	assert_eq(flash.material_override.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_almost_eq(flash.scale.x * GunFx.FLASH_MESH_RADIUS * 2.0, 0.3, 0.001)
	assert_same(flash.mesh, GunFx.flash_mesh())
	flash.free()


func test_explosion_adds_no_lights() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	GunExplosionEffect.spawn(parent, Vector3.ZERO, 3.0)
	var effect := parent.get_child(parent.get_child_count() - 1)
	assert_eq(effect.find_children("*", "Light3D", true, false).size(), 0)
	assert_gt(effect.find_children("*", "MeshInstance3D", true, false).size(), 0)


func test_warm_up_draws_each_variant_then_cleans_up() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	GunFx.warm_up(camera)
	var holder := camera.get_node("GunFxWarmUp")
	assert_eq(holder.get_child_count(), GunFx.warm_up_materials().size())
	await wait_process_frames(5)
	assert_false(is_instance_valid(holder) and holder.is_inside_tree())
