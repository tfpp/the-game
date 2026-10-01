extends RefCounted
## Sector-sized MultiMeshes share prop geometry; only the current floor is built.

const PROPS := {
	"bed": preload("res://features/hotel_props/props/single_bed.tscn"),
	"radiator": preload("res://features/hotel_props/props/radiator.tscn"),
	"bedside": preload("res://features/hotel_props/props/bedside_table.tscn"),
	"desk": preload("res://features/hotel_props/props/writing_desk.tscn"),
	"chair": preload("res://features/hotel_props/props/desk_chair.tscn"),
	"wardrobe": preload("res://features/hotel_props/props/wardrobe.tscn"),
	"armchair": preload("res://features/hotel_props/props/armchair.tscn"),
	"sofa": preload("res://features/hotel_props/props/two_seat_sofa.tscn"),
	"coffee": preload("res://features/hotel_props/props/coffee_table.tscn"),
	"phone": preload("res://features/hotel_props/props/rotary_phone.tscn"),
	"radio": preload("res://features/hotel_props/props/bedside_radio.tscn"),
	"clock": preload("res://features/hotel_props/props/alarm_clock.tscn"),
	"lamp": preload("res://features/hotel_props/props/table_lamp.tscn"),
	"floor_lamp": preload("res://features/hotel_props/props/floor_lamp.tscn"),
	"television": preload("res://features/hotel_props/props/crt_television.tscn"),
	"suitcase": preload("res://features/hotel_props/props/vintage_suitcase.tscn"),
	"rack": preload("res://features/hotel_props/props/folding_luggage_rack.tscn"),
	"fan": preload("res://features/hotel_props/props/standing_fan.tscn"),
	"plant": preload("res://features/hotel_props/props/potted_plant.tscn"),
	"art": preload("res://features/hotel_props/props/framed_art.tscn"),
	"mirror": preload("res://features/hotel_props/props/wall_mirror.tscn"),
	"bin": preload("res://features/hotel_props/props/waste_bin.tscn"),
	"counter": preload("res://features/hotel_props/props/reception_counter.tscn"),
	"cubby": preload("res://features/hotel_props/props/key_cubby.tscn"),
	"bell": preload("res://features/hotel_props/props/service_bell.tscn"),
	"register": preload("res://features/hotel_props/props/guest_register.tscn"),
	"cart": preload("res://features/hotel_props/props/cleaning_cart.tscn"),
	"service": preload("res://features/hotel_props/props/room_service_cart.tscn"),
	"towels": preload("res://features/hotel_props/props/towel_stack.tscn"),
	"cup": preload("res://features/hotel_props/props/coffee_cup.tscn"),
}
static var _data: Dictionary[String, Dictionary] = {}
var _root: Node3D
var _batches: Dictionary[String, Array] = {}
var _count := 0


func _init(root: Node3D) -> void:
	_root = root


static func data(id: String) -> Dictionary:
	if not _data.has(id):
		var prop := (PROPS[id] as PackedScene).instantiate() as Node3D
		var model := prop.get_node("Model") as MeshInstance3D
		var collider := prop.get_node("Collider") as CollisionShape3D
		var material := model.material_override.duplicate() as StandardMaterial3D
		material.vertex_color_use_as_albedo = true
		_data[id] = {
			"mesh": model.mesh,
			"material": material,
			"shape": collider.shape,
			"collision_transform": collider.transform
		}
		prop.free()
	return _data[id]


func add_prop(
	room: Node3D,
	id: String,
	point: Vector3,
	yaw: float = 0,
	color: Color = Color.WHITE,
	sector: int = 0,
	solid: bool = true
) -> void:
	var local := Transform3D(Basis(Vector3.UP, yaw), point)
	var pose := _root.global_transform.affine_inverse() * room.global_transform * local
	var key := "%d:%s" % [sector, id]
	if not _batches.has(key):
		_batches[key] = []
	_batches[key].append({"transform": pose, "color": color})
	_count += 1
	var placements: Array = room.get_meta("furniture_layout", [])
	placements.append({"id": id, "transform": local, "solid": solid})
	room.set_meta("furniture_layout", placements)
	if solid:
		var body := room.get_node_or_null("FurnitureCollision") as StaticBody3D
		if body == null:
			body = StaticBody3D.new()
			body.name = "FurnitureCollision"
			room.add_child(body)
		var shape := CollisionShape3D.new()
		shape.shape = data(id)["shape"]
		shape.transform = local * data(id)["collision_transform"]
		body.add_child(shape)


