extends GutTest

const PLAYER_SCENE := preload("res://core/player/player.tscn")
const HAND_SCENE := preload("res://features/holdables/hand.tscn")
const FEATURE_SCENE := preload("res://features/player_models/feature.tscn")

var _player: Player
var _feature: Node
var _model: BlockPlayerModel


func before_each() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_feature = FEATURE_SCENE.instantiate()
	add_child_autofree(_feature)
	_feature._process(0.0)
	_model = _player.get_node("Body/Avatar") as BlockPlayerModel
	_model.set_process(false)


func test_model_replaces_visuals_without_changing_collision_or_authority() -> void:
	assert_not_null(_model)
	assert_false((_player.get_node("Body/Mesh") as Node3D).visible)
	assert_false((_player.get_node("Body/Visor") as Node3D).visible)
	assert_true((_player.get_node("Collider") as CollisionShape3D).shape is CapsuleShape3D)
	assert_eq(_player.get_multiplayer_authority(), 1)
	_feature._process(0.0)
	assert_eq(_player.get_node("Body").get_child_count(), 3, "Attach once per player")


func test_first_person_hides_avatar_and_third_person_reveals_it() -> void:
	var body := _player.get_node("Body") as Node3D
	assert_false(_model.is_visible_in_tree())
	body.visible = true
	assert_true(_model.is_visible_in_tree())
	assert_false((_player.get_node("Body/Mesh") as Node3D).visible)


func test_late_player_starts_in_underwear_with_its_own_rig() -> void:
	var remote := PLAYER_SCENE.instantiate() as Player
	remote.name = "7"
	remote.set_multiplayer_authority(7)
	add_child_autofree(remote)
	_feature._process(0.0)
	var other := remote.get_node("Body/Avatar") as BlockPlayerModel
	assert_not_null(other)
	assert_ne(other, _model)
	assert_eq(other.skin_color, PlayerSkin.TONES[PlayerSkin.index_for_id(7)])
	assert_eq(_model.skin_color, PlayerSkin.TONES[PlayerSkin.index_for_id(1)])
	assert_true(other.is_visible_in_tree())


func test_jump_landing_blends_back_into_idle() -> void:
	_model.animate(0.1, Vector3(0, 6, 0), false, 8.0)
	assert_eq(_model.locomotion, &"jump")
	assert_gt(absf(_model.get_node("Rig/LeftLeg").rotation.x), 0.1)
	_model.animate(0.016, Vector3.ZERO, true, 8.0)
	assert_lt(_model.get_node("Rig").scale.y, 1.0, "Landing compresses the body briefly")
	for index: int in 30:
		_model.animate(0.016, Vector3.ZERO, true, 8.0)
	assert_eq(_model.locomotion, &"idle")
	assert_almost_eq(_model.get_node("Rig").scale.y, 1.0, 0.001)
	assert_almost_eq(_model.get_node("Rig/LeftLeg").rotation.x, 0.0, 0.002)


func test_held_items_use_skinned_third_person_arms_and_first_person_hand_rig() -> void:
	(_player.get_node("Body") as Node3D).visible = true
	var hand := HAND_SCENE.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	hand.net_item_id = "banana"
	hand._process(0.0)
	_model._process(0.1)
	hand._process(0.0)
	assert_false(_model.get_node("Rig/Torso/RightArm").visible)
	assert_true(_model.get_node("Rig/Torso/LeftArm").visible)
	assert_eq(hand._arms._sleeve.albedo_color, _model.shirt_color)
	assert_eq(hand._arms._glove.albedo_color, _model.skin_color)
	assert_false(hand._arms.visible)
	assert_false(bool(_model.human.material.get_shader_parameter("hide_right_arm")))
	hand.net_item_id = "shotgun"
	hand._process(0.0)
	_model._process(0.1)
	assert_false(_model.get_node("Rig/Torso/LeftArm").visible)
	hand._process(0.0)
	assert_false(bool(_model.human.material.get_shader_parameter("hide_left_arm")))
	(_player.get_node("Body") as Node3D).visible = false
	hand._process(0.0)
	assert_true(hand._arms.visible)
	assert_eq(hand._arms.human.surface.mesh, _model.human.surface.mesh)
	assert_true(bool(hand._arms.human.material.get_shader_parameter("arms_only")))
	assert_eq(hand._arms.human.skeleton.get_bone_count(), 45)
	hand.net_item_id = ""
	hand._process(0.0)
	_model._process(0.1)
	assert_true(_model.get_node("Rig/Torso/RightArm").visible)
	assert_true(_model.get_node("Rig/Torso/LeftArm").visible)
	await get_tree().process_frame


