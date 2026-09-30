extends GutTest

const Layout := preload("res://features/procedural_rooms/world_layout.gd")
const PLAYER := preload("res://core/player/player.tscn")
const INTERACTION := preload("res://features/interaction/interaction.gd")


func test_all_five_panel_buttons_select_by_aim_and_b1_starts_return_trip() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var world := Layout.build(root)
	var lift := world.get_node("Lift") as ProceduralMovingLift
	lift.set_physics_process(false)
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	root.add_child(player)
	player.set_physics_process(false)
	player.global_position = lift.cab.global_position + Vector3(0, .95, -.65)
	player.net_position = player.global_position
	Controls.device = Controls.Device.GAMEPAD
	Controls.playing = true
	var interaction := INTERACTION.new()
	add_child_autofree(interaction)
	for index: int in 5:
		var button := lift.cab.get_node("Floor%d" % index) as Node3D
		var eye := (
			player.global_position
			+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * .5)
		)
		var direction := (button.global_position - eye).normalized()
		player.yaw = atan2(-direction.x, -direction.z)
		player.pitch = asin(direction.y)
		assert_same(interaction._find_target(), button, "Aim selects B%d" % (5 - index))
		for other: int in 5:
			if other != index:
				assert_false(lift.cab.get_node("Floor%d" % other).call("aimed_at", player))
	assert_eq(lift.cab.get_node("Floor4").call("interaction_text"), "Already at B1")
	lift.net_floor = 0
	interaction.use()
	assert_eq(lift.net_target, 4, "Normal Use selects B1 from another floor")
	assert_eq(lift.net_phase, ProceduralMovingLift.Phase.CLOSING)
	assert_false(lift.doorway_occupied(), "Panel selection stays clear of door interlocks")
	Controls.playing = false
	Controls.device = Controls.Device.KEYBOARD


func test_panel_texture_uv_and_button_centres_match() -> void:
	var scene := (
		preload("res://features/procedural_rooms/elevator_panel.tscn").instantiate() as Node3D
	)
	var face := scene.get_node("Face") as MeshInstance3D
	var material := face.material_override as StandardMaterial3D
	assert_eq(material.albedo_texture.get_size(), Vector2(128, 128))
	assert_false(material.uv1_world_triplanar)
	assert_eq(material.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
	assert_eq((face.mesh as QuadMesh).size, Vector2(.6, 1))
	scene.free()


func test_cab_faces_stop_inside_closed_doors_and_all_landing_sills_have_support() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var world := Layout.build(root)
	var lift := world.get_node("Lift") as ProceduralMovingLift
	var visual := lift.cab.get_node("ElevatorCabModel/Visual") as MeshInstance3D
	assert_lte(visual.mesh.get_aabb().end.z, 1.2801, "Cab stops at closed door inner face")
	await wait_physics_frames(2)
	var space := world.get_world_3d().direct_space_state
	for floor: int in 5:
		for z: float in [-8.2, -8.1, -8.0, -7.9]:
			var ray := PhysicsRayQueryParameters3D.create(
				Vector3(0, floor * 4 + .2, z), Vector3(0, floor * 4 - .2, z)
			)
			assert_false(space.intersect_ray(ray).is_empty(), "Supported landing threshold")
		var interior := PhysicsRayQueryParameters3D.create(
			Vector3(0, floor * 4 + .1, -8.25), Vector3(0, floor * 4 - .1, -8.25)
		)
		interior.exclude = [lift.cab.get_rid()]
		assert_true(space.intersect_ray(interior).is_empty(), "Static landing stays outside cab")
