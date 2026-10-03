extends SceneTree
## Preserve the existing SphereMesh detail geometry as CPU-side authoring data.
## Run: godot --headless --path game -s ../docs/design/model-sources/frogs/bake_cpu_sphere.gd
const Source := preload("res://features/frogs/sphere_source.gd")


func _initialize() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = .5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var original := sphere.surface_get_arrays(0)
	var source := Source.new()
	source.arrays.resize(Mesh.ARRAY_MAX)
	for field: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX]:
		source.arrays[field] = original[field]
	assert(ResourceSaver.save(source, "res://assets/frogs/models/sphere_source.tres") == OK)
	quit()
