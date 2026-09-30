extends GutTest

const MODEL := preload("res://features/slum_alley/dumpster_model.tscn")
const LOOT := preload("res://features/loot/loot_container.tscn")


func _dumpster(viewers: int) -> DumpsterVisual:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var loot := LOOT.instantiate() as LootContainer
	loot.name = "Loot"
	loot.net_active_searchers = viewers
	parent.add_child(loot)
	var model := MODEL.instantiate() as DumpsterVisual
	parent.add_child(model)
	model.set_process(false)
	return model


func test_lid_opens_eases_reverses_and_stays_open_until_last_viewer_leaves() -> void:
	var model := _dumpster(0)
	var loot := model.get_node("../Loot") as LootContainer
	var hinge := model.get_node("Hinge") as Node3D
	assert_almost_eq(hinge.rotation.x, 0.0, .001)
	loot.net_active_searchers = 2
	model._process(DumpsterVisual.OPEN_SECONDS * .5)
	assert_almost_eq(hinge.rotation_degrees.x, DumpsterVisual.OPEN_ANGLE * .5, .01)
	loot.net_active_searchers = 1
	model._process(DumpsterVisual.OPEN_SECONDS)
	assert_almost_eq(hinge.rotation_degrees.x, DumpsterVisual.OPEN_ANGLE, .01)
	loot.net_active_searchers = 0
	model._process(DumpsterVisual.CLOSE_SECONDS * .5)
	assert_almost_eq(hinge.rotation_degrees.x, DumpsterVisual.OPEN_ANGLE * .5, .01)
	loot.net_active_searchers = 1
	model._process(DumpsterVisual.OPEN_SECONDS)
	assert_almost_eq(hinge.rotation_degrees.x, DumpsterVisual.OPEN_ANGLE, .01)
	loot.net_active_searchers = 0
	model._process(DumpsterVisual.CLOSE_SECONDS)
	assert_almost_eq(hinge.rotation.x, 0.0, .001)
	var top := hinge.to_global(Vector3(0, .17, 1.43))
	assert_almost_eq(top.y, 1.6, .001, "Closed lid sits flush on the body")


func test_late_view_initial_pose_and_hollow_body_have_valid_uvs() -> void:
	var model := _dumpster(1)
	var hinge := model.get_node("Hinge") as Node3D
	assert_almost_eq(hinge.rotation_degrees.x, DumpsterVisual.OPEN_ANGLE, .01)
	assert_gt(model.get_node("Interior").mesh.get_faces().size(), 24)
	assert_almost_eq(model.mesh.get_aabb().end.y, 1.43, .001)
	for visual: MeshInstance3D in [model, model.get_node("Interior"), model.get_node("Hinge/Lid")]:
		var arrays := visual.mesh.surface_get_arrays(0)
		for uv: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
			assert_between(uv.x, 0.0, 1.0)
			assert_between(uv.y, 0.0, 1.0)
