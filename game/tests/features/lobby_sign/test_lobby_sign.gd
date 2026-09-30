extends GutTest
## The south lobby's Mandarin hello sign: mounting, clearance and baked artwork.

const ROOM := preload("res://world/room.tscn")
const SIGN := preload("res://features/lobby_sign/feature.tscn")
const PAINT := preload("res://features/lobby_sign/tools/build_texture.gd")
const TEXTURE := preload("res://assets/lobby_sign/textures/hello_albedo.png")
const WOOD := preload("res://features/casino_hub/materials/wood.tres")
const FACE := preload("res://features/lobby_sign/materials/face.tres")

const GOLD_THRESHOLD := 0.55

var _room: Node3D
var _sign: Node3D


func before_each() -> void:
	_room = ROOM.instantiate() as Node3D
	add_child_autofree(_room)
	_sign = SIGN.instantiate() as Node3D
	_room.add_child(_sign)
	await wait_physics_frames(3)


func test_sign_mounts_flush_on_the_south_lobby_wall_facing_readers() -> void:
	var sign := _node("Sign")
	assert_almost_eq(sign.global_position.x, 10.0, 0.001)
	assert_almost_eq(sign.global_position.y, 2.25, 0.001)
	assert_almost_eq(sign.global_position.z, 34.0, 0.001)
	var normal := sign.global_basis.z
	assert_almost_eq(normal.x, 0.0, 0.001)
	assert_almost_eq(normal.z, -1.0, 0.001, "Readers stand north of the sign, in the lobby")
	var wall := _ray(sign.global_position + normal * 0.2, sign.global_position - normal * 0.2)
	assert_false(wall.is_empty(), "The sign must mount on the real south wall")
	if not wall.is_empty():
		assert_almost_eq((wall["position"] as Vector3).distance_to(sign.global_position), 0.0, 0.01)
		assert_gt((wall["normal"] as Vector3).dot(normal), 0.99, "The plaque faces into the room")


func test_reading_spot_has_clear_sight_floor_and_standing_room() -> void:
	var sign := _node("Sign")
	var normal := sign.global_basis.z
	var face := sign.global_position
	var approach := face + normal * 1.5
	assert_true(
		_ray(approach, face + normal * 0.06).is_empty(),
		"Nothing may block the view of the characters"
	)
	var floor_hit := _ray(approach, approach - Vector3(0, 3, 0))
	assert_false(floor_hit.is_empty(), "The reading position needs a floor")
	if not floor_hit.is_empty():
		assert_almost_eq((floor_hit["position"] as Vector3).y, 0.0, 0.03, "Lobby promenade floor")
	var capsule := PhysicsShapeQueryParameters3D.new()
	capsule.shape = CapsuleShape3D.new()
	(capsule.shape as CapsuleShape3D).radius = 0.4064
	(capsule.shape as CapsuleShape3D).height = 1.8288
	capsule.transform.origin = Vector3(approach.x, 0.94, approach.z)
	assert_true(
		_space().intersect_shape(capsule).is_empty(), "A standing player fits in front of the sign"
	)


func test_south_exit_and_wall_depth_stay_clear() -> void:
	# The corridor mouth (x -2.5..2.5 at z 34.5) must remain walkable, and the
	# plaque may not protrude into the lobby further than wall decor.
	assert_true(
		_ray(Vector3(0, 1, 30), Vector3(0, 1, 44)).is_empty(),
		"The south exit corridor must stay open"
	)
	var sign := _node("Sign")
	var plaque := _node("Sign/Plaque") as MeshInstance3D
	var box := plaque.mesh as BoxMesh
	assert_gt(sign.global_position.x - box.size.x * 0.5, 2.5, "Clear of the exit gap")
	var front := plaque.to_global(Vector3(0, 0, box.size.z * 0.5))
	var back := plaque.to_global(Vector3(0, 0, -box.size.z * 0.5))
	assert_almost_eq(34.0 - back.z, 0.005, 0.01, "Backing sits 5mm proud of the wall")
	assert_lt(34.0 - front.z, 0.16, "The plaque only protrudes wall-decor depth")


func test_scene_is_static_scenery_identical_on_every_peer() -> void:
	for node: Node in [
		_sign, _node("Sign"), _node("Sign/Plaque"), _node("Sign/Face"), _node("Sign/Caption")
	]:
		assert_null(node.get_script(), "No runtime scripts: the scene is immutable scenery")
		assert_false(node is Light3D or node is CollisionObject3D or node is CSGShape3D)
	for node: GeometryInstance3D in [
		_node("Sign/Plaque") as GeometryInstance3D,
		_node("Sign/Face") as GeometryInstance3D,
		_node("Sign/Caption") as GeometryInstance3D,
	]:
		assert_eq(node.visibility_range_end, 50.0, node.name)
		assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, node.name)
	var plaque := _node("Sign/Plaque") as MeshInstance3D
	assert_same(plaque.get_surface_override_material(0), WOOD, "Shared walnut backing")
	var face := _node("Sign/Face") as MeshInstance3D
	assert_same(face.get_surface_override_material(0), FACE, "Own painted face")
	var second := SIGN.instantiate() as Node3D
	add_child_autofree(second)
	assert_eq(_node("Sign").transform, (second.get_node("Sign") as Node3D).transform)
	assert_eq(
		(_node("Sign/Caption") as Label3D).text, (second.get_node("Sign/Caption") as Label3D).text
	)


