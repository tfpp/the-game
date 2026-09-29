extends RefCounted
## Cell-aligned roof openings and reusable glazed roof lanterns for every room kit.

const Geometry := preload("res://features/world_builder/geometry.gd")
const Materials := preload("res://features/world_builder/materials.gd")


static func apply(layout: Dictionary, rooms: Array) -> void:
	layout["skylight_cells"] = {}
	layout["skylights"] = []
	for room: Dictionary in rooms:
		if not room.get("skylight", false):
			continue
		if not layout["ceiling"]:
			layout["errors"].append("Skylights require a ceiling.")
			continue
		var rect: Rect2i = layout["rooms"][room["id"]]
		var size := Vector2i(clampi(rect.size.x / 2, 2, 6), clampi(rect.size.y / 2, 2, 6))
		var opening := Rect2i(rect.position + (rect.size - size) / 2, size)
		for z: int in range(opening.position.y, opening.end.y):
			for x: int in range(opening.position.x, opening.end.x):
				layout["skylight_cells"][Vector2i(x, z)] = true
		var scale: float = layout["cell_size"]
		var center := (Vector2(opening.position) + Vector2(size) / 2) * scale
		var height: float = layout["heights"][rect.position]
		layout["skylights"].append(
			{
				"room": room["id"],
				"size": Vector2(size) * scale,
				"position":
				Vector3(center.x, layout["room_elevations"][room["id"]] + height, center.y),
				"kit": layout["room_kits"][room["id"]],
				"height": height,
				"room_size": Vector2(rect.size) * scale
			}
		)


static func build(layout: Dictionary, root: Node3D) -> void:
	if layout["skylights"].is_empty():
		return
	var parent := Node3D.new()
	parent.name = "Skylights"
	Geometry.attach(root, parent, root)
	if not root.has_node("WindowSky"):
		var clock := Node.new()
		clock.name = "WindowSky"
		clock.set_script(load("res://features/world_builder/window_sky.gd"))
		Geometry.attach(root, clock, root)
	for definition: Dictionary in layout["skylights"]:
		var lantern := piece(
			definition["size"], definition["kit"], definition["height"], definition["room_size"]
		)
		lantern.name = definition["room"]
		lantern.position = definition["position"]
		Geometry.attach(parent, lantern, root)
		for child: Node in lantern.find_children("*", "", true, false):
			child.owner = root


static func piece(
	size: Vector2, kit: String, height: float = 3.5, room_size: Vector2 = Vector2(10, 10)
) -> Node3D:
	var root := Node3D.new()
	root.name = "Skylight"
	root.set_meta("aperture_size", size)
	var g := Geometry.new()
	g.materials = Materials.create("hotel")
	var trim := "gold" if kit == "classic" else kit + "_trim"
	var reveal := "plaster" if kit == "classic" else kit + "_ceiling"
	for x: float in [-size.x / 2, size.x / 2]:
		g.box(reveal, Vector3(x, 0.12, 0), Vector3(0.18, 0.3, size.y + 0.18), true)
		g.box(trim, Vector3(x, -0.04, 0), Vector3(0.26, 0.08, size.y + 0.26))
	for z: float in [-size.y / 2, size.y / 2]:
		g.box(reveal, Vector3(0, 0.12, z), Vector3(size.x + 0.18, 0.3, 0.18), true)
		g.box(trim, Vector3(0, -0.04, z), Vector3(size.x + 0.26, 0.08, 0.26))
	for index: int in range(1, ceili(size.x / 2)):
		var x := -size.x / 2 + size.x * index / ceili(size.x / 2)
		g.box(trim, Vector3(x, 0.15, 0), Vector3(0.065, 0.08, size.y))
	g.box(trim, Vector3(0, 0.15, 0), Vector3(size.x, 0.08, 0.065))
	# Glass is above the cut ceiling: solid for players, transparent to the sky view.
	g.cast_shadows = false
	g.box("glass", Vector3(0, 0.20, 0), Vector3(size.x, 0.025, size.y), true)
	g.finish(root)
	var sky := MeshInstance3D.new()
	sky.name = "SkyPane"
	var quad := QuadMesh.new()
	quad.size = size
	quad.material = preload("res://features/world_builder/window_sky.tres")
	sky.mesh = quad
	sky.rotation.x = PI / 2
	sky.position.y = 0.25
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Geometry.attach(root, sky, root)
	var light := OmniLight3D.new()
	light.name = "Daylight"
	light.set_script(load("res://features/world_builder/skylight_light.gd"))
	light.position.y = -minf(1.0, height * 0.25)
	light.light_energy = 3.0
	light.omni_range = maxf(8, Vector3(room_size.x / 2, height, room_size.y / 2).length() + 2)
	light.omni_attenuation = 0.65
	light.shadow_enabled = true
	light.shadow_bias = 0.025
	Geometry.attach(root, light, root)
	return root
