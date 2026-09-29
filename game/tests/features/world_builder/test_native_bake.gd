extends GutTest

const Layout := preload("res://features/world_builder/layout.gd")
const Builder := preload("res://features/world_builder/mesh_builder.gd")
const Bake := preload("res://features/world_builder/tools/native_bake.gd")
const Cache := preload("res://features/world_builder/tools/bake_cache.gd")
const Files := preload("res://features/world_builder/tools/bake_files.gd")


func test_native_preparation_unwraps_structure_and_excludes_glass_and_fixtures() -> void:
	var layout := (
		Layout
		. compile(
			{
				"version": 1,
				"rooms": [{"id": "Room", "size": [7, 7], "at": [0, 0]}],
			}
		)
	)
	var world := Builder.build(layout)
	add_child_autofree(world)
	assert_eq(Bake.prepare_geometry(world), OK)
	var structural := 0
	var excluded := 0
	for node: Node in world.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if str(mesh.name).ends_with("_unshadowed"):
			assert_eq(mesh.gi_mode, GeometryInstance3D.GI_MODE_DISABLED)
			excluded += 1
		else:
			assert_eq(mesh.gi_mode, GeometryInstance3D.GI_MODE_STATIC)
			for index: int in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(index)
				assert_eq(arrays[Mesh.ARRAY_TEX_UV2].size(), arrays[Mesh.ARRAY_VERTEX].size())
			structural += 1
	assert_gt(structural, 0)
	assert_gt(excluded, 0)
	assert_eq(world.get_meta("lightmap_chunks"), structural)
	var lights := world.find_children("*", "OmniLight3D", true, false)
	assert_gt(lights.size(), 0)
	for node: Node in lights:
		var light := node as OmniLight3D
		assert_eq(light.light_bake_mode, Light3D.BAKE_STATIC)
		assert_gt(light.light_size, 0.0)


func test_publish_validates_entire_manifest_before_copying_files() -> void:
	var stage := "user://native-bake-test"
	DirAccess.make_dir_recursive_absolute(stage)
	Files.write_text(stage.path_join("wing.scn"), "previous scene")
	assert_eq(
		Files.publish(
			stage, "res://wing.scn", "res://maps", ["res://maps/missing.exr", "res://other.exr"]
		),
		ERR_INVALID_DATA
	)
	assert_eq(FileAccess.get_file_as_string(stage.path_join("wing.scn")), "previous scene")
	Files.remove_tree(stage)


func test_cache_checks_inputs_and_saved_outputs() -> void:
	var base := "user://native-cache-test"
	var output := base + "/room.scn"
	var map := base + "/room_lightmaps/native.exr"
	var source := base + "/generator.gd"
	DirAccess.make_dir_recursive_absolute(map.get_base_dir())
	Files.write_text(source, "generator v1")
	Files.write_text(output, "saved scene")
	Files.write_text(map, "saved lightmap")
	var signature := Cache.fingerprint({"height": 4}, [source])
	assert_false(Cache.matches(output, signature))
	assert_eq(Cache.save(output, signature, [map]), OK)
	assert_true(Cache.matches(output, signature))
	assert_eq(signature, Cache.fingerprint({"height": 4}, [source]))
	assert_false(Cache.matches(output, Cache.fingerprint({"height": 5}, [source])))
	Files.write_text(source, "generator v2")
	assert_false(Cache.matches(output, Cache.fingerprint({"height": 4}, [source])))
	Files.write_text(map, "edited lightmap")
	assert_false(Cache.matches(output, signature))
	Files.write_text(map, "saved lightmap")
	assert_true(Cache.matches(output, signature))
	DirAccess.remove_absolute(map)
	assert_false(Cache.matches(output, signature))
	Files.remove_tree(base)
