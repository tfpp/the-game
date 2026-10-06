extends Node
## Bake saved GridMaps and separate server collision from the painted R44.

const ROOT := "res://features/metro/"
var library: MeshLibrary
var _id := 0


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
	var bars := Node3D.new()
	bars.name = "TunnelBars"
	room.add_child(bars)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("181e1c")
	library = MeshLibrary.new()
	_id = 0
	var wall_id := tile(Vector3(0.25, 5, 8), Vector3(0, 2.5, 0), dark, false)
	var rail_id := tile(Vector3(0.08, 0.12, 8), Vector3(0, 2.5, 0), load(ROOT + "lamp.tres"), false)
	ResourceSaver.save(library, ROOT + "tunnel_tiles.tres")
	library.take_over_path(ROOT + "tunnel_tiles.tres")
	var walls := grid(room, "Tunnel")
	var strips := grid(bars, "PassingLights")
	for z: int in range(-72, 73, 8):
		for x: int in [-3, 3]:
			walls.set_cell_item(Vector3i(x, 0, z), wall_id)
			strips.set_cell_item(
				Vector3i(x, 0, z),
				rail_id,
				strips.get_orthogonal_index_from_basis(Basis(Vector3.RIGHT, PI / 2))
			)
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
			if not ride:
				zone.set("render_bounds", AABB(Vector3(-6, -1, -92), Vector3(30, 9, 184)))
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
