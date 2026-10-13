extends GutTest
## The throw with the real MetroService: the guard calls the Crown connector's cab,
## throws once its doors are open, and the offender lands on a loaded metro platform
## through MetroService.deliver(). Late joiners and fallbacks.

const SECURITY := preload("res://features/casino_security/feature.tscn")
const METRO := preload("res://features/metro/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")

var _security: CasinoSecurity
var _metro: MetroService
var _access: MetroAccess
var _player: Player


func before_each() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.25, 50)
	shape.shape = box
	floor.add_child(shape)
	floor.position = Vector3(0, -0.125, 0)
	add_child_autofree(floor)
	_metro = METRO.instantiate() as MetroService
	add_child_autofree(_metro)
	_metro.set_physics_process(false)
	_metro.transfers.set_physics_process(false)
	# The Golden Crown connector, as casino_gridmap.tscn places it.
	_access = MetroAccess.new()
	_access.zone_id = "crown"
	_access.label = "Golden Crown"
	_access.position = Vector3(-12, 0, 19.8)
	_access.rotation.y = PI
	add_child_autofree(_access)
	_security = SECURITY.instantiate() as CasinoSecurity
	add_child_autofree(_security)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	_player.position = Vector3(-12, 0.92, 12)
	_player.net_position = _player.position
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	await wait_physics_frames(3)
	_security.build_grid_now()


func after_each() -> void:
	await get_tree().process_frame


## Skips straight to the guard arriving at the doors with the offender on board.
func _arrive_at_doors() -> CasinoGuard:
	var guard := _security.guards()[1]
	guard.net_carrying = 1
	guard.position = _security.cab_marker() * SecurityRules.THROW_STAND
	guard.walk([], SecurityRules.GuardState.CARRYING)
	_security._set_detention(1, 1, &"vandalism", SecurityRules.Phase.CARRIED)
	return guard


func test_the_cab_marker_is_the_crown_connector() -> void:
	assert_not_null(_access.source, "metro registered the connector's cab")
	assert_eq(_security.cab_marker(), _access.global_transform)
	var stand := _security.cab_marker() * SecurityRules.THROW_STAND
	var target := _security.cab_marker() * SecurityRules.CAB_TARGET
	assert_almost_eq(stand, Vector3(-12, 0, 17.9), Vector3.ONE * 0.01, "in front of the doors")
	assert_almost_eq(target, Vector3(-12, 1.0, 21.2), Vector3.ONE * 0.01, "inside the cab")


func test_guard_calls_the_cab_throws_in_and_the_offender_lands_on_a_platform() -> void:
	var guard := _arrive_at_doors()
	var cab := _access.source
	assert_eq(cab.net_state, ElevatorCab.State.CLOSED)
	_security.advance(0.0)
	assert_eq(guard.net_state, SecurityRules.GuardState.DOORS)
	assert_eq(cab.net_state, ElevatorCab.State.OPENING, "the guard pressed the call button")
	assert_true(await wait_until(func() -> bool: return cab.net_state == ElevatorCab.State.OPEN, 5))
	_security.advance(0.0)
	assert_eq(guard.net_state, SecurityRules.GuardState.THROWING, "throws once the doors open")
	_security.advance(SecurityRules.RELEASE_S)
	assert_eq(_security.phase_for(1), SecurityRules.Phase.THROWN)
	assert_eq(guard.net_carrying, 0)
	_security.advance(SecurityRules.FLIGHT_S * 0.5)
	assert_false(_metro.transfers.pending.has(1), "the flight plays out first")
	_security.advance(SecurityRules.FLIGHT_S * 0.5)
	assert_true(_metro.transfers.pending.has(1))
	assert_eq(_metro.transfers.pending[1]["kind"], "wake")
	var target: Vector3 = _security._deliveries[1]["position"]
	var station := -1
	for index: int in 4:
		if _metro.stations[index].contains(target):
			station = index
	assert_ne(station, -1, "drop-off is inside a metro station")
	assert_true(absf(target.x - _metro.stations[station].global_position.x - 8.0) > 4.0)
	await wait_physics_frames(8)
	assert_true(_metro.transfers.pending[1]["ready"], "client reported the platform floor")
	_metro.transfers._physics_process(0.1)
	assert_lt(_player.net_position.distance_to(target), 0.002, "teleported onto the platform")
	assert_eq(_security.phase_for(1), SecurityRules.Phase.LANDED)
	assert_false(_metro.transfers.pending.has(1))
	# The guard finishes the heave and heads back to the post.
	assert_true(
		await wait_until(
			func() -> bool: return guard.net_state == SecurityRules.GuardState.RETURNING, 3
		)
	)
	_security.advance(SecurityRules.LANDED_S)
	assert_false(_security.detentions.has(1))


func test_stuck_doors_do_not_stop_the_throw() -> void:
	var guard := _arrive_at_doors()
	_security.advance(0.0)
	_access.source.net_state = ElevatorCab.State.CLOSING
	_security.advance(SecurityRules.DOOR_WAIT_S)
	assert_eq(guard.net_state, SecurityRules.GuardState.THROWING)


func test_a_metro_that_never_loads_puts_them_down_at_the_doors() -> void:
	_arrive_at_doors()
	_security.advance(0.0)
	_security.advance(SecurityRules.DOOR_WAIT_S)
	_security.advance(SecurityRules.RELEASE_S)
	_security.advance(SecurityRules.FLIGHT_S + 0.1)
	assert_true(_metro.transfers.pending.has(1))
	_security.advance(SecurityRules.DELIVERY_TIMEOUT_S + 0.1)
	assert_false(_metro.transfers.pending.has(1), "the abandoned drop-off is cancelled")
	assert_eq(_security.phase_for(1), SecurityRules.Phase.LANDED)
	var stand := _security.cab_marker() * SecurityRules.THROW_STAND
	assert_lt(Vector2(_player.position.x - stand.x, _player.position.z - stand.z).length(), 0.1)


func test_death_mid_flight_cancels_the_drop_off() -> void:
	_arrive_at_doors()
	_security.advance(0.0)
	_security.advance(SecurityRules.DOOR_WAIT_S)
	_security.advance(SecurityRules.RELEASE_S)
	_security.advance(SecurityRules.FLIGHT_S + 0.1)
	assert_true(_metro.transfers.pending.has(1))
	_security.release(1)
	assert_false(_metro.transfers.pending.has(1))
	assert_true(_security.detentions.is_empty())
