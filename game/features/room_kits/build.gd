extends SceneTree
## Export reusable, grid-aligned scene pieces from the same definitions as room generation.

const Style := preload("res://features/world_builder/style.gd")
const Builder := preload("res://features/world_builder/mesh_builder.gd")
const Geometry := preload("res://features/world_builder/geometry.gd")
const Materials := preload("res://features/world_builder/materials.gd")
const Architecture := preload("res://features/world_builder/architecture.gd")
const Pieces := preload("res://features/room_kits/pieces.gd")
const Catalog := preload("res://features/room_kits/catalog.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for kit: String in Catalog.KITS:
		for kind: String in [
			"floor",
			"ceiling",
			"wall",
			"inside_corner",
			"outside_corner",
			"doorway",
			"window",
			"skylight"
		]:
			_save(_piece(kit, kind), "res://features/room_kits/%s/%s.scn" % [kit, kind])
	var Sewer := preload("res://features/sewer_kit/kit.gd")
	var modules := {
		"straight": [2, 3],
		"corner": [1, 3],
		"tee": [0, 1, 3],
		"cross": [0, 1, 2, 3],
		"end": [3],
		"access": [3]
	}
	for kind: String in modules:
		var ports: Array[int] = []
		ports.assign(modules[kind])
		_save(
			Sewer.module_scene(ports, kind == "access"),
			"res://features/sewer_kit/modules/%s.scn" % kind
		)
	print("KIT_BUILD: four room kits and six sewer modules exported")
	quit()


func _piece(kit: String, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind.to_pascal_case()
	root.set_meta("kit", kit)
	root.set_meta("grid_size", 4.0)
	var openings := Node3D.new()
	openings.name = "Openings"
	Geometry.attach(root, openings, root)
	var g := Geometry.new()
	g.materials = Materials.create("hotel")
	var architecture := Architecture.new()
	architecture.set("_g", g)
	architecture.set("_root", root)
	architecture.set("_style", Style.DEFAULTS)
	if kind == "skylight":
		var lantern := preload("res://features/world_builder/skylights.gd").piece(
			Vector2(2, 2), kit
		)
		lantern.position.y = 3.5
		Geometry.attach(root, lantern, root)
		for child: Node in lantern.find_children("*", "", true, false):
			child.owner = root
		var clock := Node.new()
		clock.set_script(load("res://features/world_builder/window_sky.gd"))
		Geometry.attach(root, clock, root)
		var material := "ceiling" if kit == "classic" else kit + "_ceiling"
		for x: float in [-1.5, 1.5]:
			g.box(material, Vector3(x, 3.6, 0), Vector3(1, 0.2, 4), true)
		for z: float in [-1.5, 1.5]:
			g.box(material, Vector3(0, 3.6, z), Vector3(2, 0.2, 1), true)
	elif kind in ["floor", "ceiling"]:
		var material := kind if kit == "classic" else kit + "_" + kind
		g.box(material, Vector3(0, -0.1 if kind == "floor" else 3.6, 0), Vector3(4, 0.2, 4), true)
	else:
		var wall := {
			"a": Vector3(-2, 0, -2),
			"b": Vector3(2, 0, -2),
			"normal": Vector3.BACK,
			"height": 3.5,
			"kit": kit,
			"openings": []
		}
		if kind in ["doorway", "window"]:
			wall["openings"] = [
				{
					"id": "Opening",
					"kind": "door" if kind == "doorway" else "window",
					"start": 1.1,
					"width": 1.8,
					"height": 2.6 if kind == "doorway" else 1.8,
					"sill": 0.0 if kind == "doorway" else 1.0,
					"interactive": true
				}
			]
		Builder._wall(g, wall, Style.DEFAULTS)
		architecture._wall(wall)
		if kind.ends_with("corner"):
			var other := wall.duplicate(true)
			other["a"] = Vector3(-2, 0, -2)
			other["b"] = Vector3(-2, 0, 2 if kind == "inside_corner" else -6)
			other["normal"] = Vector3.RIGHT if kind == "inside_corner" else Vector3.LEFT
			Builder._wall(g, other, Style.DEFAULTS)
			architecture._wall(other)
			if kit == "classic":
				architecture._column(Vector3(-2, 0, -2), 3.5, 0.34)
			else:
				Pieces.corner(g, kit, Vector3(-2, 0, -2), 3.5)
	g.finish(root)
	return root


func _save(root: Node3D, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var scene := PackedScene.new()
	var result := scene.pack(root)
	if result == OK:
		result = ResourceSaver.save(scene, path, ResourceSaver.FLAG_COMPRESS)
	root.free()
	if result != OK:
		push_error("Kit export failed: " + path)
		quit(1)
