extends GutTest
## Trip profile, station hand-over and the scenery that passes a ride's windows.

const METRO := preload("res://features/metro/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const STEP := 1.0 / 64.0
var metro: MetroService


func before_each() -> void:
	metro = METRO.instantiate() as MetroService
	add_child_autofree(metro)
	metro.set_physics_process(false)
	metro.transfers.set_physics_process(false)
	await wait_physics_frames(3)


func test_trips_start_and_stop_without_jolts() -> void:
	assert_eq(MetroRules.distance(0), 0.0)
	assert_almost_eq(MetroRules.distance(MetroRules.TRAVEL * 0.5), MetroRules.SPACING * 0.5, 0.001)
	assert_almost_eq(MetroRules.distance(MetroRules.TRAVEL), MetroRules.SPACING, 0.001)
	assert_eq(MetroRules.speed(0), 0.0)
	assert_almost_eq(MetroRules.speed(MetroRules.TRAVEL), 0.0, 0.0001)
	assert_almost_eq(MetroRules.speed(MetroRules.TRAVEL * 0.5), MetroRules.TOP_SPEED, 0.0001)
	assert_lt(MetroRules.distance(0.5), 0.1, "Creeps away from the platform")
	assert_lt(MetroRules.ACCELERATION, 0.5 * 9.81, "Under half a g")
	assert_lt(MetroRules.TOP_SPEED, 30.0)
	var backwards := false
	var worst_speed_error := 0.0
	var worst_rate := 0.0
	var worst_jerk := 0.0
	var rate := 0.0
	for step: int in range(1, int(MetroRules.TRAVEL / STEP) + 1):
		var t := step * STEP
		var covered := MetroRules.distance(t) - MetroRules.distance(t - STEP)
		backwards = backwards or covered < 0
		var midpoint := MetroRules.speed(t - STEP * 0.5)
		worst_speed_error = maxf(worst_speed_error, absf(covered / STEP - midpoint))
		var next_rate := (MetroRules.speed(t) - MetroRules.speed(t - STEP)) / STEP
		worst_rate = maxf(worst_rate, absf(next_rate))
		if step > 1:
			worst_jerk = maxf(worst_jerk, absf(next_rate - rate) / STEP)
		rate = next_rate
	assert_false(backwards)
	assert_lt(worst_speed_error, 0.01, "Distance and speed agree")
	assert_lt(worst_rate, MetroRules.ACCELERATION + 0.01)
	assert_lt(worst_jerk, MetroRules.ACCELERATION / MetroRules.EASE * 1.05, "No acceleration step")


func test_station_hands_over_trains_out_of_sight() -> void:
	assert_eq(MetroRules.train_z(MetroRules.DEPART), 0.0)
	assert_eq(MetroRules.train_z(MetroRules.PERIOD), 0.0)
	var previous := 0.0
	var jumps := 0
	var hidden_jumps := 0
	var last_departing := -1.0
	var first_arriving := -1.0
	for step: int in range(1, int(MetroRules.TRAVEL / STEP) + 1):
		var time := MetroRules.DEPART + step * STEP
		var z := MetroRules.train_z(time)
		if absf(z - previous) > 2.0:
			jumps += 1
			if MetroRules.train_hidden(previous) and MetroRules.train_hidden(z):
				hidden_jumps += 1
		if not MetroRules.train_hidden(z):
			if z < 0:
				last_departing = time
			elif first_arriving < 0:
				first_arriving = time
		previous = z
	assert_eq(jumps, 1, "Only the hand-over is discontinuous")
	assert_eq(hidden_jumps, 1, "Both trains are behind tunnel walls at the hand-over")
	assert_lt(last_departing, first_arriving, "Never two trains in sight")
	assert_gt(last_departing - MetroRules.DEPART, 8.0, "Departure stays visible into the tunnel")


func test_station_view_follows_the_profile() -> void:
	var zone := metro.stations[1]
	zone.load_room(10000)
	await wait_physics_frames(3)
	for time: float in [5.0, MetroRules.DEPART + 3, MetroRules.DEPART + 9, MetroRules.PERIOD - 2]:
		metro.net_time = time
		zone.update_view()
		assert_almost_eq(zone.train.position.z, MetroRules.train_z(time), 0.0001)
		assert_eq(zone.train.visible, not MetroRules.train_hidden(zone.train.position.z))
		if time > MetroRules.DEPART:
			assert_eq(zone._hum.position.z, zone.train.position.z, "Rumble travels with it")


func test_ride_scenery_runs_the_trip_between_aligned_platforms() -> void:
	var ride := metro.rides[2]
	ride.load_room(10000)
	await wait_physics_frames(3)
	var scenery := ride.scenery
	var expected := {
		3.0: MetroRules.SPACING,
		MetroRules.OPEN + MetroRules.DWELL: 0.0,
		MetroRules.DEPART: 0.0,
		MetroRules.DEPART + 4: MetroRules.distance(4),
		MetroRules.DEPART + MetroRules.TRAVEL * 0.5: MetroRules.SPACING * 0.5,
		MetroRules.PERIOD: MetroRules.SPACING,
	}
	for time: float in expected:
		metro.net_time = time
		ride.update_view()
		assert_almost_eq(scenery.position.z, float(expected[time]), 0.001, "At %s s" % time)
		for material: ShaderMaterial in ride._scrolling:
			assert_almost_eq(
				float(material.get_shader_parameter(&"scroll")), scenery.position.z, 0.001
			)
	assert_gt(ride._scrolling.size(), 3, "Walls, floors and steel all scroll")
	# The platform beside the train at each end is the one it is standing at.
	metro.net_time = MetroRules.DEPART
	ride.update_view()
	assert_almost_eq(ride.to_local(scenery.get_node("Departure").global_position).z, 0.0, 0.001)
	metro.net_time = MetroRules.PERIOD
	ride.update_view()
	assert_almost_eq(ride.to_local(scenery.get_node("Arrival").global_position).z, 0.0, 0.001)
	assert_eq(scenery.find_children("*", "CollisionObject3D", true, false).size(), 0)
	var shapes := 0
	for grid: Node in scenery.find_children("*", "GridMap", true, false):
		var library := (grid as GridMap).mesh_library
		for item: int in library.get_item_list():
			shapes += library.get_item_shapes(item).size()
	assert_eq(shapes, 0, "Passing scenery never collides")


func test_ride_windows_show_named_platforms_signals_and_few_lights() -> void:
	var ride := metro.rides[2]
	ride.load_room(10000)
	await wait_physics_frames(3)
	metro.net_cycle = 2
	metro.net_time = MetroRules.DEPART + 3
	ride.update_view()
	var from := MetroRules.NAMES[MetroRules.station(2, 2)]
	var to := MetroRules.NAMES[MetroRules.station(2, 3)]
	assert_false(ride._departure_boards.is_empty())
	assert_false(ride._arrival_boards.is_empty())
	assert_true(ride._departure_boards[0].text.begins_with(from))
	assert_true(ride._arrival_boards[0].text.begins_with(to))
	assert_eq(ride._signals.size(), 3)
	metro.net_time = MetroRules.DEPART + 1
	ride.update_view()
	assert_eq(_aspects(ride), [3, 0], "Every block ahead is clear")
	metro.net_time = MetroRules.DEPART + MetroRules.TRAVEL * 0.5
	ride.update_view()
	assert_eq(_aspects(ride), [1, 2], "Passed signals drop to danger")
	var worst := 0
	for step: int in int(MetroRules.TRAVEL * 2) + 1:
		metro.net_time = MetroRules.DEPART + step * 0.5
		ride.update_view()
		var lit := 0
		for light: Node in ride._content.find_children("*", "Light3D", true, false):
			if (light as Light3D).is_visible_in_tree():
				lit += 1
		worst = maxi(worst, lit)
	assert_lte(worst, 24, "Distant platform and tunnel lights stay off")


func test_hum_and_rattle_follow_speed() -> void:
	var ride := metro.rides[0]
	ride.load_room(10000)
	await wait_physics_frames(3)
	var rider := PLAYER.instantiate() as Player
	rider.name = "1"
	rider.position = ride.position + Vector3(0, 2.1244, 2.5)
	add_child_autofree(rider)
	rider.set_physics_process(false)
	(rider.get_node("Camera") as Camera3D).current = true
	metro.net_time = MetroRules.DEPART
	ride._process(0)
	var idle_pitch := ride._hum.pitch_scale
	assert_eq(ride._shake_offset, Vector2.ZERO, "A standing train is still")
	metro.net_time = MetroRules.DEPART + MetroRules.TRAVEL * 0.5 + 0.01
	ride._process(0)
	assert_gt(ride._hum.pitch_scale, idle_pitch)
	assert_ne(ride._shake_offset, Vector2.ZERO)
	ride._clear_shake()


func _aspects(ride: MetroZone) -> Array:
	var clear := 0
	var stop := 0
	for head: Node3D in ride._signals:
		clear += int((head.get_node("Clear") as Node3D).visible)
		stop += int((head.get_node("Stop") as Node3D).visible)
	return [clear, stop]
