extends Node
## Bake saved GridMaps and separate server collision from the painted R44.

const ROOT := "res://features/metro/"
const GRAFFITI_TAGS := 8
## Station nodes a passing platform copy omits: the ride draws its own track.
const STATION_ONLY: Array[String] = [
	"Train",
	"TrainCollision",
	"RailSound",
	"TrackBed",
	"Rails",
	"TrackExitSteps",
	"TunnelMouths",
	"TunnelRoof",
	"TunnelDarkness"
]
# Passing-tunnel layout in scenery coordinates: the departure platform is centred
# on z = 0 and the arrival platform on z = -SPACING; the train heads to -Z.
## -X wall cells (from, to) replaced by columns beside a parallel track.
const COLUMNS := Vector2i(-110, -150)
## Refuge niches (z, wall x).
const NICHES: Array[Vector2i] = [
	Vector2i(-92, -3), Vector2i(-128, 3), Vector2i(-186, -3), Vector2i(-214, 3)
]
## Graffiti (wall x, z, atlas tag).
const TAGS: Array[Vector3i] = [
	Vector3i(3, -80, 0),
	Vector3i(-3, -97, 3),
	Vector3i(3, -115, 2),
	Vector3i(-9, -130, 6),
	Vector3i(3, -140, 4),
	Vector3i(-3, -163, 6),
	Vector3i(3, -176, 5),
	Vector3i(-3, -197, 7),
	Vector3i(3, -206, 1),
	Vector3i(-3, -222, 0)
]
const SIGNALS: Array[float] = [-101.0, -165.0, -226.0]
var library: MeshLibrary
var _id := 0
## The station kit, reused (without collision) for the platforms a ride passes.
var _station_library: MeshLibrary
var _station_items: Dictionary[String, int] = {}
var _passing_materials: Dictionary[Material, Material] = {}


func _ready() -> void:
	call_deferred("build")


func build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + "rooms"))
	_split_train()
	_build_elevator()
	_build_station()
	_build_transit()
	_build_feature()
	print("METRO_REALM_BUILD PASS")
	get_tree().quit()


func own(node: Node, owner: Node) -> void:
	node.scene_file_path = ""
	for child: Node in node.get_children():
		child.owner = owner
		own(child, owner)


func save(node: Node, path: String) -> void:
	own(node, node)
	var scene := PackedScene.new()
	assert(scene.pack(node) == OK)
	assert(ResourceSaver.save(scene, path) == OK)


func _split_train() -> void:
	var source := load(ROOT + "r44_five_car_set.tscn") as PackedScene
	var visual := source.instantiate() as Node3D
	for node: Node in visual.find_children("*", "CollisionShape3D", true, false):
		node.free()
	for node: GridMap in visual.find_children("*", "GridMap", true, false):
		node.collision_layer = 0
		node.collision_mask = 0
	for node: CollisionObject3D in visual.find_children("*", "CollisionObject3D", true, false):
		node.collision_layer = 0
		node.collision_mask = 0
	for node: Node in visual.find_children("CabinLight*", "OmniLight3D", true, false):
		if not node.name.ends_with("6"):
			node.free()
	save(visual, ROOT + "train_visual.tscn")
	visual.free()
	var collision := source.instantiate() as Node3D
	for node: Node in collision.find_children("*", "MeshInstance3D", true, false):
		node.free()
	for node: Node in collision.find_children("*", "Light3D", true, false):
		node.free()
	var shapes := (load(ROOT + "cabin_tiles.tres") as MeshLibrary).duplicate() as MeshLibrary
	for item: int in shapes.get_item_list():
		shapes.set_item_mesh(item, null)
	ResourceSaver.save(shapes, ROOT + "cabin_collision.tres")
	shapes.take_over_path(ROOT + "cabin_collision.tres")
	for node: GridMap in collision.find_children("*", "GridMap", true, false):
		node.mesh_library = shapes
	save(collision, ROOT + "train_collision.tscn")
	collision.free()


func tile(size: Vector3, center: Vector3, material: Material, solid: bool = true) -> int:
	var id := _id
	_id += 1
	library.create_item(id)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	library.set_item_mesh(id, mesh)
	library.set_item_mesh_transform(id, Transform3D(Basis.IDENTITY, center))
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		library.set_item_shapes(id, [shape, Transform3D(Basis.IDENTITY, center)])
	return id


