extends SceneTree
## Explicit offline build. Saved GridMap cells remain editable in the Godot editor.

const TILES := preload("res://features/casino_hub/gridmap/casino_tiles.tres")
const BAR := preload("res://assets/casino_hub/models/salon_bar.glb")
const TABLE := preload("res://features/casino_props/props/blackjack_table.tscn")
const COUCH := preload("res://features/casino_props/props/bundle/casino-two-seat-couch.tscn")
const CHAIR := preload("res://features/casino_props/props/bundle/casino-lounge-chair.tscn")
const COFFEE := preload("res://features/casino_props/props/coffee_table.tscn")
const GLASS := preload("res://features/casino_props/props/bundle/martini-glass.tscn")
const STOOL := preload("res://features/casino_hub/models/casino_stool.tscn")
const SCONCE := preload("res://features/casino_hub/models/brass_sconce.tscn")
const FINISHES := preload("res://features/casino_hub/model_materials.gd")

var room := Node3D.new()


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	room.name = "Interior"
	room.set_script(FINISHES)
	root.add_child(room)
	var floor := _grid("Deck")
	for x: int in range(16, 24):
		for z: int in range(-12, 12):
			floor.set_cell_item(Vector3i(x, 20, z), 6)
	var walls := _grid("EndWalls")
	var reverse := walls.get_orthogonal_index_from_basis(Basis(Vector3.UP, PI))
	for x: int in range(16, 24):
		walls.set_cell_item(Vector3i(x, 20, -12), 14)
		walls.set_cell_item(Vector3i(x, 20, 11), 14, reverse)
		walls.set_cell_item(Vector3i(x, 0, -12), 13)
		walls.set_cell_item(Vector3i(x, 0, 11), 13, reverse)
	var back := _grid("OuterWall")
	var inward := back.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for z: int in range(-12, 12):
		back.set_cell_item(Vector3i(23, 20, z), 14, inward)
		back.set_cell_item(Vector3i(23, 0, z), 13, inward)
	var ceiling := _grid("Ceiling")
	for x: int in range(16, 24):
		for z: int in range(-12, 12):
			ceiling.set_cell_item(Vector3i(x, 35, z), 8)
	_collision("Roof", Vector3(20, 8.85, 0), Vector3(8, 0.2, 24))
	var rails := _grid("WindowRail")
	rails.cell_center_x = false
	rails.cell_center_z = false
	var turn := rails.get_orthogonal_index_from_basis(Basis(Vector3.UP, -PI / 2))
	for z: int in range(-12, 12, 2):
		rails.set_cell_item(Vector3i(16, 20, z), 9, turn)
	var bar := _prop(BAR, "PrivateBar", Vector3(23, 5, 0), -PI / 2)
	FINISHES.apply_finishes(bar)
	_collision("Counter", Vector3(21.9, 5.49, 0), Vector3(0.4, 0.98, 7))
	for z: int in [-2, 0, 2]:
		_prop(STOOL, "Stool_%d" % z, Vector3(20.7, 5, z))
	for z: int in [-4, 6]:
		_prop(TABLE, "TripleTable_%d" % z, Vector3(20.5, 5, z))
		_prop(GLASS, "TableGlass_%d" % z, Vector3(21.2, 5.92, z + 0.5))
	var couch := _prop(COUCH, "VelvetBooth", Vector3(17.4, 5, -8), PI / 2)
	couch.scale = Vector3.ONE * 1.1
	_prop(CHAIR, "WindowChair", Vector3(17.5, 5, 2.8), PI / 2)
	_prop(COFFEE, "CocktailTable", Vector3(18.3, 5, -8))
	_prop(GLASS, "LuckyCoupe", Vector3(18.3, 5.46, -8))
	for z: int in [-6, 6]:
		_prop(SCONCE, "Sconce_%d" % z, Vector3(23.8, 7.2, z), -PI / 2)
		var light := OmniLight3D.new()
		light.name = "AmberPool_%d" % z
		light.position = Vector3(21, 7.3, z)
		light.light_color = Color("ffd4a0")
		light.light_energy = 0.8
		light.omni_range = 7.0
		_add(light)
	var label := Label3D.new()
	label.name = "ClubSign"
	label.text = "THE MIRROR CLUB\nWhat happens upstairs stays upstairs."
	label.position = Vector3(23.75, 7.5, 0)
	label.rotation.y = -PI / 2
	label.pixel_size = 0.004
	label.font_size = 34
	label.modulate = Color("dfbe7c")
	_add(label)
	var scene := PackedScene.new()
	var error := scene.pack(room)
	if error == OK:
		error = ResourceSaver.save(scene, "res://features/vip_lounge/interior.tscn")
	print("VIP interior saved: ", error)
	quit(0 if error == OK else 1)


func _add(node: Node) -> void:
	room.add_child(node)
	_own(node)


func _own(node: Node) -> void:
	node.owner = room
	if not node.scene_file_path.is_empty():
		return
	for child: Node in node.get_children():
		_own(child)


func _grid(label: String) -> GridMap:
	var grid := GridMap.new()
	grid.name = label
	grid.mesh_library = TILES
	grid.cell_size = Vector3(1, 0.25, 1)
	grid.cell_octant_size = 8
	grid.cell_center_y = false
	_add(grid)
	return grid


func _prop(scene: PackedScene, label: String, at: Vector3, yaw := 0.0) -> Node3D:
	var node := scene.instantiate() as Node3D
	node.name = label
	node.position = at
	node.rotation.y = yaw
	_add(node)
	return node


func _collision(label: String, at: Vector3, dimensions: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	body.add_child(shape)
	_add(body)
