extends GutTest

const FROG := preload("res://features/frogs/frog.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")

var _frog: Frog


func before_each() -> void:
	_frog = FROG.instantiate() as Frog
	_frog.position = Vector3(2, 1, -3)
	_frog.body_color = Color("62a23f")
	_frog.body_size = 0.7
	add_child_autofree(_frog)
	_frog.set_physics_process(false)


func test_hit_stops_hop_hides_body_and_ignores_repeat_hits() -> void:
	_frog._hopping = true
	_frog.take_hit(1)
	_frog._process(0.0)
	assert_false(_frog.net_alive)
	assert_false(_frog._hopping)
	assert_false(_frog.get_node("Body").visible)
	assert_true(_frog.get_node("Collider").disabled)
	var position_at_death := _frog.position
	_frog._physics_process(1.0)
	_frog.take_hit(1)
	assert_almost_eq(_frog._respawn_timer, Frog.RESPAWN_DELAY_S - 1.0, 0.001)
	assert_eq(_frog.position, position_at_death)
	assert_eq(_effects().size(), 1)


func test_respawn_restores_original_location_profile_and_collision() -> void:
	var home := _frog.position
	_frog.position += Vector3(8, 2, 4)
	_frog.take_hit(1)
	_frog._physics_process(Frog.RESPAWN_DELAY_S - 0.1)
	assert_false(_frog.net_alive)
	_frog._physics_process(0.2)
	_frog._process(0.0)
	assert_true(_frog.net_alive)
	assert_eq(_frog.position, home)
	assert_eq(_frog.net_position, home)
	assert_eq(_frog.body_color, Color("62a23f"))
	assert_eq(_frog.body_size, 0.7)
	assert_true(_frog.get_node("Body").visible)
	assert_false(_frog.get_node("Collider").disabled)
	assert_true(_frog._settling, "Respawn must settle safely before planning a hop")


func test_debris_keeps_colored_materials_scale_and_cleans_up() -> void:
	var torso := _frog.get_node("Body/Torso") as MeshInstance3D
	var torso_scale := torso.get_global_transform_interpolated().basis.get_scale()
	_frog.take_hit(1)
	var effect := _effects()[0]
	var found_torso := false
	for child: Node in effect.get_children():
		var piece := child as MeshInstance3D
		if piece != null and piece.material_override == torso.material_override:
			if piece.global_basis.get_scale().is_equal_approx(torso_scale):
				found_torso = true
	assert_true(found_torso, "Model debris must retain its skin and scaled geometry")
	await wait_seconds(MeshExplosion.DEBRIS_DURATION_S + 0.2)
	assert_false(is_instance_valid(effect), "The complete cosmetic effect must free itself")


func test_real_weapon_hits_frog_without_making_it_block_player_movement() -> void:
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.set_multiplayer_authority(1)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_yaw = 0.0
	player.net_pitch = 0.0
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	var origin := hand._aim_origin(player)
	_frog.global_position = origin + Vector3(0, -_frog._collider.position.y, -3)
	await wait_physics_frames(2)
	assert_eq(player.collision_mask & _frog.collision_layer, 0)
	hand.net_item_id = "pistol"
	hand.request_primary_action()
	assert_false(_frog.net_alive, "A weapon must hit the real frog collider on layer 2")


func test_dead_frog_is_not_a_shot_obstacle() -> void:
	_frog.take_hit(1)
	_frog._process(0.0)
	await wait_physics_frames(2)
	var center := _frog._collider.global_position
	var query := PhysicsRayQueryParameters3D.create(
		center + Vector3.BACK, center + Vector3.FORWARD, 3
	)
	assert_true(_frog.get_world_3d().direct_space_state.intersect_ray(query).is_empty())


func _effects() -> Array[MeshExplosion]:
	var effects: Array[MeshExplosion] = []
	for child: Node in _frog.get_children():
		if child is MeshExplosion:
			effects.append(child)
	return effects
