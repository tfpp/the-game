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
		assert_between(height, 1.6, 2.11)
		unique[height] = true
	assert_eq(unique.size(), 11)
	assert_eq(PlayerHeight.for_identity(1, ""), PlayerHeight.BASE_METERS)
	assert_eq(PlayerHeight.for_identity(1, " Sor "), PlayerHeight.SOR_METERS)
	assert_ne(PlayerHeight.for_identity(1, "Sorcerer"), PlayerHeight.SOR_METERS)


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
		assert_almost_eq(capsule.height, 0.2032, 0.00001)
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
		assert_lt((_player.get_node("Camera") as Camera3D).near, 0.01)
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
	assert_lt(mount.origin.y, 0.3, "Remote gun follows the tiny player's feet")
	assert_eq(rig.net_stats, stats)


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
	assert_almost_eq(avatar.height_scale(), 1.0 / 9, 0.00001)
	assert_almost_eq(
		remote.get_node("Nameplate").position.y,
		-PlayerHeight.BASE_METERS * 0.5 + 0.2032 + 0.35,
		0.00001
	)
	assert_eq(_models.height_scale_for(1), 1.0)
