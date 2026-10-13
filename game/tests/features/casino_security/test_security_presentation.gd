extends GutTest
## What every peer draws from the replicated state: the offender lifted onto the
## guard's shoulder, the throw, the body standing again afterwards and the same
## picture for a late joiner. The offender's own view pins and darkens.

const SECURITY := preload("res://features/casino_security/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _security: CasinoSecurity


func before_each() -> void:
	_security = SECURITY.instantiate() as CasinoSecurity
	add_child_autofree(_security)
	_security.set_physics_process(false)
	_security.set_process(false)


func after_each() -> void:
	await get_tree().process_frame


func _player(peer: int, at: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.position = at
	player.net_position = at
	add_child_autofree(player)
	player.set_physics_process(false)
	player.set_process(false)
	return player


func _carry(peer: int, guard_index: int, state: SecurityRules.GuardState) -> CasinoGuard:
	var guard := _security.guards()[guard_index]
	guard.position = Vector3(3, 0, 2)
	guard.rotation.y = 0.6
	guard.net_carrying = peer
	guard.set_state(state)
	guard._process(0.0)
	guard.state_elapsed = 0.0
	_security._set_detention(peer, guard_index, &"assault", SecurityRules.Phase.CARRIED)
	return guard


func test_other_peers_see_the_lift_the_carry_and_the_throw() -> void:
	var player := _player(2, Vector3(3.4, 0.92, 1.2))
	var body := player.get_node("Body") as Node3D
	var standing := body.global_transform
	var guard := _carry(2, 0, SecurityRules.GuardState.LIFTING)
	_security.present(0.0)
	assert_true(body.global_transform.is_equal_approx(standing), "the lift starts where they stood")
	guard.state_elapsed = SecurityRules.LIFT_S
	_security.present(0.016)
	var shoulder := SecurityRules.carry_body(guard.drawn_transform())
	assert_true(body.global_transform.is_equal_approx(shoulder), "slung over the shoulder")
	guard.set_state(SecurityRules.GuardState.CARRYING)
	guard.position += Vector3(0, 0, 1.5)
	_security.present(0.016)
	assert_true(
		body.global_transform.is_equal_approx(SecurityRules.carry_body(guard.drawn_transform())),
		"rides along as the guard walks"
	)
	_security._set_phase(2, SecurityRules.Phase.THROWN)
	_security.present(0.0)
	var release := SecurityRules.carry_body(guard.drawn_transform())
	assert_almost_eq(
		body.global_position, release.origin, Vector3.ONE * 0.01, "thrown from the shoulder"
	)
	for _frame: int in 10:
		_security.present(SecurityRules.FLIGHT_S * 0.05)
	var target := _security.cab_marker() * SecurityRules.CAB_TARGET
	assert_lt(body.global_position.distance_to(target), release.origin.distance_to(target))
	_security.present(SecurityRules.FLIGHT_S)
	assert_lt(body.global_basis.get_scale().x, 0.01, "through the doors, out of sight")
	_security.release(2)
	_security.present(0.016)
	assert_true(body.position.is_zero_approx(), "standing again once it's over")
	assert_almost_eq(body.global_basis.get_scale().x, 1.0, 0.001)
	assert_lt(body.global_basis.y.dot(Vector3.UP), 1.001)
	assert_gt(body.global_basis.y.dot(Vector3.UP), 0.999, "upright")


func test_a_late_joiner_draws_the_same_carry_from_the_snapshot() -> void:
	var player := _player(2, Vector3(3.4, 0.92, 1.2))
	var guard := _carry(2, 1, SecurityRules.GuardState.CARRYING)
	_security.present(0.016)
	var expected := (player.get_node("Body") as Node3D).global_transform
	var late := SECURITY.instantiate() as CasinoSecurity
	late.detentions = _security.detentions.duplicate(true)
	add_child_autofree(late)
	late.set_process(false)
	late.set_physics_process(false)
	var late_guard := late.guards()[1]
	late_guard.position = guard.position
	late_guard.rotation.y = guard.rotation.y
	late_guard.net_state = guard.net_state
	late.present(0.016)
	assert_eq(late.phase_for(2), SecurityRules.Phase.CARRIED)
	assert_true((player.get_node("Body") as Node3D).global_transform.is_equal_approx(expected))


func test_the_offenders_own_view_holds_them_then_rides_the_shoulder() -> void:
	var player := _player(1, Vector3(-4, 0.92, -10))
	var view := _security.get_node("SecurityView") as SecurityView
	_security._set_detention(1, 0, &"firearm", SecurityRules.Phase.HELD)
	view._physics_process(0.016)
	player.global_position += Vector3(0.3, 0, 0)
	view._physics_process(0.016)
	assert_almost_eq(
		player.global_position, Vector3(-4, 0.92, -10), Vector3.ONE * 0.001, "held still"
	)
	player.global_position = Vector3(10, 0.92, 10)
	view._physics_process(0.016)
	assert_eq(player.global_position, Vector3(10, 0.92, 10), "server teleports still apply")
	view._process(0.016)
	assert_true(view._layer.visible)
	assert_string_contains(view._caption.text, "Brandishing a firearm")
	var guard := _carry(1, 0, SecurityRules.GuardState.CARRYING)
	_security.present(0.016)
	view._physics_process(0.016)
	var shoulder := SecurityRules.carry_point(guard.drawn_transform())
	assert_almost_eq(player.global_position, shoulder, Vector3.ONE * 0.001, "riding the shoulder")
	assert_eq(player.net_position, shoulder, "and that is what everyone else sees")
	_security._set_phase(1, SecurityRules.Phase.THROWN)
	_security.present(SecurityRules.FLIGHT_S)
	_security.present(SecurityRules.FLIGHT_S)
	view._process(0.016)
	assert_eq(view.darkness, 1.0, "blacked out through the doors")
	_security.release(1)
	_security.present(0.016)
	view._process(0.016)
	view._physics_process(0.016)
	assert_false(view._layer.visible)
	player.global_position = Vector3(5, 0.92, 5)
	view._physics_process(0.016)
	assert_eq(player.global_position, Vector3(5, 0.92, 5), "free to move again")


func test_guards_are_buff() -> void:
	var guard := _security.guards()[0]
	await wait_process_frames(2)
	var skeleton := guard.body.avatar.human.skeleton
	var spine := skeleton.get_bone_pose_scale(skeleton.find_bone("Spine"))
	assert_gt(spine.x, 1.2, "broad")
	assert_gt(guard.body.avatar.height_scale(), 1.1, "and tall")
	var head := skeleton.get_bone_pose_scale(skeleton.find_bone("Head"))
	assert_lt(head.x * spine.x, 1.15, "with a roughly human-sized head")
	assert_not_null(guard.body.torso_items.get_node_or_null("Back"), "SECURITY on the back")
	assert_eq(guard.collision_layer, 2, "players walk through them like patrons")
