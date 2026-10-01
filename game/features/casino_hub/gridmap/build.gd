extends SceneTree
## Build the shared MeshLibrary and the initial editable casino scene offline.

const Layout := preload("res://features/casino_hub/gridmap/layout.gd")
const TILES := preload("res://features/casino_hub/gridmap/tiles.tscn")
const Shops := preload("res://features/casino_hub/gridmap/shops.gd")
const Decor := preload("res://features/casino_hub/gridmap/decor.gd")
const DECOR_LIBRARY_PATH := "res://features/casino_hub/gridmap/casino_decor.tres"
const LIBRARY_PATH := "res://features/casino_hub/gridmap/casino_tiles.tres"
const SOURCE_PATH := "res://features/casino_hub/gridmap/scene_source.tscn"
const SCENE_PATH := "res://features/casino_hub/casino_gridmap.tscn"


func _initialize() -> void:
	var library := _library()
	assert(ResourceSaver.save(library, LIBRARY_PATH) == OK)
	assert(ResourceSaver.save(Decor.library(), DECOR_LIBRARY_PATH) == OK)
	var source := load(SOURCE_PATH) as PackedScene
	var level := source.instantiate() as Node3D
	Layout.populate(
		level.get_node("Floors") as GridMap,
		level.get_node("WallsNorthSouth") as GridMap,
		level.get_node("WallsEastWest") as GridMap
	)
	Shops.populate(
		level.get_node("Floors") as GridMap,
		level.get_node("ShopWallsNorthSouth") as GridMap,
		level.get_node("ShopWallsEastWest") as GridMap
	)
	Decor.populate(level.get_node("Decor") as GridMap)
	var ceiling := level.get_node("Ceiling") as GridMap
	for bounds: Rect2i in [
		Rect2i(-24, -20, 48, 40), Rect2i(-16, 20, 18, 10), Rect2i(2, 20, 32, 18)
	]:
		for x: int in range(bounds.position.x, bounds.end.x):
			for z: int in range(bounds.position.y, bounds.end.y):
				ceiling.set_cell_item(Vector3i(x, 20, z), 8)
	var packed := PackedScene.new()
	assert(packed.pack(level) == OK)
	assert(ResourceSaver.save(packed, SCENE_PATH) == OK)
	print("CASINO_GRIDMAP: library and editable pit/promenade scene saved")
	level.free()
	quit()


func _library() -> MeshLibrary:
	var library := MeshLibrary.new()
	var tiles := TILES.instantiate() as Node3D
	var names: Dictionary[int, String] = {
		0: "Floor",
		1: "Wall",
		2: "Ramp",
		3: "WoodWall",
		5: "TileFloor",
		6: "WoodFloor",
		7: "DoorHeader",
		8: "CeilingTile"
	}
	for id: int in names:
		var tile := tiles.get_node(names[id]) as MeshInstance3D
		var mesh := tile.mesh
		if tile.material_override != null:
			mesh = mesh.duplicate() as Mesh
			mesh.surface_set_material(0, tile.material_override)
		library.create_item(id)
		library.set_item_name(id, names[id])
		library.set_item_mesh(id, mesh)
		library.set_item_mesh_transform(id, tile.transform)
		var shapes: Array = []
		for child: Node in tile.find_children("*", "CollisionShape3D", true, false):
			var collider := child as CollisionShape3D
			var body := collider.get_parent() as Node3D
			shapes.append(collider.shape)
			shapes.append(tile.transform * body.transform * collider.transform)
		library.set_item_shapes(id, shapes)
	# GridMap physics needs the final box dimensions rather than a scaled shape basis.
	var perimeter := BoxShape3D.new()
	perimeter.size = Vector3(2, 5, 0.2)
	library.set_item_shapes(
		Layout.WOOD_WALL, [perimeter, Transform3D(Basis.IDENTITY, Vector3(0.5, 2.5, -0.5))]
	)
	# Reuse the authored facing for the 1.5 m pit edge; don't change its source model.
	library.create_item(Layout.PIT_WALL)
	library.set_item_name(Layout.PIT_WALL, "WoodPitWall")
	library.set_item_mesh(Layout.PIT_WALL, library.get_item_mesh(Layout.WOOD_WALL))
	library.set_item_mesh_transform(
		Layout.PIT_WALL, Transform3D(Basis.from_scale(Vector3(1, 0.6, 1)), Vector3(0, 0, -0.5))
	)
	var retaining := BoxShape3D.new()
	retaining.size = Vector3(1, 1.5, 0.2)
	library.set_item_shapes(
		Layout.PIT_WALL, [retaining, Transform3D(Basis.IDENTITY, Vector3(0, 0.75, -0.5))]
	)
	tiles.free()
	return library
