extends SceneTree
## Build the shared MeshLibrary and the initial editable casino scene offline.

const Balcony := preload("res://features/casino_hub/gridmap/mariachi_balcony.gd")
const Structure := preload("res://features/casino_hub/gridmap/pit_structure.gd")
const Layout := preload("res://features/casino_hub/gridmap/layout.gd")
const TILES := preload("res://features/casino_hub/gridmap/tiles.tscn")
const Railings := preload("res://features/casino_hub/gridmap/railings.gd")
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
	Railings.populate(
		level.get_node("PitRailing/SpansNorthSouth") as GridMap,
		level.get_node("PitRailing/SpansEastWest") as GridMap,
		level.get_node("PitRailing/Posts") as GridMap
	)
	var ceiling := level.get_node("Ceiling") as GridMap
	for bounds: Rect2i in [
		Rect2i(-24, -20, 48, 40), Rect2i(-16, 20, 18, 10), Rect2i(2, 20, 32, 18)
	]:
		for x: int in range(bounds.position.x, bounds.end.x):
			for z: int in range(bounds.position.y, bounds.end.y):
				ceiling.set_cell_item(Vector3i(x, 20, z), 8)
	Structure.configure(level)
	Balcony.configure(level)
	preload("res://features/casino_hub/gridmap/retired_food_hall.gd").trim(level)
	preload("res://features/casino_hub/gridmap/vip_window.gd").configure(level)
	var packed := PackedScene.new()
	assert(packed.pack(level) == OK)
	assert(ResourceSaver.save(packed, SCENE_PATH) == OK)
	print("CASINO_GRIDMAP: library and editable pit/promenade scene saved")
	level.free()
	quit()


static func _library() -> MeshLibrary:
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
		8: "CeilingTile",
		9: "RailingKit/RailSpan",
		10: "RailingKit/RailPost",
		12: "StuccoPitWall",
		13: "StuccoWall",
		15: "CasinoStairFlight"
	}
	for id: int in names:
		var tile := tiles.get_node(names[id]) as MeshInstance3D
		var mesh := tile.mesh
		if tile.material_override != null:
			mesh = mesh.duplicate() as Mesh
			mesh.surface_set_material(0, tile.material_override)
		library.create_item(id)
		library.set_item_name(id, str(tile.name))
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
	# Reuse the authored facing for the quarter-height pit edge.
	library.create_item(Layout.PIT_WALL)
	library.set_item_name(Layout.PIT_WALL, "WoodPitWall")
	library.set_item_mesh(Layout.PIT_WALL, library.get_item_mesh(Layout.WOOD_WALL))
	library.set_item_mesh_transform(
		Layout.PIT_WALL,
		Transform3D(Basis.from_scale(Vector3(1, Layout.PIT_HEIGHT / 2.5, 1)), Vector3(0, 0, -0.5))
	)
	var retaining := BoxShape3D.new()
	retaining.size = Vector3(1, Layout.PIT_HEIGHT, 0.2)
	library.set_item_shapes(
		Layout.PIT_WALL,
		[retaining, Transform3D(Basis.IDENTITY, Vector3(0, Layout.PIT_HEIGHT / 2.0, -0.5))]
	)
	var elevator := load("res://features/elevator/gridmap/elevator_library.tres") as MeshLibrary
	library.create_item(11)
	library.set_item_name(11, "ElevatorBay")
	library.set_item_mesh(11, elevator.get_item_mesh(0))
	library.set_item_shapes(11, elevator.get_item_shapes(0))
	# Fitted upper hall module keeps the same physical texture scale as the 5 m tile.
	library.create_item(14)
	library.set_item_name(14, "StuccoUpperWall")
	var upper := (
		load("res://assets/room_kits/beige_stucco_wall_full/beige_stucco_wall_upper.res")
		as ArrayMesh
	)
	upper = upper.duplicate() as ArrayMesh
	upper.surface_set_material(0, library.get_item_mesh(13).surface_get_material(0))
	library.set_item_mesh(14, upper)
	library.set_item_mesh_transform(14, Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.5)))
	var upper_shape := BoxShape3D.new()
	upper_shape.size = Vector3(1, Structure.CEILING_HEIGHT - Layout.STANDARD_WALL_HEIGHT, 0.2)
	library.set_item_shapes(
		14, [upper_shape, Transform3D(Basis.IDENTITY, Vector3(0, upper_shape.size.y / 2.0, -0.5))]
	)
	# Shear the existing span into a slope with upright balusters, then bake collision.
	library.create_item(16)
	library.set_item_name(16, "CasinoStairRail")
	var slope := Basis(Vector3(0, 0.625, 1), Vector3.UP, Vector3.LEFT)
	var rail_tool := SurfaceTool.new()
	rail_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	rail_tool.append_from(library.get_item_mesh(9), 0, Transform3D(slope, Vector3.ZERO))
	var rail := rail_tool.commit()
	rail.surface_set_material(0, library.get_item_mesh(9).surface_get_material(0))
	library.set_item_mesh(16, rail)
	var rail_shape := ConvexPolygonShape3D.new()
	var rail_points := PackedVector3Array()
	for x: float in [0.0, 2.0]:
		for y: float in [0.0, 1.105]:
			for z: float in [-0.075, 0.075]:
				rail_points.append(slope * Vector3(x, y, z))
	rail_shape.points = rail_points
	library.set_item_shapes(16, [rail_shape, Transform3D.IDENTITY])
	tiles.free()
	return library
