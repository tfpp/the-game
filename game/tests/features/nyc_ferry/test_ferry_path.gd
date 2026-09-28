extends GutTest
## Pure logic for the ferry's route timeline (features/nyc_ferry/ferry_path.gd).

const ROUTE_M := 30.0
const SPEED := 3.0
const WAIT_S := 3.0


func test_starts_docked_at_a() -> void:
	var distance := NycFerryPath.distance_along_route(0.0, ROUTE_M, SPEED, WAIT_S)
	assert_eq(distance, 0.0)


func test_stays_docked_at_a_during_wait() -> void:
	var distance := NycFerryPath.distance_along_route(WAIT_S - 0.01, ROUTE_M, SPEED, WAIT_S)
	assert_eq(distance, 0.0)


func test_midway_across_first_crossing() -> void:
	# Leg takes route_m / speed = 10s; halfway across is 5s into the crossing.
	var distance := NycFerryPath.distance_along_route(WAIT_S + 5.0, ROUTE_M, SPEED, WAIT_S)
	assert_almost_eq(distance, 15.0, 0.001)


func test_reaches_dock_b_and_stays_there() -> void:
	var leg_s := ROUTE_M / SPEED
	var distance := NycFerryPath.distance_along_route(WAIT_S + leg_s + 1.0, ROUTE_M, SPEED, WAIT_S)
	assert_almost_eq(distance, ROUTE_M, 0.001)


func test_returns_toward_a_on_second_crossing() -> void:
	var leg_s := ROUTE_M / SPEED
	var t := WAIT_S + leg_s + WAIT_S + 5.0
	var distance := NycFerryPath.distance_along_route(t, ROUTE_M, SPEED, WAIT_S)
	assert_almost_eq(distance, ROUTE_M - 15.0, 0.001)


func test_schedule_repeats_after_a_full_cycle() -> void:
	var leg_s := ROUTE_M / SPEED
	var cycle_s := 2.0 * (leg_s + WAIT_S)
	var a := NycFerryPath.distance_along_route(4.0, ROUTE_M, SPEED, WAIT_S)
	var b := NycFerryPath.distance_along_route(4.0 + cycle_s, ROUTE_M, SPEED, WAIT_S)
	assert_almost_eq(a, b, 0.001)
