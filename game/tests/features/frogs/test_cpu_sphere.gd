extends GutTest

const Source := preload("res://assets/frogs/models/sphere_source.tres")


func test_cpu_detail_source_matches_the_existing_frog_sphere() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = .5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var expected := sphere.surface_get_arrays(0)
	assert_eq(Source.arrays[Mesh.ARRAY_INDEX], expected[Mesh.ARRAY_INDEX])
	for field: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL]:
		var actual: PackedVector3Array = Source.arrays[field]
		var reference: PackedVector3Array = expected[field]
		assert_eq(actual.size(), reference.size())
		for index: int in actual.size():
			assert_true(actual[index].is_equal_approx(reference[index]))
