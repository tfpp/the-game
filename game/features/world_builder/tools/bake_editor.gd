@tool
extends EditorPlugin
## Version-checked adapter around Godot's editor-only Bake Lightmaps action.
## Installed only in the temporary worker project, never the user's project.

const Files := preload("res://features/world_builder/tools/bake_files.gd")
const BakedShader := preload("res://features/world_builder/baked_lighting.gdshader")
var _job: Dictionary
var _scene: Node3D
var _lightmap: LightmapGI
var _deadline: int
var _next: Callable
var _due: int


func _enter_tree() -> void:
	if "--world-bake-worker" in OS.get_cmdline_user_args():
		_deadline = Time.get_ticks_msec() + 60000
		_schedule(_open)


func _schedule(callback: Callable, delay: int = 100) -> void:
	_next = callback
	_due = Time.get_ticks_msec() + delay
	set_process(true)


func _process(_delta: float) -> void:
	if not _next.is_valid() or Time.get_ticks_msec() < _due:
		return
	var callback := _next
	_next = Callable()
	set_process(false)
	callback.call()


func _open() -> void:
	if EditorInterface.get_resource_filesystem().is_scanning():
		_retry(_open)
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://job.json"))
	if not value is Dictionary or not value.has("scene") or not value.has("data"):
		_finish(false, "Invalid native bake job")
		return
	_job = value
	EditorInterface.open_scene_from_path(_job["scene"])
	_schedule(_select)


func _select() -> void:
	_scene = EditorInterface.get_edited_scene_root() as Node3D
	if _scene == null or _scene.scene_file_path != _job["scene"]:
		_retry(_select)
		return
	_lightmap = _scene.get_node_or_null("LightmapGI") as LightmapGI
	if _lightmap == null:
		_finish(false, "Generated scene has no LightmapGI")
		return
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(_lightmap)
	EditorInterface.edit_node(_lightmap)
	_schedule(_bake, 3000)


func _bake() -> void:
	for node: Node in EditorInterface.get_base_control().find_children("*", "Button", true, false):
		var button := node as Button
		if button.text != "Bake Lightmaps":
			continue
		if button.disabled:
			_finish(false, "Godot cannot bake on this worker: " + button.tooltip_text)
			return
		print("WORLD_BAKE: Godot LightmapGI high quality, three bounces, 2x supersampling")
		# Baking pumps editor frames: run from _process with processing paused.
		button.pressed.emit()
		_schedule(_finalize)
		return
	_finish(false, "Bake Lightmaps action not found; check the Godot editor version")


func _validate_bake() -> bool:
	var data := _lightmap.light_data
	if data == null or data.get_user_count() != int(_scene.get_meta("lightmap_chunks", 0)):
		_finish(false, "Bake did not cover every structural mesh")
		return false
	for index: int in data.get_user_count():
		if not _lightmap.get_node_or_null(data.get_user_path(index)) is MeshInstance3D:
			_finish(false, "Lightmap references a missing mesh")
			return false
	if data.get_lightmap_textures().is_empty():
		_finish(false, "Bake returned no lightmap textures")
		return false
	return true


func _finalize() -> void:
	if not _validate_bake():
		return
	var imports := PackedStringArray()
	var files: Array[String] = []
	for name: String in DirAccess.get_files_at(str(_job["data"]).get_base_dir()):
		var path := str(_job["data"]).get_base_dir().path_join(name)
		if name.ends_with(".exr"):
			# HDR arrays remain uncompressed for Compatibility/WebGL portability.
			var config := ConfigFile.new()
			if config.load(path + ".import") != OK:
				_finish(false, "Missing lightmap array import settings")
				return
			config.set_value("params", "compress/mode", 0)
			config.save(path + ".import")
			imports.append(path)
			files.append(path)
			files.append(path + ".import")
		elif name.ends_with(".lmbake"):
			files.append(path)
	if imports.is_empty():
		_finish(false, "No lightmap images were saved")
		return
	EditorInterface.get_resource_filesystem().reimport_files(imports)
	var sizes := Files.lighting_sizes(files)
	var budget := int(_job["max_bytes"])
	# Leave space for the cache receipt and resource metadata in the export pack.
	if sizes.x < 0 or maxi(sizes.x, sizes.y) + 4096 > budget:
		_finish(
			false, "Lightmaps exceed %d bytes: source %d, runtime %d" % [budget, sizes.x, sizes.y]
		)
		return
	print("WORLD_BAKE: lightmap bytes: source=", sizes.x, " runtime=", sizes.y)
	for node: Node in _scene.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.gi_mode != GeometryInstance3D.GI_MODE_STATIC:
			continue
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for index: int in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(index) as StandardMaterial3D
			var material := ShaderMaterial.new()
			material.shader = BakedShader
			material.set_shader_parameter("albedo_texture", original.albedo_texture)
			material.set_shader_parameter("albedo_tint", original.albedo_color)
			material.set_shader_parameter(
				"texture_scale", Vector2(original.uv1_scale.x, original.uv1_scale.y)
			)
			mesh.set_surface_override_material(index, material)
	for node: Node in _scene.find_children("*", "OmniLight3D", true, false):
		node.free()
	_scene.set_meta("baked_lighting", "Godot LightmapGI: high quality, 3 bounces, 2x supersampling")
	if EditorInterface.save_scene() != OK:
		_finish(false, "Cannot save baked scene")
		return
	_finish(true, "Native lightmap bake complete", files)


func _retry(callback: Callable) -> void:
	if Time.get_ticks_msec() >= _deadline:
		_finish(false, "Timed out loading the isolated bake project")
		return
	_schedule(callback, 250)


func _finish(ok: bool, message: String, files: Array[String] = []) -> void:
	print("WORLD_BAKE: ", message)
	var file := FileAccess.open("res://result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok, "message": message, "files": files}))
		file.close()
	EditorInterface.get_selection().clear()
	# Allow pending editor scene-save/thumbnail callbacks to finish before teardown.
	_schedule(func() -> void: get_tree().quit(0 if ok else 1), 1500)
