extends GutTest

const Pointer := preload("res://features/scumm_arcade/screen_pointer.gd")


func test_center_and_corners_map_to_game_pixels() -> void:
	assert_eq(
		Pointer.project(Transform3D.IDENTITY, Vector3(0, 0, 2), Vector3.FORWARD), Vector2i(160, 100)
	)
	assert_eq(
		Pointer.project(Transform3D.IDENTITY, Vector3(-0.59, 0.4425, 2), Vector3.FORWARD),
		Vector2i(0, 0)
	)
	assert_eq(
		Pointer.project(Transform3D.IDENTITY, Vector3(0.59, -0.4425, 2), Vector3.FORWARD),
		Vector2i(319, 199)
	)


func test_tilted_rotated_translated_screen_maps_same_pixels() -> void:
	var screen := Transform3D(Basis.from_euler(Vector3(-0.28, 0.8, 0)), Vector3(-13, 0.274, 8.993))
	var origin := screen * Vector3(0.295, 0.22125, 2)
	var direction := screen.basis * Vector3.FORWARD
	var point := Pointer.project(screen, origin, direction)
	assert_almost_eq(point.x, 240, 1)
	assert_almost_eq(point.y, 50, 1)


func test_off_screen_parallel_back_facing_and_behind_rays_miss() -> void:
	assert_eq(
		Pointer.project(Transform3D.IDENTITY, Vector3(0.6, 0, 2), Vector3.FORWARD), Pointer.MISS
	)
	assert_eq(
		Pointer.project(Transform3D.IDENTITY, Vector3(0, 0.45, 2), Vector3.FORWARD), Pointer.MISS
	)
	assert_eq(Pointer.project(Transform3D.IDENTITY, Vector3(0, 0, 2), Vector3.RIGHT), Pointer.MISS)
	assert_eq(Pointer.project(Transform3D.IDENTITY, Vector3(0, 0, -2), Vector3.BACK), Pointer.MISS)
	assert_eq(
		Pointer.project(Transform3D.IDENTITY, Vector3(0, 0, -2), Vector3.FORWARD), Pointer.MISS
	)