func test_remote_ground_probe_keeps_jump_pose_through_apex() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(10, 1, 10)
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	add_child_autofree(floor_body)
	await wait_physics_frames(2)
	_player.net_position.y = _player.movement.hull_height_m() * 0.5
	_player.net_velocity = Vector3.ZERO
	assert_true(_model._remote_grounded())
	_player.net_velocity.y = 6.0
	assert_false(_model._remote_grounded(), "Takeoff counts as airborne even near the floor")
	_player.net_position.y += 2.0
	_player.net_velocity.y = 0.0
	assert_false(_model._remote_grounded(), "Zero vertical speed at the apex is not grounded")


func test_account_id_keeps_skin_across_peer_changes_and_spawn_data_carries_only_tone() -> void:
	var manager: Node = load("res://features/holdables/holdables.gd").new()
	var original := Network.peer_accounts.duplicate(true)
	Network.peer_accounts[501] = {"account_id": 42}
	Network.peer_accounts[902] = {"account_id": 42}
	Network.peer_accounts[903] = {"account_id": 43}
	var first: Dictionary = manager._hand_data(501)
	var reconnected: Dictionary = manager._hand_data(902)
	var different: Dictionary = manager._hand_data(903)
	assert_eq(first["skin_index"], reconnected["skin_index"])
	assert_ne(first["skin_index"], different["skin_index"])
	assert_eq(first.size(), 2)
	assert_false(first.has("account_id"))
	var spawned := manager._spawn_hand(reconnected) as Hand
	add_child_autofree(spawned)
	assert_eq(spawned.peer_id, 902)
	assert_eq(spawned.skin_tone_index(), PlayerSkin.index_for_id(42))
	assert_eq(manager._hand_data(1)["skin_index"], PlayerSkin.index_for_id(1))
	Network.peer_accounts = original
	manager.free()


func test_skin_changes_update_exposed_body_without_changing_clothes_or_underwear() -> void:
	_model.set_clothing("shirt:4", "pants:3")
	_model.set_skin_index(7)
	assert_eq(_model.skin_color, PlayerSkin.TONES[7])
	assert_eq(_model.shirt_color, ClothingCatalog.COLORS[4])
	assert_eq(_model.pants_color, ClothingCatalog.COLORS[3])
	assert_eq(_model.human.material.get_shader_parameter("skin_tint"), PlayerSkin.TONES[7])
	_model.set_clothing("", "")
	assert_eq(_model.sleeve_color(), PlayerSkin.TONES[7])
	assert_eq(_model.pants_color, PlayerSkin.TONES[7])
	assert_false(bool(_model.human.material.get_shader_parameter("pants_equipped")))


func test_girl_body_type_narrows_shoulders_widens_hips_and_grows_hair() -> void:
	var default_shoulder := (_model.get_node("Rig/Torso/RightArm") as Node3D).position.x
	var default_hip := (_model.get_node("Rig/RightLeg") as Node3D).position.x
	var default_hair := _model.human.shape_weight("LongHair")
	_model.set_body_type("girl")
	assert_eq(_model.body_type, &"girl")
	var shoulder := (_model.get_node("Rig/Torso/RightArm") as Node3D).position.x
	var hip := (_model.get_node("Rig/RightLeg") as Node3D).position.x
	assert_lt(shoulder, default_shoulder, "Girl model has narrower shoulders")
	assert_gt(hip, default_hip, "Girl model has wider hips")
	assert_gt(_model.human.shape_weight("LongHair"), default_hair, "Girl model sculpts longer hair")
	assert_eq(_model.human.shape_weight("Feminine"), 1.0)


func test_body_type_switch_preserves_clothing_and_skin() -> void:
	_model.set_clothing("shirt:4", "pants:3")
	_model.set_skin_index(7)
	_model.set_body_type("girl")
	assert_eq(_model.shirt_color, ClothingCatalog.COLORS[4])
	assert_eq(_model.pants_color, ClothingCatalog.COLORS[3])
	assert_eq(_model.skin_color, PlayerSkin.TONES[7])
	assert_true(
		bool(_model.human.material.get_shader_parameter("pants_equipped")),
		"Pants stay equipped across a body type switch"
	)


func test_unrecognized_body_type_falls_back_to_default() -> void:
	_model.set_body_type("girl")
	_model.set_body_type("not-a-real-type")
	assert_eq(_model.body_type, &"default")


func test_request_body_type_validates_value_and_replicates() -> void:
	var models := _feature as PlayerModels
	models.request_body_type("girl")
	assert_eq(models.type_for(1), "girl")
	models.request_body_type("nonsense")
	assert_eq(models.type_for(1), "girl", "Invalid values are ignored")
	models.request_body_type("default")
	assert_eq(models.type_for(1), "default")


