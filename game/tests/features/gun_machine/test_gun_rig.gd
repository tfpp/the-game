extends GutTest
## Integration coverage for gun_rig.gd: equip/discard, firing (ammo consumption and
## projectile spawning) and reloading. Runs single-process, so
## `multiplayer.get_remote_sender_id()` is 0 and every RPC here resolves to peer 1 —
## the same trick test_holdables.gd uses to call server RPCs directly.

const GunRigScene := preload("res://features/gun_machine/gun_rig.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _player: Player
var _rig: GunRig


class _MachineStub:
	extends Node
	var spawned: Array[Dictionary] = []

	func spawn_projectile(data: Dictionary) -> void:
		spawned.append(data)


func _sample_stats(seed_value: int = 7) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return GunGenerator.generate(rng)


func before_each() -> void:
	_player = PlayerScene.instantiate() as Player
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_rig = GunRigScene.instantiate() as GunRig
	_rig.peer_id = 1
	add_child_autofree(_rig)
	_rig.set_process(false)
	await get_tree().physics_frame


func test_equip_loads_a_full_magazine_and_the_rest_into_reserve() -> void:
	var stats := _sample_stats()
	_rig.equip(stats)
	assert_eq(_rig.net_ammo_in_mag, int(stats["magazine_size"]))
	assert_eq(_rig.net_ammo_reserve, int(stats["total_ammo"]) - int(stats["magazine_size"]))
	assert_eq(_rig.net_stats["ammo_type"], stats["ammo_type"])


func test_discard_empties_the_rig() -> void:
	_rig.equip(_sample_stats())
	_rig.discard()
	assert_true(_rig.net_stats.is_empty())
	assert_eq(_rig.net_ammo_in_mag, 0)
	assert_eq(_rig.net_ammo_reserve, 0)


func test_firing_consumes_one_round_per_barrel_and_spawns_a_projectile_per_pellet() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	var stats := _sample_stats()
	_rig.equip(stats)
	var starting_ammo := _rig.net_ammo_in_mag
	_rig.request_fire()
	assert_eq(_rig.net_ammo_in_mag, starting_ammo - int(stats["barrel_count"]))
	var profile := GunGenerator.profile(stats["ammo_type"])
	var expected_projectiles := int(stats["barrel_count"]) * int(profile["pellets"])
	assert_eq(stub.spawned.size(), expected_projectiles)
	for data: Dictionary in stub.spawned:
		assert_eq(int(data["shooter_peer"]), 1)
		assert_almost_eq(float(data["damage"]), float(stats["damage"]), 0.01)


func test_firing_without_enough_ammo_in_the_magazine_does_nothing() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	_rig.equip(_sample_stats())
	_rig.net_ammo_in_mag = 0
	_rig.request_fire()
	assert_true(stub.spawned.is_empty())


func test_fire_requests_from_another_peer_are_ignored() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	_rig.equip(_sample_stats())
	_rig.peer_id = 2
	_rig.request_fire()
	assert_true(stub.spawned.is_empty())


func test_a_fresh_shot_is_blocked_by_its_own_fire_rate_cooldown() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	_rig.equip(_sample_stats())
	_rig.net_ammo_in_mag = int(_rig.net_stats["magazine_size"])
	_rig.request_fire()
	var after_first := stub.spawned.size()
	_rig.request_fire()
	assert_eq(stub.spawned.size(), after_first, "still on cooldown, so no second shot")


func test_reload_moves_ammo_from_reserve_into_the_magazine() -> void:
	var stats := _sample_stats()
	_rig.equip(stats)
	_rig.net_ammo_in_mag = 0
	var reserve := _rig.net_ammo_reserve
	_rig.request_reload()
	var expected := mini(int(stats["magazine_size"]), reserve)
	assert_eq(_rig.net_ammo_in_mag, expected)
	assert_eq(_rig.net_ammo_reserve, reserve - expected)


func test_for_peer_finds_the_matching_rig() -> void:
	assert_eq(GunRig.for_peer(get_tree(), 1), _rig)
	assert_null(GunRig.for_peer(get_tree(), 99))


func test_process_priority_runs_after_player_and_third_person_camera_updates() -> void:
	assert_gt(_rig.process_priority, 10, "Mount after player and third-person camera updates")


func test_physics_interpolation_is_disabled_so_the_viewmodel_does_not_jitter() -> void:
	assert_eq(_rig.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)


func test_fire_origin_is_the_players_eye_and_does_not_depend_on_the_view_camera() -> void:
	var stub := _MachineStub.new()
	stub.add_to_group(&"gun_machine_root")
	add_child_autofree(stub)
	_rig.equip(_sample_stats())
	_player.net_position = Vector3(4, 2, -3)
	(_player.get_node("Camera") as Camera3D).global_position = Vector3(40, 50, 60)
	var expected_origin := _rig._aim_origin(_player)
	_rig.request_fire()
	assert_false(stub.spawned.is_empty())
	for data: Dictionary in stub.spawned:
		assert_true((data["position"] as Vector3).is_equal_approx(expected_origin))