func grid(parent: Node3D, label: String) -> GridMap:
	var result := GridMap.new()
	result.name = label
	result.mesh_library = library
	result.cell_size = Vector3.ONE
	result.cell_center_x = false
	result.cell_center_y = false
	result.cell_center_z = false
	result.cell_octant_size = 8
	parent.add_child(result)
	return result


func add_sign(parent: Node3D, text: String, at: Vector3, yaw: float, size: float) -> void:
	var board := SignBoard.new()
	board.text = text
	board.position = at
	board.rotation.y = yaw
	board.letter_height = size
	parent.add_child(board)


func _build_elevator() -> void:
	library = MeshLibrary.new()
	_id = 0
	var steel := load(ROOT + "painted_steel.tres") as Material
	var floor_id := tile(Vector3(3.2, 0.12, 3.2), Vector3(0, -0.06, -1.6), steel)
	var wall_id := tile(Vector3(0.12, 2.5, 3.2), Vector3(0, 1.25, -1.6), steel)
	var back_id := tile(Vector3(3.2, 2.5, 0.12), Vector3(0, 1.25, -3.14), steel)
	var roof_id := tile(Vector3(3.2, 0.1, 3.2), Vector3(0, 2.5, -1.6), steel)
	ResourceSaver.save(library, ROOT + "access_tiles.tres")
	library.take_over_path(ROOT + "access_tiles.tres")
	var cab := (load("res://features/elevator/elevator_cab.tscn") as PackedScene).instantiate()
	cab.set_script(load(ROOT + "metro_elevator.gd"))
	for button_path: String in ["Car/CabButton", "Car/HallButton"]:
		cab.get_node(button_path).set_script(load(ROOT + "metro_button.gd"))
	var shell := grid(cab, "Cabin")
	shell.set_cell_item(Vector3i(0, 0, 0), floor_id)
	shell.set_cell_item(Vector3i(0, 1, 0), roof_id)
	shell.set_cell_item(Vector3i(0, 2, 0), back_id)
	# Independent GridMaps avoid changing mesh transforms with overlapping cells.
	shell.clear()
	for data: Array in [
		[floor_id, Vector3.ZERO],
		[roof_id, Vector3.ZERO],
		[wall_id, Vector3(-1.54, 0, 0)],
		[wall_id, Vector3(1.54, 0, 0)],
		[back_id, Vector3.ZERO]
	]:
		var part := grid(cab, "Shell%d" % cab.get_child_count())
		part.position = data[1]
		part.set_cell_item(Vector3i.ZERO, data[0])
	(cab.get_node("Car/Doors") as Node3D).scale.y = 0.78
	(cab.get_node("Car/Sign") as Node3D).position.y = 2.43
	(cab.get_node("Car/Sign") as SignBoard).letter_height = 0.095
	(cab.get_node("Car/Indicator") as Node3D).position.y = 2.22
	(cab.get_node("Car/HallLamp") as Node3D).position.y = 2.25
	(cab.get_node("Car/CabLamp") as Node3D).position.y = 2.22
	(cab.get_node("Car/CabIndicator") as Node3D).position.y = 2.22
	(cab.get_node("Car/CabLight") as Node3D).position.y = 2.25
	(cab.get_node("Car/HallButton") as Node3D).position.x = 1.7
	save(cab, ROOT + "access_elevator.tscn")
	cab.free()


