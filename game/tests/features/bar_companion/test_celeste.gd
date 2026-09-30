extends GutTest

const SCENE := preload("res://features/bar_companion/celeste.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _npc: Celeste
var _talk: NetworkedInteraction
var _subtitles: Subtitles


func before_each() -> void:
	_subtitles = Subtitles.new()
	add_child_autofree(_subtitles)
	_npc = SCENE.instantiate() as Celeste
	_npc.position = Vector3(-6.6, -1.5, -7.8)
	add_child_autofree(_npc)
	_npc.set_physics_process(false)
	_talk = _npc.get_node("NetworkedEntity") as NetworkedInteraction


func _player(peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = _npc.global_position + Vector3(0, 0, 1)
	player.global_position = player.net_position
	return player


func _clear_cooldown() -> void:
	_talk._actions[&"use"].next_msec = 0


func test_free_recruit_and_dismiss_through_real_use_with_subtitles() -> void:
	_player(1)
	_npc.use()
	assert_eq(_npc.net_leader, 1, "no wallet or apartment required")
	assert_string_contains(_subtitles.current_text(), "Celeste:")
	assert_string_contains(_subtitles.current_text(), "For now")
	assert_eq(_npc.interaction_text(), "Part ways with Celeste")
	_npc.use()
	assert_eq(_npc.net_leader, 1, "holding Use cannot immediately dismiss")
	_clear_cooldown()
	_npc.use()
	assert_eq(_npc.net_leader, 0)
	assert_eq(_npc.net_position, Vector3(-6.6, -1.5, -7.8))
	assert_string_contains(_subtitles.current_text(), "I know where to find you")


func test_requests_reject_unknown_far_forged_and_other_players() -> void:
	var player := _player(1)
	_player(2)
	assert_eq(_talk._evaluate(99, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_talk._evaluate(1, &"use", {"peer": 2}), NetworkedEntity.Result.DENIED)
	player.net_position += Vector3(8, 0, 0)
	assert_eq(_talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	player.net_position = _npc.global_position
	assert_eq(_talk._evaluate(1, &"use", {}), NetworkedEntity.Result.ACCEPTED)
	_clear_cooldown()
	assert_eq(_talk._evaluate(2, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_npc.net_leader, 1)
	assert_false(_npc.can_use(_talk.player_for_peer(2)))


func test_disconnect_death_timeout_departure_and_replaced_player_release_her() -> void:
	var player := _player(1)
	for reason: String in ["disconnect", "death", "timeout", "departure", "replacement"]:
		player.net_position = _npc.global_position
		_clear_cooldown()
		_npc.use()
		assert_eq(_npc.net_leader, 1)
		match reason:
			"disconnect":
				_npc._on_disconnect(1)
			"death":
				_npc._on_death(1, 2)
			"timeout":
				_npc._advance(Celeste.VISIT_S + 1)
			"departure":
				player.net_position = Vector3(100, 0, 100)
				_npc._advance(0.1)
			"replacement":
				player.free()
				player = _player(1)
				_npc._advance(0.1)
		assert_eq(_npc.net_leader, 0, reason)
		assert_true(_npc._trail.is_empty(), reason)


func test_session_reset_and_unrelated_death() -> void:
	_player(1)
	_npc.use()
	_npc._on_death(2, 1)
	assert_eq(_npc.net_leader, 1)
	_talk._on_session_changed(Network.Mode.OFFLINE)
	assert_eq(_npc.net_leader, 0)
	_npc.use()
	assert_eq(_npc.net_leader, 1, "reset clears recruitment cooldown")


func test_authority_rejects_mutations_when_component_is_not_server_owned() -> void:
	_player(1)
	_talk.set_multiplayer_authority(2)
	assert_eq(_talk._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_npc.net_leader, 0)


func test_late_join_snapshot_contains_leader_pose_and_drives_presentation() -> void:
	var sync := _talk.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	for field: String in ["net_leader", "net_position", "net_yaw"]:
		assert_true(sync.replication_config.property_get_spawn(NodePath(".:" + field)))
	_npc.net_leader = 1
	_npc.net_position = Vector3(2, -1.5, 3)
	_npc.net_yaw = PI / 2.0
	assert_eq(_npc.interaction_text(), "Part ways with Celeste")
	assert_false(_subtitles.is_showing(), "old dialogue is not replayed on join")


func test_remarks_cycle_without_revealing_allegiance() -> void:
	_player(1)
	_npc.use()
	for index: int in Celeste.LINES.size() + 1:
		_npc._remark_left = 0
		_npc._advance(0.0)
		assert_string_contains(
			_subtitles.current_text(), Celeste.LINES[index % Celeste.LINES.size()]
		)


func test_floor_bounds_allow_jump_but_exclude_gallery_and_other_rooms() -> void:
	assert_true(Celeste.on_gaming_floor(Vector3(0, 1, 0)))
	assert_false(Celeste.on_gaming_floor(Vector3(0, 3.2, -9)))
	assert_false(Celeste.on_gaming_floor(Vector3(22, 0, 0)))
	assert_false(Celeste.on_gaming_floor(Vector3(0, -4, 0)))


func test_models_keep_vivienne_identity_and_give_celeste_a_distinct_look() -> void:
	var original := CompanionModel.new()
	add_child_autofree(original)
	original.build_vivienne()
	assert_eq((original.get_node("NameTag") as Label3D).text, "Vivienne")
	assert_eq(original.avatar.shirt_color, ClothingCatalog.COLORS[CompanionModel.DRESS])
	assert_eq(original.avatar.body_type, &"girl")
	var celeste := _npc.get_node("Body") as CompanionModel
	assert_ne(celeste.avatar.shirt_color, original.avatar.shirt_color)
	assert_eq(celeste.avatar.hair_style, "swept")
	assert_eq((_npc.get_node("Body/NameTag") as Label3D).text, "Celeste")
	assert_not_null(_npc.find_child("Brooch", true, false))
	assert_eq(_npc.collision_layer, 0, "never blocks a player's route")
