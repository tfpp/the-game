extends RefCounted

const KIT := preload("res://features/street_hotel/room_kit.gd")
const SPEC := preload("res://features/street_hotel/spec.gd")
const SHELL := preload("res://features/procedural_rooms/shell_mesh.gd")
const FURNITURE := preload("res://features/street_hotel/furnishings.gd")
const CARPET := preload("res://assets/casino_hub/textures/carpet_albedo.png")
const WALLPAPER := preload("res://assets/casino_hub/textures/wallpaper_albedo.png")
const WOOD := preload("res://assets/casino_hub/textures/walnut_albedo.png")


static func build(parent: Node3D, floor_index: int, furnished: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "FloorLayout"
	parent.add_child(root)
	var lobby := KIT.lobby()
	root.add_child(lobby)
	var previous := lobby
	var guests: Array[Node3D] = []
	for bay: int in range(10):
		var hall := KIT.corridor("Hall%d" % bay)
		root.add_child(hall)
		_join(root, previous, "Out", hall, "In")
		previous = hall
		for side: int in [-1, 1]:
			var index := bay * 2 + (1 if side > 0 else 0)
			var number := SPEC.room_number(floor_index, index)
			var room := KIT.guest("Room%d" % number)
			root.add_child(room)
			_join(root, hall, "West" if side < 0 else "East", room, "In")
			room.set_meta("room_index", index)
			room.set_meta("recipe", SPEC.recipe(floor_index, index))
			guests.append(room)
			for y: float in [.9, 2.7]:
				KIT._wall(
					room, Vector3(0, 0, 7.99), 0, -1.96, 1.96, y - .04, y + .04, "trim", false
				)
			for x: float in [-1.9, 0, 1.9]:
				KIT._wall(room, Vector3(0, 0, 7.99), 0, x - .04, x + .04, .9, 2.7, "trim", false)
			for side_x: float in [-2.05, 2.05]:
				KIT._wall(
					room,
					Vector3(0, 0, 7.97),
					0,
					side_x - .13,
					side_x + .13,
					.8,
					2.85,
					"accent%d" % (index % 5),
					false
				)
			# An accent wall behind the bed uses one of five reused palettes.
			var mirror := -1.0 if SPEC.recipe(floor_index, index)["layout"] % 2 else 1.0
			KIT._wall(
				room,
				Vector3(-2.998 * mirror, 0, 4),
				-mirror * PI / 2,
				-3.6,
				3.6,
				.25,
				2.5,
				"accent%d" % (index % 5),
				false,
				true
			)
	var ceiling := StandardMaterial3D.new()
	ceiling.albedo_color = Color("c8bfaa")
	ceiling.roughness = 1
	var materials: Dictionary[String, Material] = {
		"floor": _material(CARPET, SPEC.COLORS[floor_index].darkened(.12)),
		"wall": _material(WALLPAPER, Color("cabda6").lerp(SPEC.COLORS[floor_index], .25)),
		"roof": ceiling,
		"trim": _material(WOOD, Color("b58d51")),
	}
	for i: int in range(5):
		materials["accent%d" % i] = _material(WALLPAPER, SPEC.recipe(floor_index, i)["accent"])
	SHELL.rebuild(root, materials)
	root.set_meta("guest_rooms", guests)
	root.set_meta("floor_index", floor_index)
	if furnished:
		var furniture := FURNITURE.new(root)
		furniture.lobby(lobby, floor_index)
		for room: Node3D in guests:
			furniture.guest(room, room.get_meta("recipe"), int(room.get_meta("room_index")) / 4)
		furniture.finish()
		_presentation(root, floor_index)
	return root


static func _join(root: Node3D, from: Node3D, exit: String, to: Node3D, entry: String) -> void:
	var a := from.get_node(exit) as ProceduralSocketAttachment
	var b := to.get_node(entry) as ProceduralSocketAttachment
	var id := "%s-%s-%s-%s" % [from.name, exit, to.name, entry]
	var errors := ProceduralSocketAttachment.attach(a, b, id)
	if not errors.is_empty():
		push_error("Hotel socket join %s failed: %s" % [id, ", ".join(errors)])
		return
	var joins: Array = root.get_meta("joins", [])
	joins.append({"from": a, "to": b})
	root.set_meta("joins", joins)


static func _material(texture: Texture2D, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = color
	material.roughness = 1
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(.5, .5, .5)
	return material


static func _presentation(root: Node3D, floor_index: int) -> void:
	for z: float in [5.0, 18.0, 36.0, 54.0, 69.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(0, 2.85, z)
		light.light_color = Color("ffd6a1")
		light.light_energy = 1.0
		light.omni_range = 10
		light.shadow_enabled = false
		root.add_child(light)
	var label := Label3D.new()
	label.name = "FloorIdentity"
	label.position = Vector3(0, 2.8, .08)
	label.text = (
		"FLOOR %d · %s\nROOMS %d–%d"
		% [
			floor_index + 1,
			SPEC.THEMES[floor_index],
			SPEC.room_number(floor_index, 0),
			SPEC.room_number(floor_index, 19)
		]
	)
	label.font_size = 32
	label.pixel_size = .005
	label.modulate = Color("f0d295")
	root.add_child(label)
