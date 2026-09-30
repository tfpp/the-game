extends GutTest
## The patrons feature on its own and with features/boxing: spawning, what every
## peer builds, replicated state for late joiners, and real punches.

const FeatureScene := preload("res://features/casino_patrons/feature.tscn")
const PatronScene := preload("res://features/casino_patrons/patron.tscn")
const BoxingScene := preload("res://features/boxing/feature.tscn")
const PlayerScene := preload("res://core/player/player.tscn")


func test_spawn_builds_the_same_patron_for_every_peer() -> void:
	var feature := FeatureScene.instantiate()
	add_child_autofree(feature)
	var first := feature._spawn_patron({"index": 1}) as CasinoPatron
	var second := feature._spawn_patron({"index": 1}) as CasinoPatron
	assert_eq(first.name, second.name)
	assert_eq(first.route, PatronMath.route(1))
	assert_eq(first.position, PatronMath.route(1)[0])
	first.free()
	second.free()


func test_late_joiners_get_position_facing_and_ragdoll_state() -> void:
	var patron := PatronScene.instantiate()
	add_child_autofree(patron)
	var config := (
		(patron.get_node("NetworkedEntity/Sync") as MultiplayerSynchronizer).replication_config
	)
	for property: String in ["net_position", "net_yaw", "net_alive", "net_ragdoll", "net_fall_dir"]:
		var path := NodePath(".:" + property)
		assert_true(config.has_property(path), property)
		assert_true(config.property_get_spawn(path), "%s arrives on spawn" % property)


func test_patrons_are_punchable_humanoids_with_articulated_limbs() -> void:
	var patron := PatronScene.instantiate() as CasinoPatron
	patron.route = [Vector3.ZERO, Vector3(0, 0, -5)] as Array[Vector3]
	add_child_autofree(patron)
	assert_true(patron.is_in_group(&"killable"))
	assert_is(patron.get_node("Body/Avatar"), BlockPlayerModel, "wears the player avatar rig")
	assert_is(patron.get_node("Body/Avatar/Rig/Human"), SkinnedHuman)
	for joint: String in [
		"Torso/Head", "Torso/LeftArm/Forearm", "Torso/RightArm", "LeftLeg/Shin", "RightLeg/Shin"
	]:
		var path := "Body/Avatar/Rig/" + joint
		assert_not_null(patron.get_node_or_null(path), path)


func test_a_boxing_power_punch_knocks_a_patron_down() -> void:
	var boxing := BoxingScene.instantiate() as Boxing
	add_child_autofree(boxing)
	var player := PlayerScene.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_yaw = 0.0
	player.net_pitch = 0.0
	var patron := PatronScene.instantiate() as CasinoPatron
	add_child_autofree(patron)
	patron.global_position = player.net_position + Vector3(0, -0.9, -1.0)
	await wait_physics_frames(2)
	assert_eq(boxing.punch(1, BoxingMath.FULL_CHARGE_S), patron)
	assert_true(patron.net_ragdoll)
