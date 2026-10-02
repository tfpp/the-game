extends GutTest

const PLAYER := preload("res://core/player/player.tscn")
const MODELS := preload("res://features/player_models/feature.tscn")
const CROUCH := preload("res://features/crouch/feature.tscn")
const HAND := preload("res://features/holdables/hand.tscn")

var _models: PlayerModels
var _player: Player
var _accounts: Dictionary


func before_each() -> void:
	_accounts = Network.peer_accounts.duplicate(true)
	Network.peer_accounts = {}
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	_player.position.y = PlayerHeight.BASE_METERS * 0.5
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_models = MODELS.instantiate() as PlayerModels
	add_child_autofree(_models)
	_models.set_process(false)


func after_each() -> void:
	Network.peer_accounts = _accounts
	await get_tree().process_frame


func test_id_math_is_stable_bounded_and_varied() -> void:
	var unique: Dictionary = {}
	for identity: int in range(1, 100):
		var height := PlayerHeight.for_identity(identity, "someone")
		assert_eq(height, PlayerHeight.for_identity(identity, "renamed"))
		assert_between(height, 1.0, 3.0)
		unique[height] = true
	assert_eq(unique.size(), 11)
	assert_true(unique.has(1.0), "The shortest standing height is reachable")
	assert_true(unique.has(3.0), "The tallest standing height is reachable")
	assert_almost_eq(PlayerHeight.for_identity(1, ""), 1.8, 0.00001)
	assert_eq(PlayerHeight.for_identity(1, " Sor "), PlayerHeight.SOR_METERS)
	assert_ne(PlayerHeight.for_identity(1, "Sorcerer"), PlayerHeight.SOR_METERS)


func test_normal_bodies_stay_in_range_and_align_avatar_capsule_eyes_and_items() -> void:
	_models._process(0)
	var avatar := _player.get_node("Body/Avatar") as BlockPlayerModel
	avatar.set_process(false)
	var collider := _player.get_node("Collider") as CollisionShape3D
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	hand.net_item_id = "banana"
	for metres: float in [1.0, 3.0]:
		_models.heights = {1: metres}
		for body: String in PlayerModels.VALID_BODY_TYPES:
			_models.body_types = {1: body}
			for frame: int in 5:
				_models._process(0)
				avatar._process(0)
			var factor := _models.height_scale_for(1)
			var standing := factor * PlayerHeight.BASE_METERS
			assert_between(standing, 1.0, 3.0)
			var capsule := collider.shape as CapsuleShape3D
			assert_almost_eq(capsule.height, standing, 0.00001)
			assert_almost_eq(collider.global_position.y - capsule.height * 0.5, 0.0, 0.00001)
			assert_almost_eq(avatar.height_scale(), factor, 0.00001)
			var bounds: AABB
			if body == "penguin":
				var foot := avatar.get_node("Rig/LeftLeg/Foot") as MeshInstance3D
				var face := avatar.get_node("Rig/Torso/Head/Face") as MeshInstance3D
				bounds = foot.global_transform * foot.get_aabb()
				bounds = bounds.merge(face.global_transform * face.get_aabb())
			else:
				bounds = avatar.human.surface.global_transform * avatar.human.surface.get_aabb()
			assert_almost_eq(bounds.position.y, 0.0, 0.00001)
			assert_almost_eq(bounds.size.y, standing, 0.00001)
			assert_almost_eq(
				(_player.get_node("Camera") as Camera3D).global_position.y, 1.6256 * factor, 0.00001
			)
			assert_almost_eq(hand._aim_origin(_player).y, 1.6256 * factor, 0.00001)
			for third_person: bool in [false, true]:
				(_player.get_node("Body") as Node3D).visible = third_person
				hand._process(0)
				assert_almost_eq(hand.global_basis.get_scale().x, factor, 0.00001)


func test_offline_default_is_preserved_but_authenticated_id_one_gets_variety() -> void:
	_models._process(0)
	assert_eq(_models.heights[1], PlayerHeight.BASE_METERS)
	Network.peer_accounts[1] = {"account_id": 1, "name": "Alice"}
	_models._assign_height(1)
	assert_almost_eq(_models.heights[1], 1.8, 0.00001)


