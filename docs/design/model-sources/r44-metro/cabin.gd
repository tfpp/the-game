extends RefCounted
## MeshLibrary passenger cabin, physical door pockets and portable door animation.

const MEDIA := "res://assets/metro/models/"
const FEATURE := "res://features/metro/"
var _builder: SceneTree
var _interior: Material
var _steel: Material
var _glass: Material
var _lamp: Material
var _scratch: Node3D


func build(builder: SceneTree, car: Node3D) -> void:
	_builder = builder
	_interior = builder.get("interior") as Material
	_steel = builder.get("material") as Material
	_glass = builder.get("glass") as Material
	_lamp = builder.get("lamp") as Material
	_scratch = Node3D.new()
	var library := make_library()
	var grid := GridMap.new()
	grid.name = "CabinStructure"
	grid.mesh_library = library
	grid.cell_size = Vector3(1, 1, 0.01)
	grid.cell_center_x = false
	grid.cell_center_y = false
	grid.cell_center_z = false
	grid.cell_octant_size = 512
	grid.collision_layer = 1
	grid.collision_mask = 0
	car.add_child(grid)
	grid.owner = car
	for z: int in range(-1000, 1001, 200):
		grid.set_cell_item(Vector3i(0, 0, z), 0)
		grid.set_cell_item(Vector3i(0, 1, z), 1)
	# Library ceiling is offset by -1 m because its cells use a separate Y layer.
	for side: int in [-1, 1]:
		var orientation := (
			0 if side == 1 else grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
		)
		for z: int in [-500, 0, 500]:
			grid.set_cell_item(Vector3i(side, 0, z), 2, orientation)
		for z: int in [-966, 966]:
			grid.set_cell_item(Vector3i(side, 0, z), 3, orientation)
		for z: int in [-750, -250, 250, 750]:
			grid.set_cell_item(Vector3i(side, 0, z), 4, orientation)
	# Wall meshes are relative to the X cell anchor (±1 m).
	for end: int in [-1, 1]:
		var orientation := (
			0 if end == 1 else grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
		)
		grid.set_cell_item(Vector3i(0, 0, end * 1090), 5, orientation)
	make_furniture(car)
	make_doors(car)
	_scratch.free()


func box(center: Vector3, size: Vector3, region: int) -> void:
	_builder.call("box", center, size, region)


func tube(a: Vector3, b: Vector3, radius: float, region: int) -> void:
	_builder.call("tube", a, b, radius, region, 6)


func face(points: Array[Vector3], region: int, normal: Vector3) -> void:
	_builder.call("polygon", points, region, normal)


func mesh(id: String, material: Material) -> ArrayMesh:
	var instance := _builder.call("finish", _scratch, id, material) as MeshInstance3D
	var result := instance.mesh as ArrayMesh
	instance.free()
	return result


func combined(id: String, surfaces: Array[ArrayMesh]) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface: ArrayMesh in surfaces:
		for i: int in surface.get_surface_count():
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface.surface_get_arrays(i))
			result.surface_set_material(
				result.get_surface_count() - 1, surface.surface_get_material(i)
			)
	result.take_over_path(MEDIA + id + ".res")
	ResourceSaver.save(result, result.resource_path)
	return result


func shape(size: Vector3, at: Vector3) -> Array:
	var result := BoxShape3D.new()
	result.size = size
	return [result, Transform3D(Basis.IDENTITY, at)]


