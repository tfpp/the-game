extends GutTest
## Pure gating and direction math for noclip (features/noclip/noclip.gd), kept free of
## scene access so it's unit-testable.

const Noclip := preload("res://features/noclip/noclip.gd")


func test_jos_is_authorized() -> void:
	assert_true(Noclip.is_authorized("jos"))


func test_other_names_are_not_authorized() -> void:
	assert_false(Noclip.is_authorized("Jos"))
	assert_false(Noclip.is_authorized("josephine"))
	assert_false(Noclip.is_authorized(""))


func test_fly_direction_is_zero_with_no_input() -> void:
	assert_eq(Noclip.fly_direction(0.0, 0.0, Vector2.ZERO), Vector3.ZERO)


func test_fly_direction_forward_faces_yaw_zero() -> void:
	var dir := Noclip.fly_direction(0.0, 0.0, Vector2(0.0, -1.0))
	assert_true(dir.is_equal_approx(Vector3(0.0, 0.0, -1.0)))


func test_fly_direction_follows_pitch_when_looking_up() -> void:
	var dir := Noclip.fly_direction(0.0, deg_to_rad(45.0), Vector2(0.0, -1.0))
	assert_true(dir.y > 0.5)


func test_fly_direction_strafe_is_horizontal() -> void:
	var dir := Noclip.fly_direction(0.0, deg_to_rad(45.0), Vector2(1.0, 0.0))
	assert_almost_eq(dir.y, 0.0, 0.001)


func test_fly_direction_is_normalized() -> void:
	var dir := Noclip.fly_direction(0.7, -0.3, Vector2(1.0, 1.0))
	assert_almost_eq(dir.length(), 1.0, 0.001)