func test_range_endpoints_apply_independently_to_late_players() -> void:
	_models._process(0)
	for peer: int in [8, 11]:
		var remote := PLAYER.instantiate() as Player
		remote.name = str(peer)
		remote.display_name = "Player%d" % peer
		remote.position = Vector3(peer * 4, PlayerHeight.BASE_METERS * 0.5, 0)
		remote.set_multiplayer_authority(peer)
		add_child_autofree(remote)
		remote.set_physics_process(false)
		remote.set_process(false)
		_models._process(0)
		var expected := 3.0 if peer == 8 else 1.0
		assert_almost_eq(_models.heights[peer], expected, 0.00001)
		var avatar := remote.get_node("Body/Avatar") as BlockPlayerModel
		avatar._process(0)
		assert_almost_eq(avatar.height_scale() * PlayerHeight.BASE_METERS, expected, 0.00001)
		assert_almost_eq(
			remote.get_node("Nameplate").position.y,
			expected - PlayerHeight.BASE_METERS * 0.5 + 0.35,
			0.00001
		)
	assert_eq(_models.height_scale_for(1), 1.0)


func test_server_derives_account_height_without_exposing_id_or_trusting_player_name() -> void:
	Network.peer_accounts = {
		1: {"account_id": 42, "name": "Alice"}, 9: {"account_id": 42, "name": "Alice"}
	}
	_player.display_name = "Sor"
	_models._process(0)
	_models._assign_height(9)
	assert_eq(_models.heights[1], _models.heights[9])
	assert_eq(_models.heights[1], PlayerHeight.for_identity(42, "Alice"))
	assert_false(_models.heights.has("account_id"))
	assert_eq(
		_models.entity._evaluate(1, &"height", {"value": 100}),
		NetworkedEntity.Result.UNKNOWN_ACTION
	)
	_models._remove_peer(9)
	assert_false(_models.heights.has(9))
	_models._assign_height(9)
	assert_eq(_models.heights[1], _models.heights[9])
	_models._reset_session(Network.Mode.OFFLINE)
	assert_true(_models.heights.is_empty())


func test_sor_capsule_avatar_eyes_and_equipment_anchor_at_feet_in_every_body() -> void:
	Network.peer_accounts[1] = {"account_id": 42, "name": "Sor"}
	_models._process(0)
	var avatar := _player.get_node("Body/Avatar") as BlockPlayerModel
	avatar.set_process(false)
	var collider := _player.get_node("Collider") as CollisionShape3D
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.set_process(false)
	hand.net_item_id = "banana"
	for body: String in PlayerModels.VALID_BODY_TYPES:
		_models.body_types = {1: body}
		_models._process(0)
		avatar._process(0)
		var capsule := collider.shape as CapsuleShape3D
		assert_almost_eq(capsule.height, 2.4384, 0.00001)
		assert_lte(capsule.radius * 2, capsule.height)
		assert_almost_eq(collider.global_position.y - capsule.height * 0.5, 0.0, 0.00001)
		var factor := _models.height_scale_for(1)
		assert_almost_eq(avatar.height_scale(), factor, 0.00001)
		if body == "penguin":
			var foot := avatar.get_node("Rig/LeftLeg/Foot") as MeshInstance3D
			var bounds: AABB = foot.global_transform * foot.get_aabb()
			assert_almost_eq(bounds.position.y, 0.0, 0.00001)
		else:
			var bounds: AABB = (
				avatar.human.surface.global_transform * avatar.human.surface.get_aabb()
			)
			assert_almost_eq(bounds.position.y, 0.0, 0.00001)
			assert_almost_eq(bounds.size.y, PlayerHeight.SOR_METERS, 0.00001)
		assert_almost_eq(
			(_player.get_node("Camera") as Camera3D).global_position.y, 1.6256 * factor, 0.00001
		)
		assert_almost_eq(hand._aim_origin(_player).y, 1.6256 * factor, 0.00001)
		hand._process(0)
		assert_almost_eq(hand.global_basis.get_scale().x, factor, 0.00001)
		assert_almost_eq((_player.get_node("Camera") as Camera3D).near, 0.05, 0.00001)
		(_player.get_node("Body") as Node3D).show()
		hand._process(0)
		assert_almost_eq(hand.global_basis.get_scale().x, factor, 0.00001)
		(_player.get_node("Body") as Node3D).hide()