func guest(room: Node3D, recipe: Dictionary, sector: int) -> void:
	# Five authored arrangements share wall anchors; variations never scatter furniture.
	var mirror := -1.0 if recipe["layout"] % 2 else 1.0
	var bed_z := 3.35
	var bed := Vector3(-1.92 * mirror, 0, bed_z)
	add_prop(room, "bed", bed, mirror * PI / 2, recipe["accent"], sector)
	if recipe["twin"]:
		add_prop(room, "bed", Vector3(bed.x, 0, 5.15), mirror * PI / 2, recipe["accent"], sector)
	var bedside := Vector3(-2.62 * mirror, 0, 2.45)
	add_prop(room, "bedside", bedside, mirror * PI / 2, Color.WHITE, sector)
	add_prop(room, "lamp", bedside + Vector3(0, .665, -.14), 0, Color.WHITE, sector, false)
	var item: String = ["phone", "radio", "clock"][recipe["decor"] % 3]
	add_prop(room, item, bedside + Vector3(0, .665, .13), 0, Color.WHITE, sector, false)
	add_prop(
		room, "wardrobe", Vector3(2.62 * mirror, 0, 1.15), -mirror * PI / 2, Color.WHITE, sector
	)
	var desk := Vector3(2.66 * mirror, 0, 4.2 + (recipe["layout"] / 2) * .25)
	add_prop(room, "desk", desk, -mirror * PI / 2, Color.WHITE, sector)
	add_prop(
		room, "chair", desk + Vector3(-.85 * mirror, 0, 0), mirror * PI / 2, Color.WHITE, sector
	)
	add_prop(
		room,
		"television" if recipe["layout"] < 3 else "towels",
		desk + Vector3(0, .803, 0),
		-mirror * PI / 2,
		Color.WHITE,
		sector,
		false
	)
	add_prop(room, "bin", Vector3(2.65 * mirror, 0, 3.05), 0, Color.WHITE, sector)
	add_prop(room, "radiator", Vector3(0, 0, 7.86), PI, Color.WHITE, sector)
	add_prop(room, "rack", Vector3(-2.5 * mirror, 0, 7.15), 0, Color.WHITE, sector)
	add_prop(room, "suitcase", Vector3(-2.5 * mirror, .495, 7.15), 0, Color.WHITE, sector, false)
	if not recipe["twin"]:
		add_prop(
			room, "armchair", Vector3(-2.52 * mirror, 0, 5.7), mirror * PI / 2, Color.WHITE, sector
		)
		add_prop(room, "coffee", Vector3(-1.55 * mirror, 0, 5.7), PI / 2, Color.WHITE, sector)
		add_prop(room, "cup", Vector3(-1.55 * mirror, .45, 5.7), 0, Color.WHITE, sector, false)
	add_prop(
		room,
		"art",
		Vector3(-2.94 * mirror, 1.75, bed_z),
		mirror * PI / 2,
		Color.WHITE,
		sector,
		false
	)
	add_prop(
		room,
		"mirror",
		Vector3(2.94 * mirror, 1.45, 1.15),
		-mirror * PI / 2,
		Color.WHITE,
		sector,
		false
	)
	if recipe["decor"] in [1, 4, 6]:
		add_prop(
			room,
			"floor_lamp" if recipe["decor"] == 4 else "plant",
			Vector3(2.42 * mirror, 0, 7.1),
			0,
			Color.WHITE,
			sector
		)


func lobby(room: Node3D, floor_index: int) -> void:
	# Reception has a staff side, a waiting group, and an open route to the lift.
	if floor_index == 0:
		add_prop(room, "counter", Vector3(-6, 0, 2), 0, Color.WHITE, 5)
		add_prop(room, "cubby", Vector3(-6, 1.1, .12), 0, Color.WHITE, 5, false)
		add_prop(room, "bell", Vector3(-5.2, 1.1075, 2.18), 0, Color.WHITE, 5, false)
		add_prop(room, "register", Vector3(-6.35, 1.1075, 2.1), 0, Color.WHITE, 5, false)
		add_prop(room, "phone", Vector3(-6.85, 1.1075, 1.92), 0, Color.WHITE, 5, false)
	else:
		add_prop(room, "desk", Vector3(-6, 0, .4), 0, Color.WHITE, 5)
		add_prop(room, "chair", Vector3(-6, 0, 1.25), PI, Color.WHITE, 5)
		add_prop(room, "radio", Vector3(-6, .803, .4), 0, Color.WHITE, 5, false)
	for side: int in [-1, 1]:
		var sofa := Vector3(side * 8.9, 0, 8.6)
		var table := Vector3(side * 7.35, 0, 8.6)
		add_prop(room, "sofa", sofa, -side * PI / 2, Color.WHITE, 5)
		add_prop(room, "coffee", table, PI / 2, Color.WHITE, 5)
		add_prop(room, "cup", table + Vector3(0, .45, .12), 0, Color.WHITE, 5, false)
		add_prop(room, "armchair", Vector3(side * 6, 0, 8.6), side * PI / 2, Color.WHITE, 5)
		add_prop(room, "plant", Vector3(side * 8.85, 0, 10.85), 0, Color.WHITE, 5)
	add_prop(
		room,
		"cart" if floor_index % 2 else "service",
		Vector3(-8.7, 0, 5.75),
		PI / 2,
		Color.WHITE,
		5
	)


func finish() -> void:
	var parent := Node3D.new()
	parent.name = "BatchedFurniture"
	_root.add_child(parent)
	for key: String in _batches:
		var parts := key.split(":")
		var sector := int(parts[0])
		var id: String = parts[1]
		var origin := Vector3(0, 0, 18 + sector * 12 if sector < 5 else 6)
		var info := data(id)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_colors = true
		multi.mesh = info["mesh"]
		multi.instance_count = _batches[key].size()
		for i: int in multi.instance_count:
			var pose: Transform3D = _batches[key][i]["transform"]
			pose.origin -= origin
			multi.set_instance_transform(i, pose)
			multi.set_instance_color(i, _batches[key][i]["color"])
		var node := MultiMeshInstance3D.new()
		node.name = "%s_Sector%d" % [id, sector]
		node.position = origin
		node.multimesh = multi
		node.material_override = info["material"]
		node.visibility_range_end = 32
		node.visibility_range_end_margin = 3
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)
	_root.set_meta("furniture_instances", _count)
	_root.set_meta("furniture_batches", _batches.size())
