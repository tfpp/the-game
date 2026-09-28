extends GutTest
## Validation and orientation math for sprays (features/spray/spray.gd).


func test_accepts_nearby_point_with_unit_normal() -> void:
	assert_true(Spray.is_valid_request(Vector3.ZERO, Vector3(0, 1, -3), Vector3.UP))


func test_rejects_far_point() -> void:
	assert_false(Spray.is_valid_request(Vector3.ZERO, Vector3(0, 0, -50), Vector3.UP))


func test_rejects_bad_normal_and_nan() -> void:
	assert_false(Spray.is_valid_request(Vector3.ZERO, Vector3(0, 1, -3), Vector3(0, 5, 0)))
	assert_false(Spray.is_valid_request(Vector3.ZERO, Vector3(NAN, 0, 0), Vector3.UP))


func test_surface_basis_y_is_normal() -> void:
	for normal: Vector3 in [
		Vector3.UP, Vector3.RIGHT, Vector3(0, 0, -1), Vector3(1, 1, 0).normalized()
	]:
		var basis := Spray.surface_basis(normal)
		assert_true(basis.y.is_equal_approx(normal))
		assert_almost_eq(basis.determinant(), 1.0, 0.001)


func test_default_texture_builds() -> void:
	assert_eq(Spray._default_texture().get_width(), Spray.SPRAY_SIZE_PX)
