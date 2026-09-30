extends GutTest


func test_auto_framing_covers_nested_rotated_models_of_different_scales() -> void:
	for id: String in ["scrap", "stolen_wallet", "pistol", "shirt:2"]:
		var model := ItemCatalog.create_view(id)
		model.position = Vector3(4, 3, -2)
		model.rotation.y = .45
		model.scale = Vector3.ONE * 1.3
		add_child_autofree(model)
		var camera := Camera3D.new()
		add_child_autofree(camera)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		var bounds := ModelIconRenderer.model_bounds(model)
		assert_gt(bounds.size.length(), 0.01)
		ModelIconRenderer.frame_bounds(camera, bounds, Vector3(1, 1.7, 1))
		for corner: int in 8:
			var point := Vector3(
				bounds.end.x if corner & 1 else bounds.position.x,
				bounds.end.y if corner & 2 else bounds.position.y,
				bounds.end.z if corner & 4 else bounds.position.z
			)
			var local := camera.global_transform.affine_inverse() * point
			assert_lt(absf(local.x), camera.size * .5, id + " fits horizontally")
			assert_lt(absf(local.y), camera.size * .5, id + " fits vertically")
			assert_lt(local.z, -camera.near, id + " is in front of camera")


func test_renderer_is_shared_even_before_deferred_viewport_attachment() -> void:
	var control := Control.new()
	add_child_autofree(control)
	var first := ModelIconRenderer.for_control(control)
	var second := ModelIconRenderer.for_control(control)
	assert_same(first, second)
	await get_tree().process_frame
	assert_true(first.is_inside_tree())
	assert_null(first.request_item("not-an-item"))
	if DisplayServer.get_name() == "headless":
		assert_null(first.request_item("scrap"))
		assert_null(first._viewport, "Server/headless checks allocate no rendering viewport")
		assert_true(first._jobs.is_empty())
	first.queue_free()
	await get_tree().process_frame
	assert_false(get_viewport().has_meta("inventory_model_icons"))
