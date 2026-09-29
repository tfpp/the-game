extends RefCounted
## Six-metre port-based modules: straights, corners, junctions and access shafts.

const Geometry := preload("res://features/world_builder/geometry.gd")
const Profiles := preload("res://features/world_builder/profiles.gd")
const Materials := preload("res://features/world_builder/materials.gd")
const SEGMENT_LENGTH := 6.0
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


static func district_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(-14, 15):
		cells.append(Vector2i(x, 3))
	for x: int in [-14, 0, 14]:
		for z: int in 3:
			cells.append(Vector2i(x, z))
	# A second route loops around the maintenance area, with a pump-room spur.
	for x: int in range(-7, 8):
		cells.append(Vector2i(x, 6))
	for x: int in [-7, 7]:
		for z: int in [4, 5]:
			cells.append(Vector2i(x, z))
	cells.append(Vector2i(0, 7))
	cells.append(Vector2i(0, 8))
	return cells


static func build(segments: int = 4) -> Node3D:
	var cells: Array[Vector2i] = []
	for index: int in segments:
		cells.append(Vector2i(0, index))
	return build_network(cells, [Vector2i.ZERO])


static func build_network(cells: Array[Vector2i], shafts: Array[Vector2i]) -> Node3D:
	var root := Node3D.new()
	root.name = "Sewer"
	var cache: Dictionary[String, PackedScene] = {}
	for cell: Vector2i in cells:
		var ports: Array[int] = []
		for side: int in 4:
			if cell + DIRECTIONS[side] in cells:
				ports.append(side)
		var access := cell in shafts
		var key := str(ports) + str(access)
		if not cache.has(key):
			var module := module_scene(ports, access)
			var packed := PackedScene.new()
			packed.pack(module)
			module.free()
			cache[key] = packed
		var piece := cache[key].instantiate() as Node3D
		piece.name = "Module_%s_%s" % [cell.x, cell.y]
		piece.position = Vector3(cell.x, 0, cell.y) * SEGMENT_LENGTH
		Geometry.attach(root, piece, root)
		for child: Node in piece.find_children("*", "", true, false):
			child.owner = root
	root.set_meta("cells", cells)
	root.set_meta("shafts", shafts)
	root.set_meta("segment_length", SEGMENT_LENGTH)
	return root


static func module_scene(ports: Array[int], access: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "SewerModule"
	root.set_meta("ports", ports)
	root.set_meta("access", access)
	var g := Geometry.new()
	g.materials = Materials.create("hotel")
	g.materials["brick"] = _material(Color("48534d"))
	g.materials["steel"] = _material(Color("505c60"))
	g.materials["water"] = _material(Color("263e2b"))
	g.materials["water"].set("roughness", 0.2)
	for x: int in [-2, 0, 2]:
		for z: int in [-2, 0, 2]:
			var drain := (
				(x == 0 and z == 0)
				or (z == 0 and ((x < 0 and 0 in ports) or (x > 0 and 1 in ports)))
				or (x == 0 and ((z < 0 and 2 in ports) or (z > 0 and 3 in ports)))
			)
			if drain:
				g.box("concrete", Vector3(x, -0.65, z), Vector3(2, 0.3, 2), true)
				g.box("water", Vector3(x, -0.35, z), Vector3(2, 0.03, 2))
				g.box("", Vector3(x, -0.035, z), Vector3(2, 0.07, 2), true)
				for bar: int in 10:
					g.box("steel", Vector3(x - 0.95 + bar * 0.2, -0.03, z), Vector3(0.055, 0.06, 2))
			else:
				g.box("concrete", Vector3(x, -0.2, z), Vector3(2, 0.4, 2), true)
			if not (access and x == -2 and z == 0):
				g.box("concrete", Vector3(x, 3.3, z), Vector3(2, 0.2, 2), true)
	for side: int in 4:
		var direction := Vector3(DIRECTIONS[side].x, 0, DIRECTIONS[side].y)
		var basis := Basis(Vector3.UP, atan2(direction.x, direction.z))
		if side not in ports:
			g.box("brick", direction * 3.1 + Vector3.UP * 1.4, Vector3(6.2, 3.6, 0.2), true, basis)
			for line: int in 6:
				g.box(
					"concrete",
					direction * 2.99 + Vector3.UP * (line * 0.5),
					Vector3(6, 0.022, 0.025),
					false,
					basis
				)
			var along := basis.x * 3
			var center := direction * 2.75 + Vector3.UP * 2.0
			Profiles.tube(g, "steel", [center - along, center + along], 0.12)
		else:
			var marker := Marker3D.new()
			marker.name = "Port%d" % side
			marker.position = direction * 3
			Geometry.attach(root, marker, root)
			# Squared portal ribs leave the entire walking opening clear.
			g.box("steel", direction * 3 + Vector3.UP * 3.05, Vector3(6, 0.12, 0.15), false, basis)
	if access:
		_shaft(g)
	var light := OmniLight3D.new()
	light.name = "ServiceLight"
	light.position = Vector3(0, 2.65, 0)
	light.light_color = Color("c4d5bc")
	light.light_energy = 0.85
	light.omni_range = 7
	Geometry.attach(root, light, root)
	g.box("steel", Vector3(0, 3.05, 0), Vector3(0.9, 0.1, 0.3))
	g.box("glow", Vector3(0, 2.99, 0), Vector3(0.8, 0.035, 0.2))
	g.finish(root)
	return root


static func _shaft(g: Geometry) -> void:
	# Module coordinates; top aligns with the storage floor six metres above.
	for x: float in [-3.08, -0.92]:
		g.box("concrete", Vector3(x, 4.65, 0), Vector3(0.16, 2.7, 2.16), true)
	for z: float in [-1.08, 1.08]:
		g.box("concrete", Vector3(-2, 4.65, z), Vector3(2, 2.7, 0.16), true)
	for x: float in [-2.42, -1.58]:
		g.box("steel", Vector3(x, 3.55, 0.55), Vector3(0.07, 7.1, 0.07))
	for step: int in 24:
		g.box("steel", Vector3(-2, 0.18 + step * 0.29, 0.55), Vector3(0.9, 0.045, 0.06))


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = preload("res://features/world_builder/textures/plaster.png")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.uv1_scale = Vector3.ONE * 1.5
	material.roughness = 0.85
	return material