func test_sor_crouch_and_respawn_keep_scaled_eyes_without_mutating_shared_movement() -> void:
	var fresh := PLAYER.instantiate() as Player
	fresh.position = Vector3(100, 0.9144, 0)
	add_child_autofree(fresh)
	fresh.remove_from_group(&"local_player")
	fresh.remove_from_group(&"players")
	fresh.set_physics_process(false)
	fresh.set_process(false)
	Network.peer_accounts[1] = {"name": "Sor"}
	_models._process(0)
	var crouch := CROUCH.instantiate() as Crouch
	add_child_autofree(crouch)
	crouch.set_physics_process(false)
	crouch._physics_process(0)
	assert_true(crouch.set_crouched(true))
	var factor := _models.height_scale_for(1)
	for tick: int in 60:
		crouch._physics_process(1.0 / 60)
		_models._process(0)
	assert_almost_eq(_player.movement.eye_height, Crouch.EYE_HEIGHT * factor, 0.01)
	var capsule := (_player.get_node("Collider") as CollisionShape3D).shape as CapsuleShape3D
	assert_almost_eq(capsule.height, PlayerHeight.SOR_METERS * Crouch.HEIGHT_SCALE, 0.00001)
	assert_eq(fresh.movement.eye_height, 64.0)
	assert_true(crouch.set_crouched(false))
	for tick: int in 60:
		crouch._physics_process(1.0 / 60)
		_models._process(0)
	assert_almost_eq(_player.movement.eye_height, 64 * factor, 0.01)
	_player.remove_from_group(&"players")
	_player.remove_from_group(&"local_player")
	fresh.add_to_group(&"players")
	fresh.add_to_group(&"local_player")
	crouch._physics_process(0)
	_models._process(0)
	assert_almost_eq(fresh.movement.eye_height, 64 * factor, 0.001)


func test_generated_gun_mount_and_aim_use_the_same_height_without_changing_stats() -> void:
	Network.peer_accounts[1] = {"name": "Sor"}
	_models._process(0)
	var rig := preload("res://features/gun_machine/gun_rig.tscn").instantiate() as GunRig
	rig.peer_id = 1
	add_child_autofree(rig)
	rig.set_process(false)
	rig.equip(GunGenerator.ray_gun())
	var stats := rig.net_stats.duplicate(true)
	var factor := _models.height_scale_for(1)
	assert_almost_eq(rig._mount_transform(_player).basis.get_scale().x, factor, 0.00001)
	assert_almost_eq(rig._aim_origin(_player).y, 1.6256 * factor, 0.00001)
	var remote := PLAYER.instantiate() as Player
	remote.name = "9"
	remote.position.y = PlayerHeight.BASE_METERS * 0.5
	remote.set_multiplayer_authority(9)
	add_child_autofree(remote)
	_models.heights = {1: PlayerHeight.SOR_METERS, 9: PlayerHeight.SOR_METERS}
	_models._process(0)
	var mount := rig._mount_transform(remote)
	assert_almost_eq(mount.basis.get_scale().x, factor, 0.00001)
	assert_gt(mount.origin.y, PlayerHeight.BASE_METERS, "Remote gun follows Sor's tall body")
	assert_eq(rig.net_stats, stats)
	# Main's authored plasma model uses the shared holdable mount and arm helpers.
	stats["ammo_type"] = GunGenerator.AmmoType.PLASMA
	stats["barrel_count"] = 2
	rig.equip(stats)
	for owner: Player in [_player, remote]:
		var avatar := owner.get_node("Body/Avatar") as BlockPlayerModel
		avatar._process(0)
		rig.peer_id = owner.get_multiplayer_authority()
		rig._process(0)
		assert_true(rig.has_hand_grips())
		assert_almost_eq(rig.global_basis.get_scale().x, factor, 0.00001)
		assert_gt(rig.global_position.y, 0.3)
		assert_eq(rig.net_stats, stats)
		var human := rig._arms.human if rig._arms.visible else avatar.human
		for right: bool in [true, false]:
			var target := rig as Node3D if right else rig.support_grip()
			var offset := Vector3(0.055 if right else -0.055, -0.04, 0.055)
			var bone := human.skeleton.find_bone("HandR" if right else "HandL")
			var wrist := human.skeleton.to_global(human.skeleton.get_bone_global_pose(bone).origin)
			assert_almost_eq(wrist, target.to_global(offset), Vector3.ONE * 0.002)


func test_snapshot_applies_to_late_avatar_and_nameplate() -> void:
	var remote := PLAYER.instantiate() as Player
	remote.name = "9"
	remote.display_name = "Sor"
	remote.set_multiplayer_authority(9)
	add_child_autofree(remote)
	_models.heights = {9: PlayerHeight.SOR_METERS}
	_models.body_types = {9: "penguin"}
	_models._process(0)
	var avatar := remote.get_node("Body/Avatar") as BlockPlayerModel
	avatar._process(0)
	assert_almost_eq(avatar.height_scale(), 4.0 / 3, 0.00001)
	assert_almost_eq(
		remote.get_node("Nameplate").position.y,
		-PlayerHeight.BASE_METERS * 0.5 + 2.4384 + 0.35,
		0.00001
	)
	assert_eq(_models.height_scale_for(1), 1.0)
