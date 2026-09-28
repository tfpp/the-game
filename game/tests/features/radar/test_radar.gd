extends GutTest

const Radar := preload("res://features/radar/radar.gd")
const Geometry := preload("res://features/radar/radar_geometry.gd")


func test_desktop_only_even_with_a_mobile_keyboard_or_gamepad() -> void:
	assert_true(Radar.desktop_visible(false, false, false))
	assert_false(Radar.desktop_visible(true, false, false))
	assert_false(Radar.desktop_visible(false, true, false))
	assert_false(Radar.desktop_visible(false, false, true))


func test_slice_shows_walls_and_floor_but_omits_roof_and_other_storeys() -> void:
	var geometry := Geometry.new()
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(8, 1, 8)
	geometry.append_mesh(floor_box, Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0)), 1.0)
	assert_eq(geometry.floors.size(), 6, "Only the two upward floor triangles")
	assert_eq(geometry.walls.size(), 0)
	geometry.append_mesh(floor_box, Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)), 1.0)
	geometry.append_mesh(floor_box, Transform3D(Basis.IDENTITY, Vector3(0, -6, 0)), 1.0)
	assert_eq(geometry.floors.size(), 6, "Ceiling and lower storey do not cover the map")
	var wall := BoxMesh.new()
	wall.size = Vector3(1, 4, 8)
	geometry.append_mesh(wall, Transform3D(Basis.IDENTITY, Vector3(4, 2, 0)), 1.0)
	assert_eq(geometry.walls.size(), 16, "All four wall sides are sliced")
	assert_eq(geometry.floor_mesh().get_surface_count(), 1)


func test_world_projection_is_north_up_and_player_centered() -> void:
	var radar := Radar.new()
	radar.size = Vector2(228, 228)
	radar._center = Vector2(10, 20)
	assert_eq(radar.map_point(Vector3(10, 1, 20)), Vector2(114, 114))
	assert_eq(radar.map_point(Vector3(10, 1, 10)), Vector2(114, 84))
	assert_eq(radar.map_point(Vector3(20, 1, 20)), Vector2(144, 114))
	radar.free()


func test_salon_boxes_include_gallery_and_furniture_but_exclude_ceiling() -> void:
	var salon := preload("res://features/casino_hub/salon.tscn").instantiate()
	add_child_autofree(salon)
	var radar := Radar.new()
	radar._height = 4.0
	var roots: Array[Node3D] = []
	radar._collect(salon, roots)
	assert_has(roots, salon.get_node("GalleryFloorBody/Shape"))
	assert_does_not_have(roots, salon.get_node("CofferedCeilingBody/Shape"))
	radar._pending = roots.duplicate()
	radar._build_height = 4.0
	radar._building = Geometry.new()
	while not radar._pending.is_empty():
		radar._build_step()
	assert_gt(radar._geometry.floors.size(), 0, "Gallery floor appears at its own storey")
	radar._height = -0.5
	roots.clear()
	radar._collect(salon, roots)
	assert_has(roots, salon.get_node("TableBody0/Shape"))
	assert_does_not_have(roots, salon.get_node("GalleryFloorBody/Shape"))
	radar.free()