func _build_station() -> void:
	library = MeshLibrary.new()
	_id = 0
	var concrete := _surface(
		"res://assets/street_props/surfaces/concrete_wall.png", Color("a4ac9c"), 0.5
	)
	var paving := _surface(
		"res://assets/street_props/surfaces/sidewalk_slabs.png", Color("8f9389"), 0.75
	)
	var plaster := _surface(
		"res://assets/street_props/surfaces/painted_concrete.png", Color("bdc6af"), 0.5
	)
	var steel := load(ROOT + "painted_steel.tres") as Material
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color("bbaa59")
	yellow.roughness = 1
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("161d1d")
	var floor_id := tile(Vector3(2, 0.3, 2), Vector3(0, 1.05, 0), paving)
	var wall_id := tile(Vector3(0.3, 5.6, 2), Vector3(0, 2.8, 0), concrete)
	var ceiling_id := tile(Vector3(2, 0.25, 2), Vector3(0, 5.6, 0), plaster)
	var stripe_id := tile(Vector3(0.18, 0.018, 2), Vector3(0, 1.21, 0), yellow, false)
	var column_id := tile(Vector3(0.45, 4.4, 0.45), Vector3(0, 3.4, 0), steel)
	var rail_id := tile(Vector3(0.10, 0.12, 2), Vector3(0, 0.08, 0), steel, false)
	var track_id := tile(Vector3(2, 0.2, 2), Vector3(0, -0.1, 0), dark)
	var panel_id := tile(Vector3(0.05, 0.6, 2), Vector3(0, 3.5, 0), steel, false)
	var tunnel_wall := tile(Vector3(0.3, 4.6, 2), Vector3(0, 2.3, 0), dark)
	var tunnel_roof := tile(Vector3(6, 0.3, 2), Vector3(0, 4.6, 0), dark)
	var tunnel_end := tile(Vector3(6, 4.6, 0.2), Vector3(0, 2.3, 0), dark)
	var tube_id := tile(
		Vector3(0.18, 0.08, 4), Vector3(0, 5.25, 0), load(ROOT + "lamp.tres"), false
	)
	var beam_id := tile(Vector3(24, 0.22, 0.3), Vector3(8, 5.4, 0), steel, false)
	var board_id := tile(Vector3(5, 1.4, 0.12), Vector3(4.5, 4.4, 0), dark, false)
	var step_ids: Array[int] = []
	for step: int in 3:
		var height := (step + 1) * 0.4
		step_ids.append(tile(Vector3(1, height, 2), Vector3(0, height / 2, 0), paving))
	ResourceSaver.save(library, ROOT + "station_tiles.tres")
	library.take_over_path(ROOT + "station_tiles.tres")
	_station_library = library
	_station_items = {"track": track_id, "rail": rail_id, "roof": tunnel_roof, "end": tunnel_end}
	var room := Node3D.new()
	room.name = "StationInterior"
	var floor_grid := grid(room, "Platform")
	var walls := grid(room, "Walls")
	var ceiling := grid(room, "Ceiling")
	var edge := grid(room, "YellowLine")
	var columns := grid(room, "Columns")
	var tracks := grid(room, "TrackBed")
	var rail := grid(room, "Rails")
	var band := grid(room, "WallBand")
	var tubes := grid(room, "FluorescentTubes")
	var beams := grid(room, "CeilingBeams")
	var stairs := grid(room, "TrackExitSteps")
	for z: int in [-63, 63]:
		for step: int in 3:
			stairs.set_cell_item(Vector3i(step, 0, z), step_ids[step])
	for z: int in range(-66, 67, 2):
		for x: int in range(3, 20, 2):
			floor_grid.set_cell_item(Vector3i(x, 0, z), floor_id)
		for x: int in range(-3, 22, 2):
			ceiling.set_cell_item(Vector3i(x, 0, z), ceiling_id)
		for x: int in [-4, 22]:
			walls.set_cell_item(Vector3i(x, 0, z), wall_id)
		edge.set_cell_item(Vector3i(2, 0, z), stripe_id)
		for x: int in [-1, 1]:
			tracks.set_cell_item(Vector3i(x, 0, z), track_id)
			rail.set_cell_item(Vector3i(x, 0, z), rail_id)
		band.set_cell_item(Vector3i(-3, 0, z), panel_id)
	for z: int in range(-60, 61, 12):
		columns.set_cell_item(Vector3i(7, 0, z), column_id)
		beams.set_cell_item(Vector3i(0, 0, z), beam_id)
		for x: int in [5, 15]:
			tubes.set_cell_item(Vector3i(x, 0, z), tube_id)
		add_sign(room, "METRO   /   LOOP LINE", Vector3(-3.7, 3.65, z), PI / 2, 0.20)
		var light := OmniLight3D.new()
		light.position = Vector3(5, 4.4, z)
		light.omni_range = 10
		light.light_energy = 0.8
		light.shadow_enabled = false
		room.add_child(light)
	for z: int in [-42, -30, 30, 42]:
		var bench := (
			(
				(load("res://features/street_props/props/bus_stop_bench.tscn") as PackedScene)
				. instantiate()
			)
			as Node3D
		)
		bench.position = Vector3(11, 1.2, z)
		bench.rotation.y = -PI / 2
		room.add_child(bench)
	# End walls close platform access to tunnels; the track opening stays visible.
	var ends := grid(room, "PlatformEnds")
	for z: int in [-67, 67]:
		for x: int in range(3, 22, 2):
			ends.set_cell_item(
				Vector3i(x, 0, z),
				wall_id,
				ends.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
			)
	var tunnel_sides := grid(room, "TunnelMouths")
	var tunnel_top := grid(room, "TunnelRoof")
	var tunnel_back := grid(room, "TunnelDarkness")
	for side: int in [-1, 1]:
		for z: int in range(68, 91, 2):
			for x: int in [-1, 1]:
				tracks.set_cell_item(Vector3i(x, 0, z * side), track_id)
			for x: int in [-3, 3]:
				tunnel_sides.set_cell_item(Vector3i(x, 0, z * side), tunnel_wall)
			tunnel_top.set_cell_item(Vector3i(0, 0, z * side), tunnel_roof)
		tunnel_back.set_cell_item(Vector3i(0, 0, 91 * side), tunnel_end)
	_add_train(room)
	var board_panels := grid(room, "DepartureBoards")
	for z: int in [-48, -24, 0, 24, 48]:
		board_panels.set_cell_item(Vector3i(0, 0, z), board_id)
		for side: int in [-1, 1]:
			var board := Label3D.new()
			board.name = "Board" if z == 0 and side == 1 else "Board%d_%d" % [z, side]
			board.position = Vector3(4.5, 4.4, z + side * 0.07)
			board.rotation.y = PI if side == -1 else 0.0
			board.double_sided = false
			board.font_size = 48
			board.pixel_size = 0.008
			board.modulate = Color("ddd4ab")
			room.add_child(board)
	add_sign(
		room,
		"CROWN > MARKET > WORKS > RESIDENCES\nEXIT ELEVATORS  >>>",
		Vector3(10, 3.7, 0),
		-PI / 2,
		0.18
	)
	var audio := AudioStreamPlayer3D.new()
	audio.name = "RailSound"
	audio.position = Vector3(0, 2, 0)
	audio.max_distance = 100
	room.add_child(audio)
	save(room, ROOT + "rooms/station.tscn")
	# Collision-only structure used for server weapon rays and arrival validation.
	var server := Node3D.new()
	for child: Node in room.get_children():
		if child is GridMap:
			var copy := child.duplicate() as GridMap
			var shapes := library.duplicate() as MeshLibrary
			for id: int in shapes.get_item_list():
				shapes.set_item_mesh(id, null)
			copy.mesh_library = shapes
			server.add_child(copy)
		elif child is StaticBody3D:
			var copy := child.duplicate() as Node3D
			for mesh: Node in copy.find_children("*", "MeshInstance3D", true, false):
				mesh.free()
			server.add_child(copy)
	save(server, ROOT + "station_collision.tscn")
	server.free()
	room.free()


