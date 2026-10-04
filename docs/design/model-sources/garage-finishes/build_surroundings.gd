extends SceneTree
## Bakes the real window cutout and a streamed, decorative GridMap alley.

const STRUCTURE := "res://features/starter_room/structure.tscn"
const OUT := "res://features/starter_room/alley_structure.tscn"
const BRICK := preload("res://assets/street_props/surfaces/brick_wall.png")
const ASPHALT := preload("res://assets/street_props/surfaces/asphalt_wet.png")


func _initialize() -> void:
	_window_cutout()
	_alley()
	quit()


func _window_cutout() -> void:
	var text := FileAccess.get_file_as_string(STRUCTURE)
	if not text.contains("WindowSillMesh"):
		var resources := (
			'[sub_resource type="BoxMesh" id="WindowSillMesh"]\n'
			+ 'material = ExtResource("2_tglfj")\nsize = Vector3(1, 1.25, 0.2)\n\n'
			+ '[sub_resource type="BoxShape3D" id="WindowSillShape"]\nsize = Vector3(1, 1.25, 0.2)\n\n'
			+ '[sub_resource type="BoxMesh" id="WindowLintelMesh"]\n'
			+ 'material = ExtResource("2_tglfj")\nsize = Vector3(1, 1.75, 0.2)\n\n'
			+ '[sub_resource type="BoxShape3D" id="WindowLintelShape"]\nsize = Vector3(1, 1.75, 0.2)\n\n'
		)
		text = text.replace(
			'[sub_resource type="MeshLibrary" id="MeshLibrary_4alma"]',
			resources + '[sub_resource type="MeshLibrary" id="MeshLibrary_4alma"]'
		)
		var items := ""
		for id: int in [2, 3]:
			var kind := "Sill" if id == 2 else "Lintel"
			var y := .625 if id == 2 else 1.625
			items += 'item/%d/name = "Window%sWall"\n' % [id, kind]
			items += 'item/%d/mesh = SubResource("Window%sMesh")\n' % [id, kind]
			items += (
				"item/%d/mesh_transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, -0.5)\n"
				% [id, y]
			)
			items += (
				(
					'item/%d/shapes = [SubResource("Window%sShape"), '
					+ "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, -0.5)]\n"
				)
				% [id, kind, y]
			)
		text = text.replace('[node name="GarageInterior"', items + '\n[node name="GarageInterior"')
	for z: int in [2, 3, 4]:
		text = text.replace("65528, %d, 1048577" % z, "65528, %d, 1048578" % z)
		text = text.replace("720888, %d, 1048577" % z, "720888, %d, 1048579" % z)
	var file := FileAccess.open(STRUCTURE, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _alley() -> void:
	var root := Node3D.new()
	root.name = "AlleyStructure"
	var library := MeshLibrary.new()
	var brick := _material(BRICK, .88)
	var ground := _material(ASPHALT, .68)
	_tile(library, 0, "WetAsphalt", Vector3(1, .12, 1), Vector3(.5, -.06, .5), ground)
	_tile(library, 1, "BrickFacade", Vector3(.2, 1, 1), Vector3(0, .5, .5), brick)
	_tile(library, 2, "AlleyEndWall", Vector3(1, 1, .2), Vector3(.5, .5, 0), brick)
	var floor := _grid(root, "Ground", library)
	var facade := _grid(root, "Facade", library)
	var ends := _grid(root, "Ends", library)
	for x: int in 5:
		for z: int in 15:
			floor.set_cell_item(Vector3i(x, 0, z), 0)
	for y: int in 7:
		for z: int in 15:
			facade.set_cell_item(Vector3i(0, y, z), 1)
		for x: int in 5:
			for z: int in [0, 15]:
				ends.set_cell_item(Vector3i(x, y, z), 2)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, OUT)
	root.free()
	print("Window: six wall cells framed around a 3m by 2m aperture; alley: 250 GridMap cells")


func _grid(root: Node3D, title: String, library: MeshLibrary) -> GridMap:
	var grid := GridMap.new()
	grid.name = title
	grid.mesh_library = library
	grid.cell_size = Vector3.ONE
	grid.cell_center_x = false
	grid.cell_center_y = false
	grid.cell_center_z = false
	root.add_child(grid)
	grid.owner = root
	return grid


func _material(texture: Texture2D, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = roughness
	return material


func _tile(
	library: MeshLibrary, id: int, title: String, size: Vector3, at: Vector3, material: Material
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var shape := BoxShape3D.new()
	shape.size = size
	var transform := Transform3D(Basis.IDENTITY, at)
	library.create_item(id)
	library.set_item_name(id, title)
	library.set_item_mesh(id, mesh)
	library.set_item_mesh_transform(id, transform)
	library.set_item_shapes(id, [shape, transform])