func make_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	box(Vector3(0, 1.15, 0), Vector3(3.04, 0.1, 2), 2)
	item(
		library,
		0,
		"Floor",
		mesh("CabinFloor", _interior),
		shape(Vector3(3.04, 0.1, 2), Vector3(0, 1.15, 0))
	)
	var profile: Array[Vector2] = [
		Vector2(-1.34, 2.13),
		Vector2(-1.20, 2.36),
		Vector2(-0.8, 2.48),
		Vector2(0.8, 2.48),
		Vector2(1.20, 2.36),
		Vector2(1.34, 2.13)
	]
	for i: int in profile.size() - 1:
		var a := profile[i]
		var b := profile[i + 1]
		face(
			[
				Vector3(a.x, a.y, -1),
				Vector3(b.x, b.y, -1),
				Vector3(b.x, b.y, 1),
				Vector3(a.x, a.y, 1)
			],
			5,
			Vector3(0, -1, 0)
		)
	item(
		library,
		1,
		"Ceiling",
		mesh("CabinCeiling", _interior),
		shape(Vector3(3.04, 0.12, 2), Vector3(0, 2.55, 0))
	)
	var wall_shapes := shape(Vector3(0.19, 1.94, 3.56), Vector3(0.43, 2.17, 0))
	item(library, 2, "WindowBay", wall_tile(false), wall_shapes)
	item(
		library,
		3,
		"EndWindowBay",
		wall_tile(true),
		shape(Vector3(0.19, 1.94, 2.88), Vector3(0.43, 2.17, 0))
	)
	box(Vector3(0.43, 3.255, 0), Vector3(0.18, 0.27, 1.44), 0)
	var exterior := mesh("HeaderSteel", _steel)
	box(Vector3(0.328, 3.255, 0), Vector3(0.024, 0.27, 1.44), 5)
	item(
		library,
		4,
		"DoorHeader",
		combined("DoorHeader", [exterior, mesh("HeaderLining", _interior)]),
		shape(Vector3(0.20, 0.27, 1.44), Vector3(0.42, 3.255, 0))
	)
	box(Vector3(0, 2.26, 0), Vector3(2.68, 2.12, 0.1), 0)
	box(Vector3(0, 2.16, -0.065), Vector3(0.74, 1.91, 0.03), 3)
	box(Vector3(0, 2.64, -0.086), Vector3(0.50, 0.75, 0.018), 7)
	box(Vector3(0.28, 1.97, -0.10), Vector3(0.035, 0.23, 0.035), 3)
	box(Vector3(0, 3.28, -0.064), Vector3(2.65, 0.07, 0.025), 5)
	item(
		library,
		5,
		"FixedEndPartition",
		mesh("EndPartition", _interior),
		shape(Vector3(2.68, 2.12, 0.10), Vector3(0, 2.26, 0))
	)
	library.take_over_path(FEATURE + "cabin_tiles.tres")
	ResourceSaver.save(library, library.resource_path)
	return library


func item(library: MeshLibrary, id: int, label: String, visual: Mesh, collision: Array) -> void:
	library.create_item(id)
	library.set_item_name(id, label)
	library.set_item_mesh(id, visual)
	library.set_item_shapes(id, collision)


func wall_tile(end: bool) -> ArrayMesh:
	var length_z := 2.88 if end else 3.56
	var windows: Array[Vector2] = []
	if end:
		windows.append(Vector2(-0.54, 0.54))
	else:
		windows.assign([Vector2(-0.96, -0.06), Vector2(0.06, 0.96)])
	# Two skins make a 115 mm empty pocket between lining and exterior panel.
	wall_strips(length_z, windows, 0.4975, 0.045, 0)
	box(Vector3(0.534, 1.31, 0), Vector3(0.025, 0.2, length_z), 1)
	box(Vector3(0.534, 2.06, 0), Vector3(0.025, 0.04, length_z), 0)
	var outside := mesh("EndBaySteel" if end else "BaySteel", _steel)
	wall_strips(length_z, windows, 0.32, 0.04, 0)
	box(Vector3(0.29, 2.14, 0), Vector3(0.045, 0.065, length_z), 5)
	box(Vector3(0.30, 3.12, 0), Vector3(0.04, 0.08, length_z), 5)
	for opening: Vector2 in windows:
		var width := opening.y - opening.x
		var z := (opening.x + opening.y) / 2
		for x: float in [0.278, 0.526]:
			box(Vector3(x, 2.155, z), Vector3(0.035, 0.05, width + 0.06), 3)
			box(Vector3(x, 3.045, z), Vector3(0.035, 0.05, width + 0.06), 3)
			for edge: float in [opening.x, opening.y]:
				box(Vector3(x, 2.60, edge), Vector3(0.035, 0.89, 0.045), 3)
	var inside := mesh("EndBayLining" if end else "BayLining", _interior)
	for opening: Vector2 in windows:
		face(
			[
				Vector3(0.48, 3.02, opening.x),
				Vector3(0.48, 3.02, opening.y),
				Vector3(0.48, 2.18, opening.y),
				Vector3(0.48, 2.18, opening.x)
			],
			0,
			Vector3.RIGHT
		)
	return combined(
		"EndWallBay" if end else "WallBay",
		[outside, inside, mesh("EndBayGlass" if end else "BayGlass", _glass)]
	)


