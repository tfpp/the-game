extends GutTest
## Server-authoritative kill/respawn behavior for features/shooting_gallery's
## humanoid dummy (humanoid_target.gd). Runs single-process like
## test_penguin.gd, so peer 1 is the server and `take_hit` resolves as if called
## from server code.

const TargetScene := preload("res://features/shooting_gallery/humanoid_target.tscn")
const PlayerScene := preload("res://core/player/player.tscn")
const HandScene := preload("res://features/holdables/hand.tscn")

var _target: HumanoidTarget


func before_each() -> void:
	_target = TargetScene.instantiate() as HumanoidTarget
	add_child_autofree(_target)
	await get_tree().physics_frame


func test_starts_alive() -> void:
	assert_true(_target.net_alive)


func test_is_in_the_killable_group() -> void:
	assert_true(_target.is_in_group(&"killable"))


func test_take_hit_kills_it() -> void:
	_target.take_hit(2)
	assert_false(_target.net_alive)


func test_a_dead_target_ignores_further_hits() -> void:
	_target.take_hit(2)
	_target._respawn_timer = HumanoidTarget.RESPAWN_DELAY_S
	_target.take_hit(2)
	assert_almost_eq(_target._respawn_timer, HumanoidTarget.RESPAWN_DELAY_S, 0.001)


func test_stays_dead_before_the_respawn_delay_elapses() -> void:
	_target.take_hit(2)
	_target._physics_process(HumanoidTarget.RESPAWN_DELAY_S - 0.1)
	assert_false(_target.net_alive)


func test_respawns_in_place_after_the_respawn_delay() -> void:
	_target.take_hit(2)
	_target._physics_process(HumanoidTarget.RESPAWN_DELAY_S)
	assert_true(_target.net_alive)


func test_hiding_and_showing_follows_net_alive() -> void:
	_target.take_hit(2)
	_target._process(0.0)
	assert_false(_target.get_node("Body").visible)
	assert_true(_target.get_node("Collider").disabled)
	_target.net_alive = true
	_target._process(0.0)
	assert_true(_target.get_node("Body").visible)
	assert_false(_target.get_node("Collider").disabled)


func test_gibbing_flings_debris_and_blood_that_clean_themselves_up() -> void:
	_target.take_hit(2)
	var mesh_effects: Array[MeshExplosion] = []
	var gore_effects: Array[GoreSplatter] = []
	for child: Node in _target.get_children():
		if child is MeshExplosion:
			mesh_effects.append(child)
		elif child is GoreSplatter:
			gore_effects.append(child)
	assert_eq(mesh_effects.size(), 1, "a kill must spawn the shared gib effect")
	assert_eq(gore_effects.size(), 1, "a kill must spawn the extra blood effect")
	assert_gt(mesh_effects[0].get_child_count(), 5, "a humanoid has many limbs to gib")
	assert_gt(gore_effects[0].get_child_count(), 5, "the blood burst should be copious")
	var wait_s := maxf(MeshExplosion.DEBRIS_DURATION_S, GoreSplatter.DURATION_S) + 0.2
	await wait_seconds(wait_s)
	assert_false(is_instance_valid(mesh_effects[0]))
	assert_false(is_instance_valid(gore_effects[0]))


func test_real_hitscan_weapon_kills_it() -> void:
	var player := PlayerScene.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_yaw = 0.0
	player.net_pitch = 0.0
	var hand := HandScene.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	var origin := hand._aim_origin(player)
	_target.global_position = origin + Vector3(0, -0.9, -3)
	await wait_physics_frames(2)
	hand.net_item_id = "pistol"
	hand.inventory().collect("ammo:pistol:1")
	hand.request_primary_action()
	assert_false(_target.net_alive, "a weapon must hit the target's real collider")
