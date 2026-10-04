extends GutTest

const SIGN_SCENE := preload("res://features/signage/sign_board.tscn")
const EPSILON := 0.0005


func _make(text: String, mount: SignBoard.Mount, style := SignBoard.Style.BRASS) -> SignBoard:
	var sign := SIGN_SCENE.instantiate() as SignBoard
	sign.text = text
	sign.mount = mount
	sign.style = style
	add_child_autofree(sign)
	return sign


func _bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var local := root.global_transform.affine_inverse() * instance.global_transform
		var box := local * instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func test_atlas_stays_within_texture_limit_and_has_every_glyph() -> void:
	var image := SignLetterAtlas.image()
	assert_lte(image.get_width(), 128)
	assert_lte(image.get_height(), 128)
	var seen := {}
	for character: String in SignLetterAtlas.GLYPHS:
		var rect := SignLetterAtlas.uv_rect(character)
		assert_false(seen.has(rect.position), "glyph %s has its own tile" % character)
		seen[rect.position] = true
		assert_lte(rect.end.x, 1.0)
		assert_lte(rect.end.y, 1.0)
		var pixels := 0
		var origin := Vector2i(rect.position * SignLetterAtlas.SIZE)
		for y in SignLetterAtlas.GLYPH_H:
			for x in SignLetterAtlas.GLYPH_W:
				if image.get_pixel(origin.x + x, origin.y + y).a > 0.5:
					pixels += 1
		if character != " ":
			assert_gt(pixels, 0, "glyph %s is painted" % character)


func test_unknown_characters_fall_back_and_case_is_ignored() -> void:
	assert_eq(SignLetterAtlas.uv_rect("a"), SignLetterAtlas.uv_rect("A"))
	assert_eq(SignLetterAtlas.uv_rect("@"), SignLetterAtlas.uv_rect("?"))
	for character: String in ["%", "+"]:
		assert_ne(SignLetterAtlas.uv_rect(character), SignLetterAtlas.uv_rect("?"))
	for character: String in ["ż", "ł"]:
		assert_ne(SignLetterAtlas.uv_rect(character), SignLetterAtlas.uv_rect("?"))
		assert_eq(SignLetterAtlas.uv_rect(character), SignLetterAtlas.uv_rect(character.to_upper()))


func test_letters_mesh_has_one_quad_per_visible_character() -> void:
	var mesh := SignBoard.letters_mesh("AB C\nD", 0.14, 0.0)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 4 * 6)
	var size := SignBoard.measure("AB C\nD", 0.14, 0.0)
	for v in verts:
		assert_between(v.x, -size.x * 0.5 - EPSILON, size.x * 0.5 + EPSILON)
		assert_between(v.y, -size.y * 0.5 - EPSILON, size.y * 0.5 + EPSILON)


func test_every_mount_has_backing_frame_and_letters_without_labels() -> void:
	for mount: SignBoard.Mount in SignBoard.Mount.values():
		for style: SignBoard.Style in SignBoard.Style.values():
			var sign := _make("GOLDEN CROWN", mount, style)
			var backing := sign.find_child("Backing", true, false) as MeshInstance3D
			assert_not_null(backing, "mount %d has a backing mesh" % mount)
			assert_true(backing.mesh is BoxMesh)
			var frame := sign.find_child("Frame", true, false) as MeshInstance3D
			assert_not_null(frame)
			assert_eq(frame.mesh.get_surface_count(), 1, "The complete frame uses one surface")
			var letters := sign.find_child("Letters", true, false) as MeshInstance3D
			assert_gt(letters.mesh.get_surface_count(), 0)
			assert_eq(sign.find_children("*", "Label3D", true, false).size(), 0)
			assert_eq(
				sign.find_child("LettersBack", true, false) != null, mount != SignBoard.Mount.FLUSH
			)


func test_flush_sign_sits_on_the_wall_with_letters_in_front() -> void:
	var sign := _make("PAWN\nSHOP", SignBoard.Mount.FLUSH)
	var bounds := _bounds(sign)
	assert_almost_eq(bounds.position.z, 0.0, EPSILON, "nothing behind the wall")
	var backing := sign.find_child("Backing", true, false) as MeshInstance3D
	var back_face: float = (
		backing.position.z + backing.get_parent().position.z - SignBoard.BOARD_DEPTH / 2
	)
	assert_almost_eq(back_face, 0.0, EPSILON, "backing is flush with the wall")
	var letters := sign.find_child("Letters", true, false) as MeshInstance3D
	var letters_z: float = letters.get_aabb().position.z + letters.get_parent().position.z
	assert_gt(letters_z, SignBoard.BOARD_DEPTH, "letters are on the front face")
	var size := sign.board_size()
	assert_almost_eq(bounds.size.x, size.x + SignBoard.FRAME_WIDTH * 2, EPSILON)


func test_bracket_sign_starts_at_the_wall_and_projects_outward() -> void:
	var sign := _make("BAR", SignBoard.Mount.BRACKET)
	var bounds := _bounds(sign)
	assert_almost_eq(bounds.position.z, 0.0, EPSILON)
	var board := sign.find_child("Board", false, false) as Node3D
	assert_gt(board.position.z - sign.board_size().x * 0.5, 0.0, "board clears the wall")
	assert_lte(bounds.end.y, EPSILON, "hangs below the arm")


func test_hanging_sign_hangs_from_the_ceiling_point() -> void:
	var sign := _make("ELEVATOR", SignBoard.Mount.HANGING)
	var bounds := _bounds(sign)
	assert_almost_eq(bounds.end.y, 0.0, EPSILON, "rods reach the ceiling")
	var board := sign.find_child("Board", false, false) as Node3D
	assert_lt(board.position.y + sign.board_size().y * 0.5, -0.1)


func test_changing_text_rebuilds_without_leftover_parts() -> void:
	var sign := _make("A", SignBoard.Mount.HANGING)
	sign.text = "LONGER TEXT"
	await wait_physics_frames(1)
	assert_eq(sign.find_children("Backing", "", true, false).size(), 1)
	var backing := sign.find_child("Backing", true, false) as MeshInstance3D
	assert_almost_eq((backing.mesh as BoxMesh).size.x, sign.board_size().x, EPSILON)
	assert_eq(sign.find_children("Rod*", "", true, false).size(), 2)
