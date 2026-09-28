extends GutTest
## Pure rotation math for the glowing cube (features/glowing_cube/glowing_cube.gd).

const GlowingCube := preload("res://features/glowing_cube/glowing_cube.gd")


func test_rotation_advances_by_speed_times_delta() -> void:
	var next: float = GlowingCube.next_rotation(0.0, 1.0)
	assert_almost_eq(next, 0.4, 0.0001)


func test_rotation_wraps_around_tau() -> void:
	var next: float = GlowingCube.next_rotation(TAU - 0.1, 1.0)
	assert_almost_eq(next, 0.3, 0.0001)


func test_rotation_never_leaves_the_0_tau_range() -> void:
	var y := 0.0
	for i: int in 1000:
		y = GlowingCube.next_rotation(y, 1.0 / 60.0)
		assert_between(y, 0.0, TAU)
