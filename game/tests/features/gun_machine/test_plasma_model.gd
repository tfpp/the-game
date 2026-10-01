extends GutTest

const PLAYER := preload("res://core/player/player.tscn")
const RIG := preload("res://features/gun_machine/gun_rig.tscn")

var _player: Player
var _rig: GunRig


func before_each() -> void:
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_process(false)
	_player.set_physics_process(false)
	_rig = RIG.instantiate() as GunRig
	_rig.peer_id = 1
	add_child_autofree(_rig)
	_rig.set_process(false)
	_rig.net_stats = _stats()


func after_each() -> void:
	await get_tree().process_frame


func test_plasma_variants_select_only_the_double_barrel_asset() -> void:
	for barrels: int in range(1, 5):
		for automatic: bool in [false, true]:
			var stats := _stats()
			stats["barrel_count"] = barrels
			stats["is_automatic"] = automatic
			var view := GunView.build(stats)
			add_child_autofree(view)
			assert_eq(view.has_node("Grip"), barrels == 2)
			assert_true(view.has_node("Muzzle"))


func test_first_person_hands_reach_both_grips_and_holster_hides_them() -> void:
	(_player.get_node("Body") as Node3D).visible = false
	_rig._process(0.0)
	var grip := _rig._view.get_node("Grip") as Marker3D
	assert_true(grip.global_transform.is_equal_approx(_rig.global_transform))
	assert_true(_rig._arms.visible)
	_check_wrists(_rig._arms.human)
	_rig.holster()
	_rig._process(0.0)
	assert_false(_rig.visible)
	assert_false(_rig._arms.visible)
	assert_false(_rig.has_hand_grips())
	_rig.request_equip_rig()
	_rig._process(0.0)
	assert_true(_rig.has_hand_grips())
	_check_wrists(_rig._arms.human)


func test_third_person_uses_avatar_hands_and_stays_with_body() -> void:
	var body := _player.get_node("Body") as Node3D
	body.visible = true
	var avatar := BlockPlayerModel.new()
	avatar.name = "Avatar"
	body.add_child(avatar)
	_rig._process(0.0)
	assert_false(_rig._arms.visible, "Use the actual avatar arms in third person")
	_check_wrists(avatar.human)
	var before := _rig.global_transform
	(_player.get_node("Camera") as Node3D).position += Vector3(0, 0, 5)
	_rig._process(0.0)
	assert_true(_rig.global_transform.is_equal_approx(before))
	_rig.net_stats["barrel_count"] = 3
	_rig._process(0.0)
	assert_false(_rig.has_hand_grips())
	assert_false(_rig._arms.visible)


func test_remote_plasma_uses_body_mount_and_aim_pitch() -> void:
	_player.name = "2"
	_player.set_multiplayer_authority(2)
	_rig.peer_id = 2
	_player.net_pitch = 0.45
	var body := _player.get_node("Body") as Node3D
	body.rotation.y = 0.7
	_rig._process(0.0)
	var expected := HeldItemPose.world_grip(_player.global_position, 0.7, 0.45)
	assert_true(_rig.global_transform.is_equal_approx(expected))
	_check_wrists(_rig._arms.human)


func test_import_has_two_surfaces_with_visible_energy_and_recessed_muzzles() -> void:
	_rig._process(0.0)
	var mesh := _rig._view.get_node("Model/PlasmaMesh") as MeshInstance3D
	assert_eq(mesh.mesh.get_surface_count(), 2)
	var energy := mesh.get_active_material(1) as StandardMaterial3D
	assert_true(energy.emission_enabled)
	assert_eq(energy.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	for marker: String in ["Muzzle", "MuzzleLeft", "MuzzleRight"]:
		var muzzle := _rig._view.get_node(marker) as Node3D
		assert_lt(muzzle.position.z, mesh.get_aabb().position.z)
		assert_true((-muzzle.basis.z).is_equal_approx(Vector3.FORWARD))


func _check_wrists(human: SkinnedHuman) -> void:
	for right: bool in [true, false]:
		var target := _rig as Node3D if right else _rig.support_grip()
		var offset := Vector3(0.055 if right else -0.055, -0.04, 0.055)
		var bone := human.skeleton.find_bone("HandR" if right else "HandL")
		var actual := human.skeleton.to_global(human.skeleton.get_bone_global_pose(bone).origin)
		assert_almost_eq(actual, target.to_global(offset), Vector3.ONE * 0.002)


func _stats() -> Dictionary:
	var stats := GunGenerator.ray_gun()
	stats["ammo_type"] = GunGenerator.AmmoType.PLASMA
	stats["barrel_count"] = 2
	return stats
