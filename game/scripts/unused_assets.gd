extends SceneTree
## Prints an export exclude filter for the files under res://assets/ that nothing uses,
## so exports ship only what the game references while the full asset packs stay in
## the repo. `scripts/export.sh` appends it to the presets' exclude_filter.
##
## "Used" means some project file outside assets/ (scripts, scenes, resources) names
## the asset by its full res:// path, plus whatever those assets depend on. Paths built
## at runtime (string concatenation) aren't seen: keep asset paths literal.
##
## Usage: godot --headless -s scripts/unused_assets.gd

const ASSETS := "res://assets/"
const SCANNED_EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "cfg", "godot"]
## Not part of the game: never scanned for references.
const SKIPPED_DIRS: Array[String] = ["res://.godot", "res://addons", "res://tests", "res://scripts"]


func _initialize() -> void:
	var used := used_assets()
	# The game always uses some assets. Finding none means the scan broke, and
	# excluding everything would ship a build without its art: fail instead.
	if used.is_empty():
		printerr("unused_assets.gd: found no used assets; refusing to exclude them all")
		quit(1)
		return
	var filters: Array[String] = []
	_collect_unused(ASSETS.trim_suffix("/"), used, filters)
	print(",".join(filters))
	quit()


## Every asset path that a project file names, plus their dependencies.
static func used_assets() -> Dictionary:
	var used := {}
	# Up to the closing quote or parenthesis: asset names can contain spaces.
	var pattern := RegEx.create_from_string("res://assets/[^\"'()\\n]+")
	var skipped: Array[String] = SKIPPED_DIRS.duplicate()
	skipped.append(ASSETS.trim_suffix("/"))
	for path: String in _files("res://", skipped):
		if not path.get_extension() in SCANNED_EXTENSIONS:
			continue
		for found: RegExMatch in pattern.search_all(FileAccess.get_file_as_string(path)):
			_add_with_dependencies(found.get_string(), used)
	return used


static func _add_with_dependencies(path: String, used: Dictionary) -> void:
	if used.has(path) or not FileAccess.file_exists(path):
		return
	used[path] = true
	for dependency: String in ResourceLoader.get_dependencies(path):
		# Entries look like "uid://...::::res://path" or a bare path.
		_add_with_dependencies(dependency.get_slice("::", dependency.get_slice_count("::") - 1), used)


## Appends a filter for each unused file under `dir`, collapsing wholly unused
## directories to "dir/*". Returns true if anything under `dir` is used.
static func _collect_unused(dir: String, used: Dictionary, filters: Array[String]) -> bool:
	var unused: Array[String] = []
	var any_used := false
	for sub: String in DirAccess.get_directories_at(dir):
		var sub_path := dir.path_join(sub)
		var sub_filters: Array[String] = []
		if _collect_unused(sub_path, used, sub_filters):
			any_used = true
			filters.append_array(sub_filters)
		else:
			unused.append(_relative(sub_path) + "/*")
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "import":
			continue
		var file_path := dir.path_join(file)
		if used.has(file_path):
			any_used = true
		else:
			unused.append(_relative(file_path))
	if any_used:
		filters.append_array(unused)
	return any_used


static func _relative(path: String) -> String:
	return path.trim_prefix("res://")


static func _files(dir: String, skipped: Array[String]) -> Array[String]:
	var result: Array[String] = []
	if dir.trim_suffix("/") in skipped:
		return result
	for sub: String in DirAccess.get_directories_at(dir):
		result.append_array(_files(dir.path_join(sub), skipped))
	for file: String in DirAccess.get_files_at(dir):
		result.append(dir.path_join(file))
	return result