func _surface(path: String, tint: Color, scale: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://features/casino_hub/materials/retro_surface.gdshader")
	material.set_shader_parameter("albedo_texture", load(path))
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("texture_scale", scale)
	return material


func _add_train(room: Node3D) -> void:
	var visual := (load(ROOT + "train_visual.tscn") as PackedScene).instantiate()
	visual.name = "Train"
	room.add_child(visual)
	var collision := (load(ROOT + "train_collision.tscn") as PackedScene).instantiate()
	collision.name = "TrainCollision"
	room.add_child(collision)


func _build_transit() -> void:
	var room := Node3D.new()
	room.name = "TransitInterior"
	_add_train(room)
	var tiles := _tunnel_library()
	ResourceSaver.save(library, ROOT + "tunnel_tiles.tres")
	library.take_over_path(ROOT + "tunnel_tiles.tres")
	# The compartment never moves. MetroZone slides this along +Z by the distance
	# covered, so the platform left behind and the next one pass the windows.
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	room.add_child(scenery)
	scenery.add_child(_platform_copy("Departure", 0))
	scenery.add_child(_platform_copy("Arrival", -int(MetroRules.SPACING)))
	_add_tunnel(scenery, tiles)
	var board := Label3D.new()
	board.name = "Board"
	board.position = Vector3(0, 3.15, 10.6)
	board.rotation.y = PI
	board.font_size = 30
	board.pixel_size = 0.008
	room.add_child(board)
	var audio := AudioStreamPlayer3D.new()
	audio.name = "RailSound"
	audio.position = Vector3(0, 2, 0)
	audio.max_distance = 150
	room.add_child(audio)
	save(room, ROOT + "rooms/transit.tscn")
	room.free()


## Station tiles keep their ids but lose collision and scroll with the ride;
## tunnel dressing is appended to the same library. Wall offsets are for the +X
## lining face (x = 2.85); a half turn mirrors them onto the -X wall.
func _tunnel_library() -> Dictionary[String, int]:
	library = _station_library.duplicate() as MeshLibrary
	_id = 0
	for item: int in library.get_item_list():
		library.set_item_shapes(item, [])
		var mesh := library.get_item_mesh(item).duplicate() as PrimitiveMesh
		mesh.material = _passing(mesh.material)
		library.set_item_mesh(item, mesh)
		_id = maxi(_id, item + 1)
	var concrete := load("res://assets/street_props/surfaces/concrete_wall.png") as Texture2D
	var plaster := load("res://assets/street_props/surfaces/peeling_plaster.png") as Texture2D
	var gravel := load("res://assets/street_props/surfaces/gravel.png") as Texture2D
	var steel := load("res://assets/street_props/surfaces/rusted_steel.png") as Texture2D
	var lining := _moving_surface(concrete, Color("8f948a"), 0.5)
	var stained := _moving_surface(plaster, Color("717568"), 0.5)
	var deep := _moving_surface(concrete, Color("737a70"), 0.5)
	var ballast := _moving_surface(gravel, Color("57534b"), 1.0)
	var rust := _moving_surface(steel, Color("968c82"), 1.0)
	var rubber := _flat(Color("1b1c1d"))
	var tiles: Dictionary[String, int] = {}
	tiles.merge(_station_items)
	tiles["lining"] = tile(Vector3(0.3, 4.6, 2), Vector3(0, 2.3, 0), lining, false)
	tiles["stained"] = tile(Vector3(0.3, 4.6, 2), Vector3(0, 2.3, 0), stained, false)
	tiles["deep"] = tile(Vector3(0.3, 4.6, 2), Vector3(0, 2.3, 0), deep, false)
	tiles["invert"] = tile(Vector3(6, 0.2, 2), Vector3(0, -0.15, 0), ballast, false)
	tiles["column"] = tile(Vector3(0.3, 4.6, 0.3), Vector3(0, 2.3, 0), rust, false)
	tiles["lamp"] = tile(
		Vector3(0.16, 0.16, 0.32), Vector3(-0.23, 2.75, 0), _flat(Color("ffd9a0"), 3.0), false
	)
	tiles["cables"] = tile(Vector3(0.07, 0.24, 2), Vector3(-0.185, 2.05, 0), rubber, false)
	tiles["high_cables"] = tile(Vector3(0.07, 0.24, 2), Vector3(-0.185, 3.7, 0), rubber, false)
	tiles["bracket"] = tile(Vector3(0.24, 0.05, 0.08), Vector3(-0.27, 1.91, 0), rust, false)
	tiles["high_bracket"] = tile(Vector3(0.24, 0.05, 0.08), Vector3(-0.27, 3.56, 0), rust, false)
	# Refuge niche with a blue emergency-alarm lamp, cut 0.75 m into the lining.
	tiles["niche"] = _compound(
		[
			[Vector3(0.3, 2.4, 2), Vector3(0.75, 1.2, 0)],
			[Vector3(0.75, 2.4, 0.15), Vector3(0.225, 1.2, -0.925)],
			[Vector3(0.75, 2.4, 0.15), Vector3(0.225, 1.2, 0.925)],
			[Vector3(0.75, 0.1, 2), Vector3(0.225, 2.45, 0)],
			[Vector3(0.75, 0.1, 1.7), Vector3(0.225, -0.05, 0)],
			[Vector3(0.3, 2.2, 2), Vector3(0, 3.5, 0)]
		],
		lining
	)
	tiles["alarm"] = tile(
		Vector3(0.12, 0.12, 0.12), Vector3(0.5, 2.25, 0), _flat(Color("3f6bff"), 3.0), false
	)
	# Closes the step between a station's back wall (x = -4) and the tunnel lining.
	tiles["cap"] = tile(Vector3(1, 5.6, 0.3), Vector3(-0.5, 2.8, 0), lining, false)
	tiles["header"] = tile(Vector3(6, 1, 0.3), Vector3(0, 5.1, 0), lining, false)
	var widths: Array[float] = [3.0, 3.0, 2.8, 1.9, 2.6, 2.2, 3.0, 1.9]
	for tag: int in GRAFFITI_TAGS:
		tiles["tag%d" % tag] = _graffiti(tag, widths[tag])
	return tiles


## The saved station shell, minus the train, track and tunnel mouths, which the
## passing tunnel draws continuously. Benches keep only their painted model.
func _platform_copy(label: String, z: int) -> Node3D:
	var scene := (
		ResourceLoader.load(ROOT + "rooms/station.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
		as PackedScene
	)
	var copy := scene.instantiate() as Node3D
	copy.name = label
	copy.position.z = z
	var benches := 0
	for child: Node in copy.get_children():
		if String(child.name) in STATION_ONLY:
			child.free()
		elif child is GridMap:
			(child as GridMap).mesh_library = library
		elif child is StaticBody3D:
			var model := child.get_node("Model") as Node3D
			child.remove_child(model)
			model.owner = null
			model.transform = (child as Node3D).transform * model.transform
			model.name = "Bench%d" % benches
			benches += 1
			copy.add_child(model)
			child.free()
	return copy


func _add_tunnel(scenery: Node3D, tiles: Dictionary[String, int]) -> void:
	var tunnel := Node3D.new()
	tunnel.name = "Tunnel"
	scenery.add_child(tunnel)
	var spacing := int(MetroRules.SPACING)
	var lining := grid(tunnel, "Lining")
	var cables := grid(tunnel, "Cables")
	var brackets := grid(tunnel, "Brackets")
	var columns := grid(tunnel, "Columns")
	var portals := grid(tunnel, "Portals")
	var flip := lining.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
	var turn := lining.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI / 2))
	_lay_track(tunnel, tiles, spacing)
	for z: int in range(90, -spacing - 91, -2):
		if absi(z) <= 66 or absi(z + spacing) <= 66:
			continue
		for x: int in [-3, 3]:
			var face := 0 if x > 0 else flip
			if x < 0 and z <= COLUMNS.x and z >= COLUMNS.y:
				columns.set_cell_item(Vector3i(x, 0, z), tiles["column"])
				continue
			var niche := Vector2i(z, x) in NICHES
			var item := "niche" if niche else "lining"
			if not niche and posmod(z * 13 + x * 29, 17) < 5:
				item = "stained"
			lining.set_cell_item(Vector3i(x, 0, z), tiles[item], face)
			if niche:
				continue
			var low := x < 0
			cables.set_cell_item(Vector3i(x, 0, z), tiles["cables" if low else "high_cables"], face)
			if posmod(z, 4) == 0:
				brackets.set_cell_item(
					Vector3i(x, 0, z), tiles["bracket" if low else "high_bracket"], face
				)
	# Beside the columns an older parallel track, dark between its own lamps.
	for z: int in range(COLUMNS.x, COLUMNS.y - 1, -2):
		lining.set_cell_item(Vector3i(-9, 0, z), tiles["deep"], flip)
	for z: int in [COLUMNS.x + 2, COLUMNS.y - 2]:
		for x: int in [-8, -6, -4]:
			lining.set_cell_item(Vector3i(x, 0, z), tiles["deep"], turn)
	for z: int in [67, -67, 67 - spacing, -67 - spacing]:
		portals.set_cell_item(Vector3i(-3, 0, z), tiles["cap"])
		portals.set_cell_item(Vector3i(0, 0, z), tiles["header"])
	for z: int in [92, -spacing - 92]:
		portals.set_cell_item(Vector3i(0, 0, z), tiles["end"])
	_dress_tunnel(tunnel, tiles, flip)


