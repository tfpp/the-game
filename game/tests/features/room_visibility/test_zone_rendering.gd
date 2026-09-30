extends GutTest

const RENDERER := preload("res://features/room_visibility/zone_rendering.gd")
const PARKING := preload("res://features/parking_garage/feature.tscn")
const BASEMENT := preload("res://features/procedural_rooms/feature.tscn")

var _root: Node3D
var _zone: RenderZone
var _renderer: Node


func before_each() -> void:
	_root = Node3D.new()
	add_child(_root)
	_zone = RenderZone.new()
	_zone.position = Vector3(0, -22, 0)
	_zone.render_layer = 20
	_zone.render_bounds = AABB(Vector3(-10, -1, -10), Vector3(20, 21, 20))
	_root.add_child(_zone)
	_renderer = RENDERER.new()
	_root.add_child(_renderer)


func after_each() -> void:
	_root.free()


func _mesh(parent: Node3D, at: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	parent.add_child(mesh)
	mesh.position = at
	return mesh


func test_garage_camera_excludes_overlapping_casino_geometry_and_lights() -> void:
	var casino := _mesh(_root, Vector3(0, -1.5, 0))
	var garage := _mesh(_zone, Vector3(0, 16, 0))
	var sun := DirectionalLight3D.new()
	_root.add_child(sun)
	_renderer._register(casino, false)
	_renderer._register(garage, false)
	_renderer._register(sun, false)
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.position = Vector3(0, -4.3, 0)
	_renderer.update_camera(camera)
	assert_eq(camera.cull_mask & garage.layers, _zone.render_mask())
	assert_eq(camera.cull_mask & casino.layers, 0, "Distance clipping alone cannot do this")
	assert_eq(camera.cull_mask & sun.layers, 0)
	assert_eq(sun.light_cull_mask & garage.layers, 0, "Casino sunlight cannot light basement")
	assert_eq(sun.light_cull_mask & 7, 7, "Keep authored non-zone illumination layers")
	assert_true(casino.visible, "Do not globally hide nodes or affect other cameras")
	camera.position = Vector3(0, 1.7, 0)
	_renderer.update_camera(camera)
	assert_ne(camera.cull_mask & casino.layers, 0)
	assert_eq(camera.cull_mask & garage.layers, 0, "Garage is not drawn from casino")


func test_new_player_visuals_follow_teleport_and_respawn_camera() -> void:
	var player := CharacterBody3D.new()
	_root.add_child(player)
	var avatar := _mesh(player, Vector3.UP)
	_renderer._register(avatar, true)
	var camera := Camera3D.new()
	camera.cull_mask = 7
	_root.add_child(camera)
	_renderer.update_camera(camera)
	assert_eq(avatar.layers, 1)
	player.position = Vector3(0, -6, 0)
	_renderer.refresh_moving()
	camera.position = Vector3(0, -4.3, 0)
	_renderer.update_camera(camera)
	assert_eq(camera.cull_mask & avatar.layers, _zone.render_mask())
	player.position = Vector3.ZERO
	_renderer.refresh_moving()
	assert_eq(avatar.layers, 1)
	var respawn := Camera3D.new()
	respawn.cull_mask = 3
	_root.add_child(respawn)
	_renderer.update_camera(respawn)
	assert_eq(camera.cull_mask, 7, "First/third-person camera switching restores old mask")
	assert_eq(respawn.cull_mask, 3)
	avatar.free()
	_renderer.refresh_moving()
	assert_eq(_renderer._visuals.size(), 0, "Disconnected/freed avatars are removed")


func test_shared_lift_visuals_remain_visible_on_both_sides() -> void:
	var cab := Node3D.new()
	cab.add_to_group(&"render_zone_shared")
	_zone.add_child(cab)
	var mesh := _mesh(cab, Vector3.ZERO)
	_renderer._register(mesh, false)
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.position = Vector3(0, -6, 0)
	_renderer.update_camera(camera)
	assert_ne(camera.cull_mask & mesh.layers, 0)
	camera.position = Vector3(0, 1.7, 0)
	_renderer.update_camera(camera)
	assert_ne(camera.cull_mask & mesh.layers, 0)


func test_renderer_removal_restores_camera_and_authored_visual_masks() -> void:
	var light := OmniLight3D.new()
	_zone.add_child(light)
	light.layers = 3
	light.light_cull_mask = 5
	_renderer._register(light, false)
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.cull_mask = 15
	camera.position.y = -6
	_renderer.update_camera(camera)
	_renderer.free()
	assert_eq(camera.cull_mask, 15)
	assert_eq(light.layers, 3)
	assert_eq(light.light_cull_mask, 5)
	_renderer = Node.new()
	_root.add_child(_renderer)


func test_separate_garage_scenes_keep_paths_and_exclude_each_other() -> void:
	var parking := PARKING.instantiate() as Node3D
	var basement := BASEMENT.instantiate() as Node3D
	_root.add_child(parking)
	_root.add_child(basement)
	var old_garage := parking.get_node("Garage") as RenderZone
	var new_garage := basement.get_node("Garage") as RenderZone
	assert_eq(old_garage.scene_file_path, "res://features/parking_garage/garage.tscn")
	assert_eq(new_garage.scene_file_path, "res://features/procedural_rooms/garage.tscn")
	assert_true(old_garage.has_node("GarageDoor"))
	assert_false(new_garage.contains(Vector3(7.4, -1.5, -8.4)), "Sunken casino is outside")
	var patron := CharacterBody3D.new()
	_root.add_child(patron)
	patron.position = Vector3(7.4, -1.5, -8.4)
	var patron_mesh := _mesh(patron, Vector3.ZERO)
	_renderer._register(patron_mesh, true)
	assert_eq(patron_mesh.layers, 1, "Moving casino patrons do not leak into garage")
	assert_true(new_garage.has_node("Return/NetworkedEntity"))
	assert_true(new_garage.has_node("CrownGarage/Lift/NetworkedEntity"))
	var old_mesh := old_garage.get_node("Floor0MiddleBand") as VisualInstance3D
	var new_mesh := new_garage.get_node("CrownGarage/Structure/Floor") as VisualInstance3D
	_renderer._register(old_mesh, false)
	_renderer._register(new_mesh, false)
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.position = Vector3(-10, 2, 595)
	_renderer.update_camera(camera)
	assert_ne(camera.cull_mask & old_mesh.layers, 0)
	assert_eq(camera.cull_mask & new_mesh.layers, 0)
	camera.global_position = new_garage.to_global(Vector3(0, 17.7, 5))
	_renderer.update_camera(camera)
	assert_ne(camera.cull_mask & new_mesh.layers, 0)
	assert_eq(camera.cull_mask & old_mesh.layers, 0)
