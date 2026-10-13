extends GutTest
## Server-owned detentions on a flat hall floor: an offence brings the nearest
## guard, who lifts, carries and throws the offender at the metro doors, then walks
## back to the post. Rejected reports, the queue, deaths, blackouts and disconnects.

const SECURITY := preload("res://features/casino_security/feature.tscn")
const COMBAT := preload("res://features/combat/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _security: CasinoSecurity
var _combat: Combat
var _players: Dictionary[int, Player] = {}


## Stands in for features/booze: reports a blackout phase per peer.
class FakeBooze:
	extends Node
	var phases: Dictionary[int, int] = {}

	func _ready() -> void:
		add_to_group(&"booze")

	func phase_for(peer: int) -> int:
		return phases.get(peer, 0)


func before_each() -> void:
	_players.clear()
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.25, 50)
	shape.shape = box
	floor.add_child(shape)
	floor.position = Vector3(0, -0.125, 0)
	add_child_autofree(floor)
	_combat = COMBAT.instantiate() as Combat
	add_child_autofree(_combat)
	_security = SECURITY.instantiate() as CasinoSecurity
	add_child_autofree(_security)
	await wait_physics_frames(2)
	_security.build_grid_now()


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
	_players[peer] = player
	return player


func _phase(peer: int) -> int:
	return _security.phase_for(peer)


func test_an_offence_brings_a_guard_who_carries_and_throws_the_offender() -> void:
	var player := _player(1, Vector3(-4, 0.92, -10))
	assert_true(_security.report_misconduct(1, &"firearm"))
	assert_eq(_phase(1), SecurityRules.Phase.HELD)
	assert_eq(_security.offence_for(1), &"firearm")
	var guard := _security.guard_for(1)
	assert_eq(guard.name, &"Guard0", "the nearest guard answers")
	assert_eq(guard.net_carrying, 1)
	assert_eq(guard.net_state, SecurityRules.GuardState.RESPONDING)
	assert_false(_security.report_misconduct(1, &"assault"), "one detention at a time")
	assert_true(
		await wait_until(func() -> bool: return _phase(1) == SecurityRules.Phase.CARRIED, 10),
		"the guard reaches the offender and lifts them"
	)
	var feet := player.global_position - Vector3.UP * player.movement.hull_height_m() * 0.5
	assert_true(SecurityRules.can_grab(guard.position, feet), "close enough to grab")
	assert_eq(guard.net_state, SecurityRules.GuardState.LIFTING)
	assert_true(
		await wait_until(
			func() -> bool: return guard.net_state == SecurityRules.GuardState.CARRYING, 3
		)
	)
	await wait_physics_frames(10)
	# The offender's own view pins their capsule to the guard's shoulder.
	var shoulder := SecurityRules.carry_point(guard.drawn_transform())
	assert_lt(player.global_position.distance_to(shoulder), 0.3, "riding the shoulder")
	assert_true(
		await wait_until(func() -> bool: return _phase(1) == SecurityRules.Phase.THROWN, 30),
		"carried to the metro doors and thrown"
	)
	var stand := _security.cab_marker() * SecurityRules.THROW_STAND
	assert_lt(Vector2(guard.position.x - stand.x, guard.position.z - stand.z).length(), 0.6)
	assert_eq(guard.net_carrying, 0, "hands empty")
	# No metro in this scene: put down outside the doors instead.
	assert_true(await wait_until(func() -> bool: return _phase(1) == SecurityRules.Phase.LANDED, 3))
	assert_lt(
		Vector2(player.global_position.x - stand.x, player.global_position.z - stand.z).length(),
		0.1
	)
	assert_true(await wait_until(func() -> bool: return _phase(1) == SecurityRules.Phase.NONE, 8))
	assert_true(_security.detentions.is_empty())
	assert_true(
		await wait_until(
			func() -> bool: return guard.net_state == SecurityRules.GuardState.POSTED, 30
		),
		"walks back to the post"
	)
	assert_eq(guard.position, guard.post)


