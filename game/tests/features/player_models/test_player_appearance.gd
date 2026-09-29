extends GutTest

const FEATURE := preload("res://features/player_models/feature.tscn")

var _models: PlayerModels


func before_each() -> void:
	_models = FEATURE.instantiate() as PlayerModels
	add_child_autofree(_models)


func test_appearance_rejects_unbounded_and_malformed_payloads() -> void:
	var data := PlayerAppearance.defaults()
	assert_true(PlayerAppearance.valid(data))
	for key: String in ["skin", "hair_color", "eyes"]:
		var bad := data.duplicate()
		bad[key] = 999999
		assert_false(PlayerAppearance.valid(bad))
		bad[key] = 0.5
		assert_false(PlayerAppearance.valid(bad))
		bad[key] = "0"
		assert_false(PlayerAppearance.valid(bad))
	data["peer_id"] = 7
	assert_false(PlayerAppearance.valid(data), "Identity cannot be supplied by payload")


func test_server_applies_only_to_transport_peer_and_copies_state() -> void:
	var data := {"skin": 7, "hair": "long", "hair_color": 2, "eyes": 1}
	assert_eq(_models.entity._evaluate(7, &"appearance", data), NetworkedEntity.Result.ACCEPTED)
	data["skin"] = 0
	assert_eq(_models.skin_for(7, 1), 7)
	assert_eq(_models.skin_for(9, 1), 1)
	assert_eq(_models.appearance_for(7)["hair"], "long")
	assert_eq(
		_models.entity._evaluate(7, &"appearance", {"skin": 0}), NetworkedEntity.Result.DENIED
	)
	assert_eq(_models.skin_for(7, 1), 7, "Invalid requests leave accepted state intact")


func test_disconnect_and_session_reset_clear_every_axis() -> void:
	_models.entity._evaluate(7, &"appearance", PlayerAppearance.defaults())
	_models.entity._evaluate(7, &"body", {"value": "girl"})
	_models.entity._evaluate(7, &"head", {"value": "frog"})
	_models.entity._evaluate(7, &"tail", {"value": "fin"})
	_models._remove_peer(7)
	assert_true(_models.appearances.is_empty())
	assert_true(_models.body_types.is_empty())
	assert_true(_models.head_types.is_empty())
	assert_true(_models.tail_types.is_empty())
	_models.entity._evaluate(1, &"appearance", PlayerAppearance.defaults())
	_models._reset_session(Network.Mode.OFFLINE)
	assert_true(_models.appearances.is_empty())


func test_replication_includes_appearance_for_late_joiners() -> void:
	var sync := _models.entity.get_node("Sync") as MultiplayerSynchronizer
	var path := NodePath(".:appearances")
	assert_true(sync.replication_config.has_property(path))
	assert_true(sync.replication_config.property_get_spawn(path))
	assert_eq(sync.get_multiplayer_authority(), 1)


func test_human_detail_changes_preserve_clothes_and_articulated_pose() -> void:
	var model := BlockPlayerModel.new()
	add_child_autofree(model)
	model.set_clothing("shirt:4", "pants:3")
	model.animate(0.3, Vector3(0, 0, -6), true, 8)
	var knee := model.get_node("Rig/LeftLeg/Shin") as Node3D
	var before := knee.rotation.x
	model.set_appearance({"skin": 6, "hair": "bald", "hair_color": 4, "eyes": 2})
	assert_false(bool(model.human.material.get_shader_parameter("hair_enabled")))
	assert_eq(model.skin_color, PlayerSkin.TONES[6])
	assert_eq(model.shirt_color, ClothingCatalog.COLORS[4])
	assert_eq(knee.rotation.x, before, "Cosmetic rebuilding preserves joint pivots")
	assert_true(model.human.surface.mesh is ArrayMesh)
	model.set_body_type("penguin")
	model.set_body_type("default")
	assert_false(bool(model.human.material.get_shader_parameter("hair_enabled")))
	assert_eq(model.eye_color_index, 2)


func test_picker_saves_accepted_appearance_and_loads_it_again() -> void:
	var original := SettingsStore.load_text("character")
	var picker := _models.get_node("ModelPicker")
	picker._saved = {}
	picker._select(4, "skin", [] as Array[String])
	picker._select(2, "hair", PlayerAppearance.HAIR_STYLES)
	var saved := SettingsStore.load_data("character")
	assert_eq(saved["skin"], 3)
	assert_eq(saved["hair"], "swept")
	var fresh := FEATURE.instantiate() as PlayerModels
	add_child_autofree(fresh)
	assert_eq(fresh.get_node("ModelPicker")._saved, saved)
	SettingsStore.save_text("character", original)