func test_face_material_is_unshaded_nearest_and_bounded() -> void:
	assert_eq(FACE.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED, "Readable at night")
	assert_eq(FACE.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
	assert_false(FACE.texture_repeat)
	assert_same(FACE.albedo_texture, TEXTURE)


func test_caption_fits_the_plaque_in_the_lobbys_label_style() -> void:
	var caption := _node("Sign/Caption") as Label3D
	assert_eq(caption.text, "HELLO · NI HAO")
	assert_eq(caption.modulate, Color(0.92, 0.69, 0.36, 1))
	assert_eq(caption.outline_modulate, Color(0.1, 0.04, 0.025, 1))
	assert_false(caption.shaded, "Unshaded like the other lobby labels")
	assert_false(caption.double_sided)
	assert_lt(caption.position.y, -1.05, "Below the textured face, on the walnut strip")
	assert_gt(caption.position.y, -1.45)
	var width := (
		(
			ThemeDB
			. fallback_font
			. get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.font_size)
			. x
		)
		* caption.pixel_size
	)
	assert_lt(width, 1.2, "Caption stays inside the 1.36 m plaque")


func test_baked_texture_matches_the_unifont_reference() -> void:
	var image := TEXTURE.get_image()
	assert_eq(image.get_width(), 64)
	assert_eq(image.get_height(), 128)
	assert_true(image.has_mipmaps(), "Mipmaps keep the banner readable at distance")
	var painted := PAINT.paint()
	var mismatched := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var baked := image.get_pixel(x, y)
			var fresh := painted.get_pixel(x, y)
			if (
				absf(baked.r - fresh.r) > 0.02
				or absf(baked.g - fresh.g) > 0.02
				or absf(baked.b - fresh.b) > 0.02
			):
				mismatched += 1
	assert_eq(mismatched, 0, "The shipped PNG is exactly the tool's deterministic bake")
	for codepoint: int in PAINT.CELLS:
		var cell: Vector2i = PAINT.CELLS[codepoint]
		var on_pixels := 0
		for row: int in PAINT.glyph_rows(codepoint):
			on_pixels += _on_bits(row)
		var gold := 0
		for y: int in range(cell.y, cell.y + 16 * PAINT.GLYPH_SCALE):
			for x: int in range(cell.x, cell.x + 16 * PAINT.GLYPH_SCALE):
				if image.get_pixel(x, y).r > GOLD_THRESHOLD:
					gold += 1
		assert_eq(
			gold, on_pixels * PAINT.GLYPH_SCALE * PAINT.GLYPH_SCALE, "Glyph cells are 3x Unifont"
		)
	var frame := 0
	var outside_gold := 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			if _in_cell(x, y):
				continue
			if image.get_pixel(x, y).r > GOLD_THRESHOLD:
				outside_gold += 1
			if _is_frame(x, y):
				frame += 1
	assert_eq(outside_gold, frame, "Only the inset frame is gold outside the characters")
	for corner: Vector2i in [Vector2i(0, 0), Vector2i(63, 0), Vector2i(0, 127), Vector2i(63, 127)]:
		var colour := image.get_pixel(corner.x, corner.y)
		assert_gt(colour.r, colour.b, "Warm burgundy background")
		assert_gt(colour.b, colour.g)
		assert_lt(colour.r, 0.45)


func _node(path: String) -> Node3D:
	var node := _sign.get_node(path) as Node3D
	assert_not_null(node, path)
	return node


func _space() -> PhysicsDirectSpaceState3D:
	return _room.get_world_3d().direct_space_state


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _space().intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


func _on_bits(value: int) -> int:
	var count := 0
	while value > 0:
		count += value & 1
		value >>= 1
	return count


func _in_cell(x: int, y: int) -> bool:
	for codepoint: int in PAINT.CELLS:
		var cell: Vector2i = PAINT.CELLS[codepoint]
		var span := 16 * PAINT.GLYPH_SCALE
		if x >= cell.x and y >= cell.y and x < cell.x + span and y < cell.y + span:
			return true
	return false


func _is_frame(x: int, y: int) -> bool:
	if not (2 <= x and x <= 61 and 2 <= y and y <= 125):
		return false
	return x == 2 or x == 61 or y == 2 or y == 125
