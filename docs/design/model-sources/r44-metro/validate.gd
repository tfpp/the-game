extends SceneTree
## Validate the shipped scene and the GLB, including actual mesh data.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var native := load("res://features/metro/r44_five_car_set.tscn") as PackedScene
	var scene := native.instantiate() as Node3D
	root.add_child(scene)
	assert(scene.get_child_count() == 6)
	assert(scene.find_children("*", "AnimatableBody3D", true, false).size() == 80)
	preload("res://../docs/design/model-sources/r44-metro/cabin.gd").flatten_grids(scene)
	var native_bounds := audit(scene)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	assert(document.append_from_file("res://assets/metro/models/r44_five_car_set.glb", state) == OK)
	var imported := document.generate_scene(state) as Node3D
	root.add_child(imported)
	var animation := imported.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(animation != null and animation.get_animation_list().size() == 6)
	assert(animation.get_animation("open_all").get_track_count() == 80)
	var glb_bounds := audit(imported)
	assert(native_bounds.position.is_equal_approx(glb_bounds.position))
	assert(native_bounds.size.is_equal_approx(glb_bounds.size))
	assert(absf(glb_bounds.size.z - 114.3) < 0.002)
	assert(absf(glb_bounds.size.y - 3.66) < 0.002)
	assert(glb_bounds.size.x < 3.2)
	for path: String in [
		"res://assets/metro/textures/r44_atlas.png",
		"res://assets/metro/textures/r44_livery.png",
		"res://assets/metro/textures/r44_graffiti.png",
		"res://assets/metro/textures/r44_interior.png"
	]:
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		assert(image != null and image.get_width() <= 128 and image.get_height() <= 128)
	print(
		"R44_VALIDATE PASS: native/GLB bounds match, 5 cars, 80 doors, 10 trucks, valid mesh/UV data"
	)
	scene.queue_free()
	imported.queue_free()
	quit()


func audit(scene: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	var triangles := 0
	var trucks := 0
	var material_ids: Dictionary[int, bool] = {}
	for child: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if instance.name.begins_with("Truck"):
			trucks += 1
		var box: AABB = instance.global_transform * instance.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for surface: int in instance.mesh.get_surface_count():
			var mat := instance.mesh.surface_get_material(surface) as StandardMaterial3D
			assert(mat != null)
			material_ids[mat.get_instance_id()] = true
			var texture := mat.albedo_texture
			assert(texture == null or (texture.get_width() <= 128 and texture.get_height() <= 128))
			var arrays := instance.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			assert(positions.size() == normals.size() and positions.size() == uv.size())
			for i: int in positions.size():
				assert(positions[i].is_finite() and normals[i].is_finite() and uv[i].is_finite())
				assert(absf(normals[i].length() - 1.0) < 0.001)
				assert(uv[i].x >= 0 and uv[i].x <= 1 and uv[i].y >= 0 and uv[i].y <= 1)
			assert(indices.size() % 3 == 0)
			for i: int in range(0, indices.size(), 3):
				var a := indices[i]
				var b := indices[i + 1]
				var c := indices[i + 2]
				assert(mini(a, mini(b, c)) >= 0)
				assert(maxi(a, maxi(b, c)) < positions.size())
				var cross := (positions[c] - positions[a]).cross(positions[b] - positions[a])
				assert(cross.length() > 0.000001)
				assert(cross.normalized().dot(normals[a]) > 0.99)
			triangles += indices.size() / 3
	assert(trucks == 10)
	assert(triangles > 15692 and triangles < 50000)
	assert(material_ids.size() == 6)
	print("Triangles: ", triangles, "; materials: ", material_ids.size(), "; bounds: ", bounds)
	return bounds