func test_request_body_type_accepts_penguin() -> void:
	var models := _feature as PlayerModels
	models.request_body_type("penguin")
	assert_eq(models.type_for(1), "penguin")


func test_penguin_body_type_shrinks_the_rig_and_builds_a_costume() -> void:
	assert_almost_eq(_model.height_scale(), 1.0, 0.0001)
	_model.set_body_type("penguin")
	assert_eq(_model.body_type, &"penguin")
	assert_almost_eq(_model.height_scale(), BlockPlayerModel.PENGUIN_HEIGHT_SCALE, 0.0001)
	assert_not_null(_model.get_node_or_null("Rig/Torso/RightArm/Flipper"))
	assert_not_null(_model.get_node_or_null("Rig/RightLeg/Foot"))
	assert_null(_model.get_node_or_null("Rig/Torso/Hem"), "Penguin costume has no clothing boxes")
	_model.animate(0.016, Vector3.ZERO, true, 8.0)
	assert_almost_eq(_model.get_node("Rig").scale.x, BlockPlayerModel.PENGUIN_HEIGHT_SCALE, 0.001)
	assert_eq(_model.sleeve_color(), Color("1c1c1c"))


func test_penguin_body_type_ignores_clothing_but_remembers_it() -> void:
	_model.set_clothing("shirt:4", "pants:3")
	_model.set_body_type("penguin")
	assert_not_null(_model.get_node_or_null("Rig/LeftLeg/Foot"))
	assert_null(_model.get_node_or_null("Rig/LeftLeg/Underwear"))
	_model.set_body_type("default")
	assert_eq(
		_model.shirt_color, ClothingCatalog.COLORS[4], "Clothing choice survives being a penguin"
	)
	assert_eq(_model.pants_color, ClothingCatalog.COLORS[3])


func test_first_person_view_model_sits_closer_to_the_camera_for_penguin() -> void:
	(_player.get_node("Body") as Node3D).visible = false
	var hand := HAND_SCENE.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	var camera_y: float = (_player.get_node("Camera") as Node3D).global_position.y
	var default_drop: float = camera_y - hand._mount_transform(_player).origin.y
	assert_gt(default_drop, 0.0)
	_model.set_body_type("penguin")
	var penguin_drop: float = camera_y - hand._mount_transform(_player).origin.y
	assert_lt(penguin_drop, default_drop, "Penguin view model sits higher, closer to the camera")
	assert_almost_eq(penguin_drop, default_drop * BlockPlayerModel.PENGUIN_HEIGHT_SCALE, 0.001)


func test_girl_collider_is_smaller_and_switching_back_restores_it() -> void:
	var models := _feature as PlayerModels
	var collider := _player.get_node("Collider") as CollisionShape3D
	var normal := collider.shape as CapsuleShape3D
	var normal_radius := normal.radius
	var normal_height := normal.height
	models.request_body_type("girl")
	models._process(0.0)
	var girl := collider.shape as CapsuleShape3D
	assert_almost_eq(girl.radius, normal_radius * 0.6, 0.001)
	assert_almost_eq(girl.height, normal_height * 0.75, 0.001)
	assert_almost_eq(collider.position.y - girl.height * 0.5, -normal_height * 0.5, 0.001)
	models.request_body_type("default")
	models._process(0.0)
	var restored := collider.shape as CapsuleShape3D
	assert_almost_eq(restored.radius, normal_radius, 0.001)
	assert_almost_eq(restored.height, normal_height, 0.001)
	assert_almost_eq(collider.position.y, 0.0, 0.001)


func test_new_players_spawn_with_their_already_requested_body_type() -> void:
	var models := _feature as PlayerModels
	var remote := PLAYER_SCENE.instantiate() as Player
	remote.name = "9"
	remote.set_multiplayer_authority(9)
	add_child_autofree(remote)
	models.body_types = {9: "girl"}
	_feature._process(0.0)
	var other := remote.get_node("Body/Avatar") as BlockPlayerModel
	assert_eq(other.body_type, &"girl")
	assert_eq(_model.body_type, &"default", "Peer 1's own choice is unaffected")


func test_shoulders_match_rendered_avatar_between_physics_ticks() -> void:
	var marker := _model.get_node("Rig/Torso/RightShoulder") as Node3D
	marker.get_global_transform_interpolated()
	var largest_error := 0.0
	for frame: int in 5:
		await get_tree().physics_frame
		_player.position.x += 0.1
		await get_tree().process_frame
		var rendered := marker.get_global_transform_interpolated().origin
		largest_error = maxf(largest_error, _model.shoulder_position(true).distance_to(rendered))
	assert_lt(largest_error, 0.001, "Held sleeves must attach to the interpolated shoulder")
