extends GutTest

const RENDERER := preload("res://features/room_visibility/zone_rendering.gd")
const BASEMENT := preload("res://features/procedural_rooms/prototype.tscn")

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


func test_static_gridmap_joins_private_render_mask_and_keeps_collision() -> void:
	var grid := GridMap.new()
	var library := MeshLibrary.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(4, .2, 4)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	library.create_item(0)
	library.set_item_mesh(0, mesh)
	library.set_item_shapes(0, [shape, Transform3D.IDENTITY])
	grid.mesh_library = library
	grid.cell_size = Vector3.ONE
	grid.cell_center_x = false
	grid.cell_center_y = false
	grid.cell_center_z = false
	grid.set_cell_item(Vector3i.ZERO, 0)
	_zone.add_child(grid)
	await wait_physics_frames(2)
	_renderer._register(grid, false)
	var id := grid.get_instance_id()
	assert_true(
		_renderer._gridmaps.has(id), "GridMap is classified despite not being VisualInstance3D"
	)
	assert_gt(_renderer._gridmaps[id]["instances"].size(), 0)
	assert_eq(_renderer._gridmaps[id]["mask"], _zone.render_mask())
	assert_same(grid.mesh_library, library, "Rendering must preserve the authored tile library")
	assert_eq(grid.get_used_cells(), [Vector3i.ZERO])
	var query := PhysicsRayQueryParameters3D.create(Vector3(0, -21, 0), Vector3(0, -23, 0), 1)
	assert_false(grid.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	_zone.remove_child(grid)
	assert_false(
		_renderer._gridmaps.has(id), "Detached maps release their cached rendering instances"
	)
	_zone.add_child(grid)
	_renderer._register(grid, false)
	_renderer._register(grid, false)
	assert_eq(_renderer._gridmaps.size(), 1, "Reentered maps register exactly once")
	assert_eq(grid.get_bake_meshes().size(), 2, "Reentry must not draw duplicated baked geometry")
	grid.free()
	assert_false(_renderer._gridmaps.has(id), "Streamed map destruction removes cached render RIDs")


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


func test_private_membership_keeps_casino_hidden_outside_zone_bounds() -> void:
	var scope := ZoneScope.new()
	scope.members = [multiplayer.get_unique_id()]
	_root.add_child(scope)
	var map := RenderZone.new()
	map.name = "Map"
	map.render_layer = 20
	scope.add_child(map)
	var return_cab := _mesh(scope, Vector3.ZERO)
	_renderer._register(return_cab, false)
	var casino := _mesh(_root, Vector3.ZERO)
	_renderer._register(casino, false)
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.position = Vector3(100, 100, 100)
	assert_false(map.contains(camera.global_position))
	_renderer.update_camera(camera)
	assert_eq(camera.cull_mask, map.render_mask())
	assert_ne(camera.cull_mask & return_cab.layers, 0, "Return cab shares the private map layer")
	assert_eq(camera.cull_mask & casino.layers, 0)
	scope.replace_members([])
	_renderer.update_camera(camera)
	assert_ne(camera.cull_mask & casino.layers, 0, "Returning restores shared-zone rendering")


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


func test_handheld_layer_survives_zone_refresh_and_restores_world_classification() -> void:
	var item := _mesh(_root, Vector3(0, -6, 0))
	FirstPersonView.set_visuals(item, true)
	_renderer._register(item, true)
	_renderer.refresh_moving()
	assert_eq(item.layers, FirstPersonView.MASK)
	FirstPersonView.set_visuals(item, false)
	_renderer.refresh_moving()
	assert_eq(item.layers, _zone.render_mask())
	item.position = Vector3.ZERO
	_renderer.refresh_moving()
	assert_eq(item.layers, 1, "Authored mask must survive registration during FPS")


func test_only_the_current_rooms_lights_illuminate_the_handheld_layer() -> void:
	var casino := DirectionalLight3D.new()
	_root.add_child(casino)
	var garage := OmniLight3D.new()
	_zone.add_child(garage)
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.make_current()
	camera.position = Vector3(0, -6, 0)
	_renderer.update_camera(camera)
	_renderer._register(casino, false)
	_renderer._register(garage, false)
	assert_eq(casino.light_cull_mask & FirstPersonView.MASK, 0)
	assert_ne(garage.light_cull_mask & FirstPersonView.MASK, 0)
	assert_ne(garage.layers & FirstPersonView.MASK, 0, "Overlay camera must see its lights")
	camera.position = Vector3.ZERO
	_renderer._process(0.0)
	assert_ne(casino.light_cull_mask & FirstPersonView.MASK, 0)
	assert_eq(garage.light_cull_mask & FirstPersonView.MASK, 0)
	camera.position = Vector3(0, -6, 0)
	_renderer._process(0.0)
	assert_eq(casino.light_cull_mask & FirstPersonView.MASK, 0)
	assert_ne(garage.light_cull_mask & FirstPersonView.MASK, 0)


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


func test_five_floor_garage_excludes_casino_geometry_and_preserves_lift_paths() -> void:
	var basement := BASEMENT.instantiate() as Node3D
	_root.add_child(basement)
	var new_garage := basement.get_node("Garage") as RenderZone
	assert_eq(new_garage.scene_file_path, "res://features/procedural_rooms/garage.tscn")
	assert_false(new_garage.contains(Vector3(7.4, -1.5, -8.4)), "Sunken casino is outside")
	var patron := CharacterBody3D.new()
	_root.add_child(patron)
	patron.position = Vector3(7.4, -1.5, -8.4)
	var patron_mesh := _mesh(patron, Vector3.ZERO)
	_renderer._register(patron_mesh, true)
	assert_eq(patron_mesh.layers, 1, "Moving casino patrons do not leak into garage")
	assert_true(new_garage.has_node("Return/NetworkedEntity"))
	assert_true(new_garage.has_node("CrownGarage/Lift/NetworkedEntity"))
	var new_mesh := new_garage.get_node("CrownGarage/Structure/Floor") as VisualInstance3D
	_renderer._register(new_mesh, false)
	var camera := Camera3D.new()
	_root.add_child(camera)
	camera.position = Vector3(7.4, -1.5, -8.4)
	_renderer.update_camera(camera)
	assert_ne(camera.cull_mask & patron_mesh.layers, 0)
	assert_eq(camera.cull_mask & new_mesh.layers, 0)
	camera.global_position = new_garage.to_global(Vector3(0, 17.7, 5))
	_renderer.update_camera(camera)
	assert_ne(camera.cull_mask & new_mesh.layers, 0)
	assert_eq(camera.cull_mask & patron_mesh.layers, 0)


func test_socket_cap_freed_before_deferred_registration_is_ignored() -> void:
	var cap := _mesh(_root, Vector3.ZERO)
	var id := cap.get_instance_id()
	cap.free()
	await wait_physics_frames(2)
	assert_false(_renderer._registered.has(id), "Freed procedural cap must not enter render cache")


func test_streamed_visual_detached_before_queue_free_is_removed_from_cache() -> void:
	var mesh := _mesh(_root, Vector3.ZERO)
	_renderer._register(mesh, true)
	var id := mesh.get_instance_id()
	_root.remove_child(mesh)
	_renderer.refresh_moving()
	assert_false(_renderer._registered.has(id))
	mesh.free()


func test_static_visual_exit_restores_masks_and_reentry_registers_once() -> void:
	var light := OmniLight3D.new()
	light.layers = 3
	light.light_cull_mask = 5
	_zone.add_child(light)
	_renderer._register(light, false)
	var id := light.get_instance_id()
	assert_false(_renderer._moving_visuals.has(id))
	_zone.remove_child(light)
	assert_false(_renderer._visuals.has(id), "Static exits do not wait for a moving scan")
	assert_false(_renderer._registered.has(id))
	assert_eq(light.layers, 3)
	assert_eq(light.light_cull_mask, 5)
	_root.add_child(light)
	_renderer._register(light, true)
	_renderer._register(light, true)
	assert_true(_renderer._moving_visuals.has(id))
	assert_eq(_renderer._visuals.size(), 1)
	light.free()
	assert_false(_renderer._moving_visuals.has(id))
	assert_false(_renderer._visuals.has(id))
