extends RefCounted
## File operations for isolated bake jobs; publish the scene only after import succeeds.


static func staged(stage: String, path: String) -> String:
	return stage.path_join(path.trim_prefix("res://"))


static func write_text(path: String, value: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(value)
	return file.get_error()


static func copy_file(source: String, destination: String) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	if error != OK:
		return error
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(source), destination)


static func copy_dependencies(resource: String, stage: String, seen: Dictionary = {}) -> Error:
	for dependency: String in ResourceLoader.get_dependencies(resource):
		var path := dependency.get_slice("::", dependency.get_slice_count("::") - 1)
		if not path.begins_with("res://") or seen.has(path):
			continue
		seen[path] = true
		var target := staged(stage, path)
		# The lightmap data resource was created directly in the staging project.
		if FileAccess.file_exists(target):
			continue
		var error := copy_file(path, target)
		if error != OK:
			return error
		if FileAccess.file_exists(path + ".import"):
			error = copy_file(path + ".import", target + ".import")
			if error != OK:
				return error
		error = copy_dependencies(path, stage, seen)
		if error != OK:
			return error
	return OK


static func publish(stage: String, output: String, maps: String, files: Array) -> Error:
	if files.is_empty() or not FileAccess.file_exists(staged(stage, output)):
		return ERR_INVALID_DATA
	# Validate the entire manifest before writing any files.
	for path: String in files:
		if not path.begins_with(maps + "/") or ".." in path:
			return ERR_INVALID_DATA
	# Each bake uses new resource filenames, preserving the previous bake until success.
	for path: String in files:
		var error := copy_file(staged(stage, path), ProjectSettings.globalize_path(path))
		if error != OK:
			return error
	var log: Array = []
	var result := OS.execute(
		OS.get_executable_path(),
		PackedStringArray(
			["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"]
		),
		log,
		true
	)
	var message := "\n".join(log)
	if result != 0 or "ERROR:" in message:
		printerr(message)
		return ERR_CANT_CREATE
	var destination := ProjectSettings.globalize_path(output)
	var pending := destination + ".pending"
	var error := copy_file(staged(stage, output), pending)
	if error == OK:
		error = DirAccess.rename_absolute(pending, destination)
	if error != OK:
		DirAccess.remove_absolute(pending)
		return error
	# Only the documented generated-lightmap directory is pruned.
	for name: String in DirAccess.get_files_at(maps):
		var path := maps.path_join(name)
		if (
			not files.has(path)
			and (
				name.ends_with(".exr") or name.ends_with(".exr.import") or name.ends_with(".lmbake")
			)
		):
			DirAccess.remove_absolute(path)
	return OK


static func remove_tree(path: String) -> void:
	for name: String in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(name))
	for name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)