## Ballast, track and roof run the whole strip, under both platform copies too.
func _lay_track(tunnel: Node3D, tiles: Dictionary[String, int], spacing: int) -> void:
	var bed := grid(tunnel, "TrackBed")
	var rails := grid(tunnel, "Rails")
	var invert := grid(tunnel, "Invert")
	var roof := grid(tunnel, "Roof")
	for z: int in range(90, -spacing - 91, -2):
		var platform := absi(z) <= 66 or absi(z + spacing) <= 66
		var tracks: Array[int] = [0]
		if z <= COLUMNS.x and z >= COLUMNS.y:
			tracks.append(-6)
		for centre: int in tracks:
			for x: int in [centre - 1, centre + 1]:
				bed.set_cell_item(Vector3i(x, 0, z), tiles["track"])
				rails.set_cell_item(Vector3i(x, 0, z), tiles["rail"])
			invert.set_cell_item(Vector3i(centre, 0, z), tiles["invert"])
			if not platform:
				roof.set_cell_item(Vector3i(centre, 0, z), tiles["roof"])


## Passing lamps, tags, signals and refuges: the cues that show distance.
func _dress_tunnel(tunnel: Node3D, tiles: Dictionary[String, int], flip: int) -> void:
	var lamps := grid(tunnel, "Lamps")
	var tags := grid(tunnel, "Graffiti")
	var alarms := grid(tunnel, "Alarms")
	# Window-height lamps alternate sides every 8 m; each pool of light also
	# sweeps through the cabin as it passes.
	var lamp := 0
	for z: int in range(-73, -233, -8):
		var x := 3 if lamp % 2 == 0 else -3
		lamp += 1
		if x < 0 and z <= COLUMNS.x and z >= COLUMNS.y:
			continue
		lamps.set_cell_item(Vector3i(x, 0, z), tiles["lamp"], 0 if x > 0 else flip)
		_lamp_light(tunnel, "Lamp%d" % lamp, Vector3(signf(x) * 2.6, 2.75, z), 4.8)
	# Lit far wall: the columns flicker past as silhouettes against it.
	for z: int in range(COLUMNS.x - 6, COLUMNS.y, -12):
		lamps.set_cell_item(Vector3i(-9, 0, z), tiles["lamp"], flip)
		_lamp_light(tunnel, "ParallelLamp%d" % -z, Vector3(-8.6, 2.75, z), 6.0)
	for spot: Vector3i in TAGS:
		tags.set_cell_item(
			Vector3i(spot.x, 0, spot.y), tiles["tag%d" % spot.z], 0 if spot.x > 0 else flip
		)
	for niche: Vector2i in NICHES:
		var x := niche.y
		alarms.set_cell_item(Vector3i(x, 0, niche.x), tiles["alarm"], 0 if x > 0 else flip)
		var exit := SignBoard.new()
		exit.text = "EXIT"
		exit.style = SignBoard.Style.NEON
		exit.neon_color = Color("49e07a")
		exit.letter_height = 0.1
		exit.position = Vector3(signf(x) * 2.85, 2.72, niche.x)
		exit.rotation.y = -signf(x) * PI / 2
		tunnel.add_child(exit)
	for index: int in SIGNALS.size():
		_signal(tunnel, "Signal%d" % index, SIGNALS[index])


