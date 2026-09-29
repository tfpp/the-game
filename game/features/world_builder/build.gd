extends SceneTree
## Generate a scene; --bake compiles static lighting into it before saving.

const Layout := preload("res://features/world_builder/layout.gd")
const Builder := preload("res://features/world_builder/mesh_builder.gd")
const NativeBake := preload("res://features/world_builder/tools/native_bake.gd")


func _initialize() -> void:
	_run.call_deferred()


# gdlint: disable=max-returns
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() > 5:
		_fail("Usage: -- INPUT.json OUTPUT.tscn|OUTPUT.scn [--bake] [--force] [--rebake]")
		return
	for flag: String in args.slice(2):
		if flag not in ["--force", "--bake", "--rebake"]:
			_fail("Unknown build option: " + flag)
			return
	if args[1].get_extension() not in ["tscn", "scn"]:
		_fail("Output must end in .tscn (text) or .scn (compact binary).")
		return
	if "--rebake" in args and "--bake" not in args:
		_fail("--rebake requires --bake.")
		return
	if FileAccess.file_exists(args[1]) and "--force" not in args and "--bake" not in args:
		_fail("Output exists; pass --force to replace it: %s" % args[1])
		return
	var file := FileAccess.open(args[0], FileAccess.READ)
	if file == null or file.get_length() > 1048576:
		_fail("Cannot read blueprint, or it exceeds 1 MiB: %s" % args[0])
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		_fail(
			(
				"Blueprint must be a JSON object. %s (line %d)"
				% [json.get_error_message(), json.get_error_line()]
			)
		)
		return
	var layout := Layout.compile(json.data)
	if not layout["errors"].is_empty():
		_fail("\n".join(layout["errors"]))
		return
	if "--bake" in args:
		await _compile_lighting(layout, args[1], "--force" in args, "--rebake" in args)
		return
	var generated := Builder.build(layout)
	var scene := PackedScene.new()
	var result := scene.pack(generated)
	if result == OK:
		var flags := ResourceSaver.FLAG_COMPRESS if args[1].get_extension() == "scn" else 0
		result = ResourceSaver.save(scene, args[1], flags)
	generated.free()
	if result != OK:
		_fail("Could not save scene: %s" % error_string(result))
		return
	if not _save_doors(layout, args[1]):
		return
	print(
		(
			"WORLD_BUILD: %d rooms, %d connections, %d floor cells -> %s"
			% [layout["rooms"].size(), layout["paths"].size(), layout["cells"].size(), args[1]]
		)
	)
	quit()


func _compile_lighting(layout: Dictionary, output: String, overwrite: bool, rebake: bool) -> void:
	if not output.begins_with("res://") or output.get_extension() != "scn" or ".." in output:
		_fail("Baked output must be a res:// path ending in .scn.")
		return
	print("WORLD_BUILD: checking geometry and baked lighting...")
	var result := await NativeBake.run(self, layout, output, overwrite, rebake)
	if result != OK:
		_fail("Lighting compilation failed; see the compiler output above.")
		return
	if not _save_doors(layout, output):
		return
	print("WORLD_BUILD: baked scene ready -> ", output)
	quit()


func _save_doors(layout: Dictionary, output: String) -> bool:
	var companion := output.get_basename() + "_doors.tscn"
	if layout["doors"].is_empty() and not FileAccess.file_exists(companion):
		return true
	var root := preload("res://features/world_builder/doorways.gd").runtime_scene(layout)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, companion)
	root.free()
	if error != OK:
		_fail("Could not save runtime door companion: %s" % error_string(error))
		return false
	return true


func _fail(message: String) -> void:
	printerr("WORLD_BUILD: ", message)
	quit(1)