func test_reports_outside_the_hall_or_of_unknown_offences_are_ignored() -> void:
	_player(1, Vector3(0, 0.92, 30))
	_player(2, Vector3(2, 0.92, 0))
	assert_false(_security.report_misconduct(1, &"firearm"), "south corridor is out of bounds")
	assert_false(_security.report_misconduct(2, &"loitering"), "not an offence")
	assert_false(_security.report_misconduct(99, &"firearm"), "no such player")
	assert_true(_security.detentions.is_empty())
	for guard: CasinoGuard in _security.guards():
		assert_eq(guard.net_state, SecurityRules.GuardState.POSTED)


func test_a_fourth_offender_waits_for_a_free_guard() -> void:
	for peer: int in [1, 2, 3, 4]:
		_player(peer, Vector3(peer * 2.0 - 5.0, 0.92, 2))
		assert_true(_security.report_misconduct(peer, &"vandalism"))
	assert_eq(_security.detentions.size(), 3, "three guards, three detentions")
	assert_false(_security.detentions.has(4))
	assert_true(_security._queued(4))
	assert_false(_security.report_misconduct(4, &"firearm"), "already waiting")
	_security.release(2)
	_security.advance(0.0)
	assert_eq(_phase(4), SecurityRules.Phase.HELD, "the freed guard takes the next one")
	assert_ne(_security.guard_for(4), _security.guard_for(1))


func test_queued_offences_expire() -> void:
	for peer: int in [1, 2, 3, 4]:
		_player(peer, Vector3(peer * 2.0 - 5.0, 0.92, 2))
		_security.report_misconduct(peer, &"vandalism")
	_security.advance(SecurityRules.QUEUE_TIMEOUT_S + 1.0)
	assert_false(_security._queued(4))


func test_disconnect_and_death_free_the_guard() -> void:
	_player(1, Vector3(-4, 0.92, -10))
	_player(2, Vector3(10, 0.92, 0))
	_security.report_misconduct(1, &"firearm")
	_security.report_misconduct(2, &"assault")
	var first := _security.guard_for(1)
	var second := _security.guard_for(2)
	_security._forget(1)
	assert_false(_security.detentions.has(1))
	assert_eq(first.net_state, SecurityRules.GuardState.RETURNING)
	assert_eq(first.net_carrying, 0)
	_combat.player_died.emit(2, 2)
	assert_false(_security.detentions.has(2), "death ends it")
	assert_eq(second.net_state, SecurityRules.GuardState.RETURNING)


func test_a_blackout_takes_precedence() -> void:
	var booze := FakeBooze.new()
	add_child_autofree(booze)
	_player(1, Vector3(-4, 0.92, -10))
	booze.phases[1] = 1
	assert_false(_security.report_misconduct(1, &"firearm"), "already passing out")
	booze.phases[1] = 0
	assert_true(_security.report_misconduct(1, &"firearm"))
	booze.phases[1] = 2
	_security.advance(0.1)
	assert_false(_security.detentions.has(1), "blacking out mid-detention lets go")


func test_an_unreachable_offender_is_let_go() -> void:
	_player(1, Vector3(-4, 0.92, -10))
	_security.report_misconduct(1, &"firearm")
	var guard := _security.guard_for(1)
	_security.advance(SecurityRules.RESPOND_TIMEOUT_S + 1.0)
	assert_false(_security.detentions.has(1))
	assert_eq(guard.net_state, SecurityRules.GuardState.RETURNING)


func test_leaving_the_hall_while_held_ends_it() -> void:
	var player := _player(1, Vector3(-4, 0.92, -10))
	_security.report_misconduct(1, &"firearm")
	player.global_position = Vector3(0, 0.92, -600)
	_security.advance(0.1)
	assert_false(_security.detentions.has(1))


func test_session_reset_sends_everyone_home() -> void:
	_player(1, Vector3(-4, 0.92, -10))
	_security.report_misconduct(1, &"firearm")
	await wait_physics_frames(20)
	_security._reset(Network.Mode.OFFLINE)
	assert_true(_security.detentions.is_empty())
	for guard: CasinoGuard in _security.guards():
		assert_eq(guard.position, guard.post)
		assert_eq(guard.net_state, SecurityRules.GuardState.POSTED)