func _lamp_light(parent: Node3D, label: String, at: Vector3, reach: float) -> void:
	var light := OmniLight3D.new()
	light.name = label
	light.position = at
	light.light_color = Color("ffd8a2")
	light.light_energy = 1.6
	light.omni_range = reach
	parent.add_child(light)


## A two-aspect block signal on the +X wall; MetroZone lights one lens.
func _signal(parent: Node3D, label: String, z: float) -> void:
	var head := Node3D.new()
	head.name = label
	head.position = Vector3(2.68, 2.8, z)
	parent.add_child(head)
	_box(head, "Housing", Vector3(0.26, 0.62, 0.24), Vector3.ZERO, _flat(Color("121414")))
	_box(
		head, "Stop", Vector3(0.05, 0.14, 0.14), Vector3(-0.14, 0.15, 0), _flat(Color("ff3a2a"), 3)
	)
	_box(
		head,
		"Clear",
		Vector3(0.05, 0.14, 0.14),
		Vector3(-0.14, -0.15, 0),
		_flat(Color("3aff7a"), 3)
	)


func _box(parent: Node3D, label: String, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = at
	parent.add_child(node)


## A spray-painted tag from the R44's own atlas, on the +X lining face.
func _graffiti(tag: int, width: float) -> int:
	var height := width * 27.0 / 59.0
	var low := Vector2(2.5 + (tag % 2) * 64, 2.5 + floorf(tag / 2.0) * 32) / 128.0
	var high := low + Vector2(59, 27) / 128.0
	var top := 2.45 + height * 0.5
	var bottom := 2.45 - height * 0.5
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[
			Vector3(-0.16, top, -width * 0.5),
			Vector3(-0.16, top, width * 0.5),
			Vector3(-0.16, bottom, width * 0.5),
			Vector3(-0.16, bottom, -width * 0.5)
		]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(
		[Vector3.LEFT, Vector3.LEFT, Vector3.LEFT, Vector3.LEFT]
	)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(
		[low, Vector2(high.x, low.y), high, Vector2(low.x, high.y)]
	)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, load(ROOT + "graffiti.tres"))
	return _item(mesh)