func test_picker_registers_a_character_settings_page_with_every_option() -> void:
	var picker := _models.get_node("ModelPicker")
	assert_true(picker.is_in_group(&"settings_pages"))
	var page: Control = picker.settings_page_build()
	add_child_autofree(page)
	assert_eq(picker._choices.size(), 8)
	var skin := picker._choices["skin"] as OptionButton
	assert_eq(skin.item_count, PlayerSkin.TONES.size() + 1)
	assert_eq(picker._preview.mouse_filter, Control.MOUSE_FILTER_STOP)
	picker._refresh()
	var previous: float = picker._preview.model.rotation.y
	var drag := InputEventScreenDrag.new()
	drag.relative.x = 15
	picker._turn_preview(drag)
	assert_gt(picker._preview.model.rotation.y, previous)


func test_human_is_one_skinned_surface_with_vertex_blend_shapes() -> void:
	var model := BlockPlayerModel.new()
	add_child_autofree(model)
	var human := model.human
	assert_eq(human.find_children("*", "MeshInstance3D", true, false).size(), 1)
	assert_eq(human.surface.mesh.get_surface_count(), 1)
	assert_not_null(human.surface.skin)
	assert_eq(human.skeleton.get_bone_count(), 45)
	assert_eq(human.surface.mesh.get_blend_shape_count(), 5)
	var arrays := human.surface.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq((arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size(), vertices.size())
	var rest_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	for index: int in vertices.size():
		assert_almost_eq(rest_uv[index].x, vertices[index].x, 0.001)
		assert_almost_eq(1.0 - rest_uv[index].y, vertices[index].y, 0.001)
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	assert_eq(weights.size(), vertices.size() * 4)
	for index: int in vertices.size():
		var total := 0.0
		for influence: int in 4:
			var weight := weights[index * 4 + influence]
			assert_true(weight >= 0.0 and weight <= 1.0)
			total += weight
		assert_almost_eq(total, 1.0, 0.001, "Every vertex has normalized skin weights")


func test_imported_human_topology_is_one_connected_component() -> void:
	var model := BlockPlayerModel.new()
	add_child_autofree(model)
	var arrays := model.human.surface.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# UV/palette seams duplicate exported vertices. Weld coincident rest positions
	# for this connectivity check, without changing the rendering mesh.
	var positions: Dictionary = {}
	var welded: Array[int] = []
	var graph: Array[Array] = []
	var signed_volume := 0.0
	for vertex: Vector3 in vertices:
		var key := Vector3i(
			roundi(vertex.x * 100000), roundi(vertex.y * 100000), roundi(vertex.z * 100000)
		)
		if not positions.has(key):
			positions[key] = positions.size()
			graph.append([])
		welded.append(int(positions[key]))
	for index: int in range(0, indices.size(), 3):
		var va := vertices[indices[index]]
		var vb := vertices[indices[index + 1]]
		var vc := vertices[indices[index + 2]]
		signed_volume += va.dot(vb.cross(vc)) / 6.0
		var a := welded[indices[index]]
		var b := welded[indices[index + 1]]
		var c := welded[indices[index + 2]]
		graph[a].append_array([b, c])
		graph[b].append_array([a, c])
		graph[c].append_array([a, b])
	var seen := {}
	var pending: Array[int] = [0]
	while not pending.is_empty():
		var next: int = pending.pop_back()
		if seen.has(next):
			continue
		seen[next] = true
		for neighbor: int in graph[next]:
			pending.append(neighbor)
	assert_eq(seen.size(), graph.size(), "All body vertices belong to one connected surface")
	assert_lt(signed_volume, -0.01, "Godot's clockwise triangles face outwards")


func test_outfit_and_build_deform_the_same_mesh_without_inventory_mutations() -> void:
	var model := BlockPlayerModel.new()
	add_child_autofree(model)
	var mesh := model.human.surface.mesh
	model.set_clothing("shirt:4", "pants:3")
	model.set_appearance(
		{"skin": 6, "hair": "long", "hair_color": 3, "eyes": 2, "outfit": "tactical"}
	)
	assert_eq(model.human.surface.mesh, mesh)
	assert_eq(model.human.shape_weight("Tactical"), 1.0)
	assert_eq(model.human.shape_weight("LongHair"), 1.0)
	assert_eq(model.shirt_color, ClothingCatalog.COLORS[4])
	assert_eq(model.pants_color, ClothingCatalog.COLORS[3])
	assert_eq(model.skin_color, PlayerSkin.TONES[6])
	model.set_body_type("girl")
	assert_eq(model.human.shape_weight("Feminine"), 1.0)
	assert_eq(model.human.surface.mesh, mesh)
	model.set_appearance(
		{"skin": 6, "hair": "long", "hair_color": 3, "eyes": 2, "outfit": "casual"}
	)
	assert_eq(model.human.shape_weight("Tactical"), 0.0)
	assert_eq(model.shirt_id, "shirt:4")
	assert_eq(model.pants_id, "pants:3")


func test_bone_pose_retains_downward_leg_rest_and_hides_held_arm_vertices() -> void:
	var model := BlockPlayerModel.new()
	add_child_autofree(model)
	model.animate(0.1, Vector3.ZERO, true, 8.0, 0.0, true, false)
	var skeleton := model.human.skeleton
	var thigh := skeleton.find_bone("ThighR")
	var rest := skeleton.get_bone_rest(thigh).basis.get_rotation_quaternion()
	assert_almost_eq(absf(skeleton.get_bone_pose_rotation(thigh).dot(rest)), 1.0, 0.001)
	assert_true(bool(model.human.material.get_shader_parameter("hide_right_arm")))
	assert_false(bool(model.human.material.get_shader_parameter("hide_left_arm")))
	model.animate(0.15, Vector3(0, 0, -6), true, 8)
	assert_lt(absf(skeleton.get_bone_pose_rotation(thigh).dot(rest)), 0.999)


func test_legacy_saved_appearance_stays_valid_and_invalid_outfits_are_rejected() -> void:
	assert_true(PlayerAppearance.valid({"skin": 3, "hair": "long", "hair_color": 1, "eyes": 2}))
	var data := PlayerAppearance.defaults()
	data["outfit"] = "unknown"
	assert_false(PlayerAppearance.valid(data))


func test_item_grip_bends_the_single_mesh_arm_to_the_target() -> void:
	var model := BlockPlayerModel.new()
	add_child_autofree(model)
	model.animate(0.1, Vector3.ZERO, true, 8.0, 0.0, true, true)
	var skeleton := model.human.skeleton
	for right: bool in [false, true]:
		var target := Vector3(0.15 if right else -0.15, 0.1, -0.35)
		model.human.reach_grip(right, skeleton.to_global(target))
		var wrist := skeleton.find_bone("HandR" if right else "HandL")
		assert_almost_eq(skeleton.get_bone_global_pose(wrist).origin, target, Vector3.ONE * 0.002)
		assert_false(
			bool(
				model.human.material.get_shader_parameter(
					"hide_right_arm" if right else "hide_left_arm"
				)
			)
		)


func test_every_finger_joint_has_weighted_vertices_and_preserves_its_parent_chain() -> void:
	var model := BlockPlayerModel.new()
	add_child_autofree(model)
	var skeleton := model.human.skeleton
	var skin := model.human.surface.skin
	var arrays := model.human.surface.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for suffix: String in ["L", "R"]:
		for digit: String in SkinnedHuman.DIGITS:
			for segment: int in 3:
				var name := digit + str(segment + 1) + suffix
				var index := skeleton.find_bone(name)
				assert_gte(index, 0)
				var parent := "Hand" + suffix if segment == 0 else digit + str(segment) + suffix
				assert_eq(skeleton.get_bone_name(skeleton.get_bone_parent(index)), parent)
				var influenced := 0
				for offset: int in bones.size():
					if (
						weights[offset] > 0.01
						and (
							skin.get_bind_bone(bones[offset]) == index
							or str(skin.get_bind_name(bones[offset])) == name
						)
					):
						influenced += 1
				assert_gt(influenced, 0, name + " must deform its own finger vertices")


func test_fingers_curl_and_return_to_rest_without_moving_the_other_hand() -> void:
	var model := BlockPlayerModel.new()
	add_child_autofree(model)
	var skeleton := model.human.skeleton
	model.human.set_finger_curl(false, 0)
	model.human.set_finger_curl(true, 0)
	var left := skeleton.find_bone("Middle3L")
	var right := skeleton.find_bone("Middle3R")
	var open := skeleton.get_bone_global_pose(right).origin
	var left_open := skeleton.get_bone_global_pose(left)
	model.human.set_finger_curl(true, 1)
	assert_gt(skeleton.get_bone_global_pose(right).origin.distance_to(open), 0.015)
	assert_eq(skeleton.get_bone_global_pose(left), left_open)
	model.human.set_finger_curl(true, 0)
	assert_almost_eq(skeleton.get_bone_global_pose(right).origin, open, Vector3.ONE * 0.001)
	model.human.reach_grip(true, model.to_global(Vector3(0.15, 0.1, -0.35)))
	var proximal := skeleton.find_bone("Index1R")
	var rest := skeleton.get_bone_rest(proximal).basis.get_rotation_quaternion()
	assert_lt(absf(skeleton.get_bone_pose_rotation(proximal).dot(rest)), 0.99)
	model.animate(0.1, Vector3.ZERO, true, 8)
	assert_almost_eq(
		absf(skeleton.get_bone_pose_rotation(proximal).dot(rest)), cos(0.12 * 0.75 * 0.5), 0.0001
	)
