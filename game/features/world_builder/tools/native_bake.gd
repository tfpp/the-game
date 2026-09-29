extends RefCounted
## Godot-only authoring pipeline. The editor worker runs in an isolated project.

const Cache := preload("res://features/world_builder/tools/bake_cache.gd")
const Builder := preload("res://features/world_builder/mesh_builder.gd")
const Files := preload("res://features/world_builder/tools/bake_files.gd")
const WORKER := "res://features/world_builder/tools/bake_editor.gd"
const SHADER := "res://features/world_builder/baked_lighting.gdshader"
const TIMEOUT_MSEC := 1800000


static func run(
	tree: SceneTree,
	layout: Dictionary,
	output: String,
	overwrite: bool = false,
	rebake: bool = false
) -> Error:
	var signature := Cache.fingerprint(layout)
	if not rebake and Cache.matches(output, signature):
		print("WORLD_BUILD: inputs and saved assets unchanged; reusing baked lighting")
		return OK
	if FileAccess.file_exists(output) and not overwrite:
		printerr("Output changed or needs rebuilding; pass --force to replace it: ", output)
		return ERR_ALREADY_EXISTS
	if OS.get_name() == "Linux" and OS.get_environment("DISPLAY").is_empty():
		if OS.get_environment("WAYLAND_DISPLAY").is_empty():
			printerr(
				"Native baking needs a graphics-enabled editor worker (DISPLAY or WAYLAND_DISPLAY)."
			)
			return ERR_UNAVAILABLE
	var job := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var stage := OS.get_cache_dir().path_join("the-game-world-bakes").path_join(job)
	var maps := output.get_basename() + "_lightmaps"
	var data_path := maps.path_join("native-" + job + ".lmbake")
	var error := _prepare(tree, layout, output, data_path, stage)
	if error != OK:
		return error
	# Complete imports before opening the scene: editor import callbacks pump frames
	# and must never re-enter a lightmap bake.
	var import_log: Array = []
	var imported := OS.execute(
		OS.get_executable_path(),
		PackedStringArray(["--headless", "--path", stage, "--import"]),
		import_log,
		true
	)
	if imported != 0 or "ERROR:" in "\n".join(import_log):
		printerr("\n".join(import_log))
		return ERR_CANT_CREATE
	var args := PackedStringArray(
		[
			"--editor",
			"--path",
			stage,
			"--rendering-method",
			"mobile",
			"--language",
			"en",
			"--log-file",
			stage.path_join("worker.log"),
			"--",
			"--world-bake-worker"
		]
	)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid < 0:
		return ERR_CANT_FORK
	print("WORLD_BUILD: Godot lightmap worker started; log: ", stage.path_join("worker.log"))
	var started := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() - started > TIMEOUT_MSEC:
			OS.kill(pid)
			printerr("Native bake timed out. Previous scene retained. Worker files: ", stage)
			return ERR_TIMEOUT
		await tree.create_timer(0.25).timeout
	var result: Variant = null
	if FileAccess.file_exists(stage.path_join("result.json")):
		result = JSON.parse_string(FileAccess.get_file_as_string(stage.path_join("result.json")))
	var worker_log := FileAccess.get_file_as_string(stage.path_join("worker.log"))
	if not result is Dictionary or not result.get("ok", false) or "ERROR:" in worker_log:
		printerr(worker_log)
		printerr("Native bake failed. Previous scene retained. Worker files: ", stage)
		return ERR_CANT_CREATE
	error = Files.publish(stage, output, maps, result["files"])
	if error == OK:
		error = Cache.save(output, signature, result["files"])
		if error == OK:
			Files.remove_tree(stage)
	return error


static func _prepare(
	tree: SceneTree, layout: Dictionary, output: String, data_path: String, stage: String
) -> Error:
	for path: String in [
		output.get_base_dir(), data_path.get_base_dir(), "res://addons/world_bake"
	]:
		var error := DirAccess.make_dir_recursive_absolute(Files.staged(stage, path))
		if error != OK:
			return error
	var world := Builder.build(layout)
	tree.root.add_child(world)
	var error := prepare_geometry(world)
	if error == OK:
		var lightmap := LightmapGI.new()
		lightmap.name = "LightmapGI"
		lightmap.quality = LightmapGI.BAKE_QUALITY_HIGH
		lightmap.directional = false
		lightmap.bounces = 3
		lightmap.interior = true
		lightmap.max_texture_size = 2048
		lightmap.supersampling = true
		lightmap.supersampling_factor = 2.0
		lightmap.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
		lightmap.environment_custom_color = Color(0.65, 0.75, 1.0)
		lightmap.environment_custom_energy = 0.18
		lightmap.light_data = LightmapGIData.new()
		error = ResourceSaver.save(lightmap.light_data, Files.staged(stage, data_path))
		lightmap.light_data.take_over_path(data_path)
		world.add_child(lightmap)
		lightmap.owner = world
		if error == OK:
			var packed := PackedScene.new()
			error = packed.pack(world)
			if error == OK:
				error = ResourceSaver.save(
					packed, Files.staged(stage, output), ResourceSaver.FLAG_COMPRESS
				)
	world.free()
	if error != OK:
		return error
	error = Files.copy_dependencies(Files.staged(stage, output), stage)
	if error != OK:
		return error
	for pair: Array in [
		[WORKER, "res://addons/world_bake/plugin.gd"],
		[SHADER, SHADER],
		[SHADER + ".uid", SHADER + ".uid"]
	]:
		error = Files.copy_file(pair[0], Files.staged(stage, pair[1]))
		if error != OK:
			return error
	var config := ConfigFile.new()
	config.set_value("", "config_version", 5)
	config.set_value("application", "config/name", "World lightmap worker")
	config.set_value("rendering", "renderer/rendering_method", "mobile")
	config.set_value(
		"editor_plugins", "enabled", PackedStringArray(["res://addons/world_bake/plugin.cfg"])
	)
	error = config.save(stage.path_join("project.godot"))
	if error != OK:
		return error
	config = ConfigFile.new()
	config.set_value("plugin", "name", "World lightmap worker")
	config.set_value("plugin", "description", "Isolated authoring worker")
	config.set_value("plugin", "author", "The Game")
	config.set_value("plugin", "version", "1.0")
	config.set_value("plugin", "script", "plugin.gd")
	error = config.save(stage.path_join("addons/world_bake/plugin.cfg"))
	if error != OK:
		return error
	return Files.write_text(
		stage.path_join("job.json"), JSON.stringify({"scene": output, "data": data_path})
	)


static func prepare_geometry(world: Node3D) -> Error:
	var chunks := 0
	for node: Node in world.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.name.to_lower().ends_with("_unshadowed"):
			mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			continue
		mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var texel := 0.025 if mesh.name.to_lower().ends_with("_detail") else 0.16
		var error := (mesh.mesh as ArrayMesh).lightmap_unwrap(mesh.transform, texel)
		if error != OK:
			return error
		chunks += 1
	for node: Node in world.find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		light.light_bake_mode = Light3D.BAKE_STATIC
		light.light_size = 0.12 if str(light.name).begins_with("Sconce") else 0.25
	world.set_meta("lightmap_chunks", chunks)
	return OK