func _compound(parts: Array, material: Material) -> int:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part: Array in parts:
		var box := BoxMesh.new()
		box.size = part[0]
		builder.append_from(box, 0, Transform3D(Basis.IDENTITY, part[1]))
	var mesh := builder.commit()
	mesh.surface_set_material(0, material)
	return _item(mesh)


func _item(mesh: Mesh) -> int:
	var id := _id
	_id += 1
	library.create_item(id)
	library.set_item_mesh(id, mesh)
	return id


func _flat(color: Color, glow: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1
	if glow > 0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material


## retro_surface's look on scenery that moves; see passing_surface.gdshader.
func _moving_surface(texture: Texture2D, tint: Color, scale: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(ROOT + "passing_surface.gdshader")
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("texture_scale", scale)
	return material


func _passing(material: Material) -> Material:
	var source := material as ShaderMaterial
	if source == null:
		return material
	if not _passing_materials.has(source):
		_passing_materials[source] = _moving_surface(
			source.get_shader_parameter("albedo_texture"),
			source.get_shader_parameter("tint"),
			source.get_shader_parameter("texture_scale")
		)
	return _passing_materials[source]


func _build_feature() -> void:
	var feature := Node3D.new()
	feature.name = "Metro"
	feature.set_script(load(ROOT + "metro_service.gd"))
	for index: int in 4:
		for ride: bool in [false, true]:
			var zone := Node3D.new()
			zone.set_script(load(ROOT + "metro_zone.gd"))
			zone.name = ("Ride" if ride else "Station") + str(index)
			zone.position = (
				MetroRules.ride_position(index) if ride else MetroRules.station_position(index)
			)
			zone.set("ride_index" if ride else "station_index", index)
			zone.set("bounds", MetroRules.RIDE_BOUNDS if ride else MetroRules.STATION_BOUNDS)
			zone.set(
				"render_bounds",
				MetroRules.RIDE_VIEW if ride else AABB(Vector3(-6, -1, -92), Vector3(30, 9, 184))
			)
			zone.set("room_scene", ROOT + ("rooms/transit.tscn" if ride else "rooms/station.tscn"))
			feature.add_child(zone)
			if not ride:
				var gps := GpsDestination.new()
				gps.name = "Destination"
				gps.label = "Metro / " + MetroRules.NAMES[index].capitalize()
				gps.position = Vector3(4, 1.2, 0)
				zone.add_child(gps)
	var net := NetworkedEntity.new()
	net.name = "NetworkedEntity"
	net.replicated_properties.assign([NodePath(".:net_cycle"), NodePath(".:net_passengers")])
	net.continuous_properties.assign([NodePath(".:net_time")])
	net.replication_interval = 0.1
	feature.add_child(net)
	save(feature, ROOT + "feature.tscn")
	feature.free()
