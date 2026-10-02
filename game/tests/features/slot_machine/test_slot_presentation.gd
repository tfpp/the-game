extends GutTest

const MACHINE := preload("res://features/slot_machine/machine.tscn")
var _machine: SlotMachine
var _view: Node3D


func before_each() -> void:
	_machine = MACHINE.instantiate() as SlotMachine
	add_child_autofree(_machine)
	_machine.set_process(false)
	_view = _machine.get_node("View")
	_view.set_process(false)


func test_late_join_stopped_reels_immediately_show_authoritative_symbols() -> void:
	_machine.state = _snapshot(false, 3, [4, 2, 1])
	_view._process(0.016)
	assert_eq(_view._positions, [4.0, 2.0, 1.0])
	assert_eq(_view._status.text, "WON $30.00")
	assert_eq(_machine._last_sound_spin, 0, "A result snapshot does not replay a win event")
	assert_false((_machine.get_node("Celebration") as SlotCelebration).is_processing())


func test_stop_order_settles_correct_symbols_while_remaining_reels_keep_moving() -> void:
	_machine.state = _snapshot(true, 0, [0, 1, 2])
	_view._process(0.02)
	_machine.state = _snapshot(true, 1, [4, 1, 2])
	_view._process(0.2)
	assert_almost_eq(fposmod(_view._positions[0], 5.0), 4.0, 0.001)
	var moving: float = _view._positions[1]
	_view._process(0.02)
	assert_ne(_view._positions[1], moving)
	assert_almost_eq(fposmod(_view._positions[0], 5.0), 4.0, 0.001)
	_machine.state = _snapshot(false, 3, [4, 4, 4])
	_view._process(0.2)
	for index: int in 3:
		assert_almost_eq(fposmod(_view._positions[index], 5.0), 4.0, 0.001)
		assert_eq(_machine.state["reels"][index], 4, "Presentation never mutates results")


func test_large_prices_and_server_messages_fit_real_display_widths() -> void:
	_machine.buy_in_cents = 100000000000
	_machine.state = _snapshot(false, 3, [0, 0, 0])
	_machine.state["message"] = "Unable to complete payment. Please try again."
	_view._process(0.016)
	var caption: Label3D = _view._caption
	var status: Label3D = _view._status
	assert_string_contains(caption.text, "1,000,000,000.00")
	for label: Label3D in [caption, status]:
		var width := (
			(
				ThemeDB
				. fallback_font
				. get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
				. x
			)
			* label.pixel_size
		)
		assert_lte(width, 1.12 if label == caption else 1.05)


func test_refined_cabinet_preserves_collision_and_shared_painted_hardware() -> void:
	var hull := (_machine.get_node("Collider") as CollisionShape3D).shape as BoxShape3D
	assert_eq(hull.size, Vector3(1.38, 2.8, 1.3))
	var cabinet := _view.get_node("SlotCabinet/Model") as MeshInstance3D
	var lever := _view.get_node("Lever/Model") as MeshInstance3D
	assert_same(cabinet.material_override, lever.material_override)
	var finish := cabinet.material_override as StandardMaterial3D
	assert_eq(finish.albedo_texture.get_size(), Vector2(128, 128))
	assert_true(finish.albedo_texture.get_image().has_mipmaps())
	for model: MeshInstance3D in [cabinet, lever]:
		var mesh := model.mesh as ArrayMesh
		assert_eq(mesh.get_surface_count(), 1)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert_lte(indices.size() / 3, 1600 if model == cabinet else 200)
		for index: int in vertices.size():
			assert_true(vertices[index].is_finite())
			assert_almost_eq(normals[index].length(), 1.0, .001)
			assert_true(uvs[index].is_finite())
			assert_between(uvs[index].x, 0.0, 1.0)
			assert_between(uvs[index].y, 0.0, 1.0)
		for index: int in range(0, indices.size(), 3):
			var a := vertices[indices[index]]
			var b := vertices[indices[index + 1]]
			var c := vertices[indices[index + 2]]
			var cross := (c - a).cross(b - a)
			assert_gt(cross.length(), .000001)
			assert_gt(cross.normalized().dot(normals[indices[index]]), .99)
	# Rays along the payline must hit the backing behind the reels, never the bezel.
	var faces := cabinet.mesh.get_faces()
	for x: float in [-.36, 0.0, .36]:
		for index: int in range(0, faces.size(), 3):
			var hit: Variant = Geometry3D.segment_intersects_triangle(
				Vector3(x, 1.73, 1),
				Vector3(x, 1.73, .40),
				faces[index],
				faces[index + 1],
				faces[index + 2]
			)
			assert_null(hit, "The payline stays clear of static cabinet hardware")


func test_refined_lever_still_pulls_with_the_spin_snapshot() -> void:
	_machine.state = _snapshot(true, 0, [0, 1, 2])
	_view._process(.2)
	assert_gt((_view.get_node("Lever") as Node3D).rotation.x, .7)
	_machine.state = _snapshot(false, 3, [0, 1, 2])
	_view._process(.5)
	assert_lt((_view.get_node("Lever") as Node3D).rotation.x, .01)


func _snapshot(spinning: bool, stopped: int, reels: Array) -> Dictionary:
	return {
		"spin": 1,
		"spinning": spinning,
		"stopped": stopped,
		"reels": reels,
		"won": true,
		"payout": 3000,
		"operator": "Player",
		"message": ""
	}
