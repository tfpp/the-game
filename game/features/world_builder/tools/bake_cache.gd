extends RefCounted
## Content-addressed bake receipt: both inputs and every saved output must match.

const Materials := preload("res://features/world_builder/materials.gd")
const BASE := "res://features/world_builder"


static func fingerprint(layout: Dictionary, sources: Array[String] = []) -> String:
	if sources.is_empty():
		for folder: String in [BASE, BASE + "/tools", BASE + "/textures"]:
			for name: String in DirAccess.get_files_at(folder):
				if name.ends_with(".gd") or name.ends_with(".gdshader") or ".png" in name:
					sources.append(folder.path_join(name))
		for material: StandardMaterial3D in Materials.create(layout["style"]["theme"]).values():
			_add_dependency(material.resource_path, sources)
			if material.albedo_texture != null:
				_add_dependency(material.albedo_texture.resource_path, sources)
	sources.sort()
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(layout))
	hash.update(var_to_bytes(Engine.get_version_info()))
	for path: String in sources:
		hash.update(path.to_utf8_buffer())
		hash.update(FileAccess.get_sha256(path).to_utf8_buffer())
	return hash.finish().hex_encode()


static func matches(output: String, signature: String) -> bool:
	var receipt := _receipt(output)
	if not FileAccess.file_exists(receipt):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(receipt))
	if not data is Dictionary or data.get("signature") != signature:
		return false
	var files: Variant = data.get("files")
	if not files is Dictionary or files.size() < 2 or not files.has(output):
		return false
	for path: String in files:
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != files[path]:
			return false
	return true


static func save(output: String, signature: String, maps: Array) -> Error:
	var hashes: Dictionary = {}
	for path: String in [output] + maps:
		if not FileAccess.file_exists(path):
			return ERR_FILE_NOT_FOUND
		hashes[path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(_receipt(output), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"signature": signature, "files": hashes}, "\t"))
	return file.get_error()


static func _receipt(output: String) -> String:
	return output.get_basename() + "_lightmaps/bake.json"


static func _add_dependency(path: String, sources: Array[String]) -> void:
	if path.is_empty() or path in sources:
		return
	sources.append(path)
	if FileAccess.file_exists(path + ".import"):
		sources.append(path + ".import")
	for dependency: String in ResourceLoader.get_dependencies(path):
		_add_dependency(dependency.get_slice("::", dependency.get_slice_count("::") - 1), sources)