func wall_strips(
	length_z: float, windows: Array[Vector2], x: float, thickness: float, region: int
) -> void:
	box(Vector3(x, 1.69, 0), Vector3(thickness, 0.98, length_z), region)
	box(Vector3(x, 3.08, 0), Vector3(thickness, 0.12, length_z), region)
	var start := -length_z / 2
	for opening: Vector2 in windows:
		box(
			Vector3(x, 2.6, (start + opening.x) / 2),
			Vector3(thickness, 0.84, opening.x - start),
			region
		)
		start = opening.y
	box(
		Vector3(x, 2.6, (start + length_z / 2) / 2),
		Vector3(thickness, 0.84, length_z / 2 - start),
		region
	)


func make_doors(car: Node3D) -> void:
	# Window aperture is a real hole through each double-sided leaf.
	box(Vector3(0, -0.49, 0), Vector3(0.04, 0.94, 0.70), 0)
	box(Vector3(0, 0.905, 0), Vector3(0.04, 0.11, 0.70), 0)
	for z: float in [-0.285, 0.285]:
		box(Vector3(0, 0.42, z), Vector3(0.04, 0.86, 0.13), 0)
	var steel := mesh("OpeningDoorLeaf", _steel)
	face(
		[
			Vector3(0, 0.85, -0.22),
			Vector3(0, 0.85, 0.22),
			Vector3(0, -0.01, 0.22),
			Vector3(0, -0.01, -0.22)
		],
		0,
		Vector3.RIGHT
	)
	var leaf_mesh := combined("PassengerDoor", [steel, mesh("DoorPane", _glass)])
	for side: int in [-1, 1]:
		for door: int in 4:
			for half: int in 2:
				var leaf := AnimatableBody3D.new()
				leaf.name = (
					"Door%s%d%s" % ["L" if side < 0 else "R", door + 1, "A" if half == 0 else "B"]
				)
				leaf.position = Vector3(
					side * 1.43, 2.16, -7.5 + door * 5.0 + (-0.356 if half == 0 else 0.356)
				)
				leaf.sync_to_physics = false
				leaf.collision_layer = 1
				leaf.collision_mask = 0
				car.add_child(leaf)
				leaf.owner = car
				var visual := MeshInstance3D.new()
				visual.name = "Visual"
				visual.mesh = leaf_mesh
				leaf.add_child(visual)
				visual.owner = car
				var collider := CollisionShape3D.new()
				collider.name = "Collision"
				var collision := BoxShape3D.new()
				collision.size = Vector3(0.04, 1.92, 0.70)
				collider.shape = collision
				leaf.add_child(collider)
				collider.owner = car


func make_furniture(car: Node3D) -> void:
	for side: int in [-1, 1]:
		for bay: float in [-5.0, 0.0, 5.0]:
			# Two lengthwise seats between short transverse end seats.
			for z: float in [-0.37, 0.37]:
				seat(Vector3(side * 1.0, 1.2, bay + z), Vector3(-side, 0, 0), 0.66, 1)
			for z: float in [-1.30, 1.30]:
				seat(Vector3(side * 1.0, 1.2, bay + z), Vector3(0, 0, -signf(z)), 0.64, 4)
			for z: float in [-1.55, 1.55]:
				tube(
					Vector3(side * 0.62, 1.2, bay + z),
					Vector3(side * 0.62, 3.45, bay + z),
					0.026,
					3
				)
				tube(
					Vector3(side * 0.62, 2.08, bay + z),
					Vector3(side * 1.29, 2.08, bay + z),
					0.022,
					3
				)
		for z: float in [-9.68, 9.68]:
			for dz: float in [-0.36, 0.36]:
				seat(
					Vector3(side * 1.0, 1.2, z + dz),
					Vector3(-side, 0, 0),
					0.65,
					1 if side < 0 else 4
				)
		# Suspended grab rail; uprights join the rail at bay ends.
		tube(Vector3(side * 0.62, 3.28, -9.5), Vector3(side * 0.62, 3.28, 9.5), 0.026, 3)
	_builder.call("finish", car, "PassengerFurniture", _interior)
	# Modest local light count: three per car, no shadows.
	for z: float in [-6.0, 0.0, 6.0]:
		for side: int in [-1, 1]:
			box(Vector3(side * 0.64, 3.43, z), Vector3(0.20, 0.035, 3.5), 6)
	_builder.call("finish", car, "FluorescentDiffusers", _lamp)
	var collision := StaticBody3D.new()
	collision.name = "SeatCollision"
	collision.collision_mask = 0
	car.add_child(collision)
	collision.owner = car
	for side: int in [-1, 1]:
		for z: float in [-9.68, -5.0, 0.0, 5.0, 9.68]:
			var collider := CollisionShape3D.new()
			var box_shape := BoxShape3D.new()
			box_shape.size = Vector3(0.72, 0.94, 2.98 if absf(z) < 8 else 1.45)
			collider.shape = box_shape
			collider.position = Vector3(side * 1.0, 1.67, z)
			collision.add_child(collider)
			collider.owner = car
	for z: float in [-6.0, 0.0, 6.0]:
		var light := OmniLight3D.new()
		light.name = "CabinLight%d" % int(z + 6)
		light.position = Vector3(0, 3.15, z)
		light.light_color = Color("dce1c8")
		light.light_energy = 0.75
		light.omni_range = 5.2
		light.shadow_enabled = false
		car.add_child(light)
		light.owner = car


