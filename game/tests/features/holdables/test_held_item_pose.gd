extends GutTest

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const HAND_SCENE := preload("res://features/holdables/hand.tscn")

var _player: Player
var _hand: Hand


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_hand = HAND_SCENE.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hand.set_process(false)


func after_each() -> void:
	# View replacements queue old meshes for deletion; flush before orphan checks.
	await get_tree().process_frame


func test_all_models_attach_the_primary_grip_to_the_right_hand() -> void:
	for def: ItemDefinition in ItemCatalog.DEFINITIONS:
		_equip(def.id)
		var grip := _hand._view.get_node("Grip") as Marker3D
		assert_true(grip.global_position.is_equal_approx(_hand.global_position), def.id)
		assert_true(grip.global_basis.is_equal_approx(_hand.global_basis), def.id)


func test_support_hand_tracks_each_items_support_marker() -> void:
	for id: String in ["pistol", "smg", "shotgun", "awp", "ball"]:
		_equip(id)
		var support := _hand._view.get_node("SupportGrip") as Marker3D
		var glove := _hand.get_node("Arms/LeftGlove") as Node3D
		assert_true(glove.visible)
		assert_true(glove.global_transform.is_equal_approx(support.global_transform), id)
		var human := _hand._arms.human
		var wrist := human.skeleton.find_bone("HandL")
		var position := human.skeleton.to_global(human.skeleton.get_bone_global_pose(wrist).origin)
		assert_almost_eq(
			position, support.to_global(Vector3(-0.055, -0.04, 0.055)), Vector3.ONE * 0.002, id
		)
	_equip("banana")
	assert_false((_hand.get_node("Arms/LeftGlove") as Node3D).visible)


func test_first_person_grip_follows_camera_after_its_update() -> void:
	var camera := _player.get_node("Camera") as Camera3D
	camera.global_transform = Transform3D(HeldItemPose.aim_basis(0.7, -0.4), Vector3(2, 3, 4))
	_equip("pistol")
	var expected := camera.global_transform * HeldItemPose.FIRST_PERSON_OFFSET
	assert_true(_hand.global_position.is_equal_approx(expected))
	assert_gt(_hand.process_priority, 10, "Mount after player and third-person camera updates")


func test_third_person_item_stays_at_body_when_camera_pulls_back() -> void:
	var body := _player.get_node("Body") as Node3D
	body.visible = true
	_player.yaw = 0.4
	_player.pitch = -0.35
	_equip("shotgun")
	var before := _hand.global_transform
	var camera := _player.get_node("Camera") as Camera3D
	camera.global_position += Vector3(0, 0, 3)
	_hand._process(0.0)
	assert_true(_hand.global_transform.is_equal_approx(before))
	var local_grip := (
		Basis(Vector3.UP, -_player.yaw) * (_hand.global_position - _player.global_position)
	)
	assert_lt(local_grip.z, 0.0, "Held in front of the avatar")
	assert_lt(local_grip.y, 0.5, "Held at chest height, not above the head")


func test_remote_item_tracks_pitch_and_yaw_without_a_camera() -> void:
	var remote := PLAYER_SCENE.instantiate() as Player
	remote.name = "2"
	remote.set_multiplayer_authority(2)
	add_child_autofree(remote)
	remote.set_process(false)
	await get_tree().process_frame
	assert_null(remote.get_node_or_null("Camera"))
	remote.net_pitch = 0.55
	(remote.get_node("Body") as Node3D).rotation.y = 1.2
	_hand.peer_id = 2
	_equip("smg")
	var forward := -_hand.global_basis.z
	assert_true(forward.is_equal_approx(ThrowMath.aim_direction(1.2, 0.55)))


func test_aim_and_drop_origins_do_not_depend_on_view_camera() -> void:
	_player.net_position = Vector3(4, 2, -3)
	var before := _hand._aim_origin(_player)
	(_player.get_node("Camera") as Camera3D).global_position = Vector3(40, 50, 60)
	(_player.get_node("Body") as Node3D).visible = true
	assert_eq(_hand._aim_origin(_player), before)
	var grip := HeldItemPose.world_grip(_player.net_position, 0.0, 0.0)
	assert_lt(grip.origin.distance_to(_player.net_position), 0.6)


func test_fps_items_and_arms_use_separate_depth_then_restore_in_third_person() -> void:
	_equip("pistol")
	var overlay := _player.get_node("FirstPersonView") as FirstPersonView
	var camera := _player.get_node("Camera") as Camera3D
	overlay._process(0.0)
	assert_true(overlay.viewport.transparent_bg)
	assert_eq(overlay.viewport.world_3d, _player.get_world_3d())
	assert_eq(camera.cull_mask & FirstPersonView.MASK, 0)
	assert_eq(overlay.camera.cull_mask, FirstPersonView.MASK)
	_assert_visual_layers(_hand, FirstPersonView.MASK)
	var aim := _hand._aim_origin(_player)
	_player.yaw = 0.1
	_player.velocity = Vector3(8, 0, 0)
	_hand._process(1.0 / 60.0)
	assert_eq(_hand._aim_origin(_player), aim, "Sway cannot change the shot origin")
	(_player.get_node("Body") as Node3D).visible = true
	_hand._process(1.0 / 60.0)
	overlay._process(0.0)
	_assert_visual_layers(_hand, 1)
	assert_eq(overlay.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)


func _assert_visual_layers(node: Node, mask: int) -> void:
	if node is GeometryInstance3D:
		assert_eq((node as GeometryInstance3D).layers, mask, str(node.get_path()))
	for child: Node in node.get_children():
		_assert_visual_layers(child, mask)


func test_every_weapon_muzzle_points_forward_and_is_attached_to_model() -> void:
	for def: ItemDefinition in ItemCatalog.DEFINITIONS:
		if def.category != ItemDefinition.Category.WEAPON:
			continue
		var view := def.view_scene.instantiate() as Node3D
		add_child_autofree(view)
		var muzzle := view.get_node("Muzzle") as Marker3D
		assert_lt(muzzle.position.z, -0.15, def.id)
		assert_almost_eq(muzzle.position.x, 0.0, 0.001, def.id)
		assert_true((-muzzle.basis.z).is_equal_approx(Vector3.FORWARD))


func test_dropped_models_have_enough_ground_clearance() -> void:
	for def: ItemDefinition in ItemCatalog.DEFINITIONS:
		var view := def.view_scene.instantiate() as Node3D
		add_child_autofree(view)
		for child: Node in view.get_children():
			var mesh := child as MeshInstance3D
			if mesh == null:
				continue
			var bounds: AABB = mesh.transform * mesh.get_aabb()
			assert_gte(bounds.position.y + def.ground_clearance, -0.001, def.id + "/" + mesh.name)


func _equip(id: String) -> void:
	_hand.net_item_id = id
	_hand._process(0.0)
