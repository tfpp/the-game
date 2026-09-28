extends GutTest

const Noclip := preload("res://features/noclip/noclip.gd")
var noclip: Noclip
var player: Player


func before_each() -> void:
	noclip = preload("res://features/noclip/feature.tscn").instantiate()
	add_child_autofree(noclip)
	noclip.set_physics_process(false)
	player = preload("res://core/player/player.tscn").instantiate()
	player.name = "1"
	add_child_autofree(player)


func test_cheats_default_off_validate_identity_and_value() -> void:
	assert_false(noclip.cheats_enabled)
	assert_true(noclip.toggle().contains("sv_cheats 1"))
	assert_false(noclip.apply_cheats(999, 1))
	assert_false(noclip.apply_cheats(1, 2))
	noclip.request_cheats(1)
	assert_true(noclip.cheats_enabled)
	assert_true(noclip.apply_cheats(1, 0))
	assert_false(noclip.cheats_enabled)


func test_revoke_restores_collision_and_safe_entry_position() -> void:
	noclip.request_cheats(1)
	player.position = Vector3(2, 2, 2)
	noclip.toggle()
	assert_false(player.is_physics_processing())
	assert_true(player.get_node("Collider").disabled)
	player.position = Vector3(10, 2, 2)
	noclip.request_cheats(0)
	noclip._physics_process(0.01)
	assert_false(noclip._active)
	assert_true(player.is_physics_processing())
	assert_false(player.get_node("Collider").disabled)
	assert_eq(player.position, Vector3(2, 2, 2))


func test_teleport_ends_flight_at_respawn_destination() -> void:
	noclip.request_cheats(1)
	noclip.toggle()
	player.server_teleport.rpc_id(1, Vector3(4, 5, 6))
	noclip._physics_process(0.01)
	assert_false(noclip._active)
	assert_eq(player.position, Vector3(4, 5, 6))
	assert_false(player.get_node("Collider").disabled)


func test_toggle_off_and_session_reset_preserve_normal_movement() -> void:
	noclip.request_cheats(1)
	noclip.toggle()
	noclip.toggle()
	assert_true(player.is_physics_processing())
	noclip.toggle()
	noclip._reset(Network.Mode.OFFLINE)
	assert_false(noclip.cheats_enabled)
	assert_false(noclip._active)
	assert_true(player.is_physics_processing())


func test_switch_is_server_owned_and_in_late_join_snapshot() -> void:
	var sync := noclip.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:cheats_enabled")))
	assert_eq(
		sync.replication_config.property_get_replication_mode(NodePath(".:cheats_enabled")), 2
	)


func test_removed_player_clears_flight_without_affecting_replacement() -> void:
	noclip.request_cheats(1)
	noclip.toggle()
	player.free()
	noclip._physics_process(0.01)
	assert_false(noclip._active)
	assert_true(noclip.cheats_enabled)