func seat(at: Vector3, forward: Vector3, width: float, region: int) -> void:
	var right := forward.cross(Vector3.UP)
	# Continuous molded bucket profile, extruded between its two end caps.
	var profile: Array[Vector2] = [
		Vector2(0.32, 0.39),
		Vector2(0.32, 0.46),
		Vector2(-0.14, 0.50),
		Vector2(-0.23, 0.91),
		Vector2(-0.30, 0.94),
		Vector2(-0.31, 0.87),
		Vector2(-0.22, 0.43)
	]
	var a: Array[Vector3] = []
	var b: Array[Vector3] = []
	for p: Vector2 in profile:
		a.append(at - right * width / 2 + forward * p.x + Vector3.UP * p.y)
		b.append(at + right * width / 2 + forward * p.x + Vector3.UP * p.y)
	for i: int in profile.size():
		var j := (i + 1) % profile.size()
		var outward := (
			forward * (profile[j].y - profile[i].y) + Vector3.UP * (profile[i].x - profile[j].x)
		)
		face([a[i], b[i], b[j], a[j]], region, outward)
	# End caps follow the profile via an indexed triangle fan around a visible inner point.
	# Use convex sections rather than a concave cap fan to keep every triangle valid.
	for side_points: Array[Vector3] in [a, b]:
		var normal := -right if side_points == a else right
		face([side_points[0], side_points[1], side_points[2], side_points[6]], region, normal)
		face(
			[side_points[2], side_points[3], side_points[4], side_points[5], side_points[6]],
			region,
			normal
		)
	box(at + Vector3(0, 0.22, 0), Vector3(0.20, 0.44, 0.20), 7)


static func animate_train(train: Node3D) -> void:
	var player := AnimationPlayer.new()
	player.name = "Doors"
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	train.add_child(player)
	player.owner = train
	var library := AnimationLibrary.new()
	for side: String in ["left", "right", "all"]:
		for opening: bool in [true, false]:
			var animation := Animation.new()
			animation.length = 1.2
			for child_car: Node in train.get_children():
				if not child_car.name.begins_with("Car"):
					continue
				var car := child_car as Node3D
				for child: Node in car.get_children():
					if not child is AnimatableBody3D:
						continue
					var leaf := child as AnimatableBody3D
					var train_left := leaf.name.begins_with("DoorL") != (car.rotation.y > 1.0)
					if side != "all" and (side == "left") != train_left:
						continue
					var closed := leaf.position
					var opened := (
						closed + Vector3(0, 0, -0.74 if leaf.name.ends_with("A") else 0.74)
					)
					var track := animation.add_track(Animation.TYPE_POSITION_3D)
					animation.track_set_path(track, NodePath(str(car.name) + "/" + str(leaf.name)))
					animation.position_track_insert_key(track, 0, closed if opening else opened)
					animation.position_track_insert_key(track, 1.2, opened if opening else closed)
			library.add_animation(("open_" if opening else "close_") + side, animation)
	player.add_animation_library("", library)


static func flatten_grids(root: Node3D) -> void:
	for child: Node in root.find_children("*", "GridMap", true, false):
		var grid := child as GridMap
		var group := Node3D.new()
		group.name = "CabinMeshes"
		grid.get_parent().add_child(group)
		group.transform = grid.transform
		for cell: Vector3i in grid.get_used_cells():
			var visual := MeshInstance3D.new()
			var id := grid.get_cell_item(cell)
			visual.name = (
				"%s_%d_%d_%d" % [grid.mesh_library.get_item_name(id), cell.x, cell.y, cell.z]
			)
			visual.mesh = grid.mesh_library.get_item_mesh(id)
			visual.transform = (
				Transform3D(grid.get_cell_item_basis(cell), grid.map_to_local(cell))
				* grid.mesh_library.get_item_mesh_transform(id)
			)
			group.add_child(visual)
		grid.free()
