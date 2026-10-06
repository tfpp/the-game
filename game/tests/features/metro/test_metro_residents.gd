extends GutTest

const METRO := preload("res://features/metro/feature.tscn")
var metro: MetroService


func before_each() -> void:
	metro = METRO.instantiate() as MetroService
	add_child_autofree(metro)
	metro.set_physics_process(false)
	metro.transfers.set_physics_process(false)
	metro.net_cycle = 8
	metro.net_time = 5


func test_stroll_is_bounded_resting_and_faces_its_movement() -> void:
	var start := Vector3(9, 1.2, 6)
	var end := Vector3(9, 1.2, 12)
	for clock: float in [0.0, 2.0, 4.0, 7.0, 10.0, 12.0, 14.0, 17.0, 20.0]:
		var pose := MetroResidents.stroll(start, end, clock)
		var point: Vector3 = pose["position"]
		assert_between(point.z, start.z, end.z)
		assert_almost_eq(point.y, 1.2, 0.001)
		assert_eq(point.x, 9.0)
		var forward := -Basis(Vector3.UP, pose["yaw"]).z
		assert_gt(forward.dot(Vector3.FORWARD if fposmod(clock, 20) >= 10 else Vector3.BACK), 0.99)
	assert_eq(MetroResidents.stroll(start, end, 2)["walk"], 0.0)
	assert_gt(MetroResidents.stroll(start, end, 7)["walk"], 0.0)
	assert_eq(MetroResidents.stroll(start, end, 12)["position"], end)
	assert_eq(MetroResidents.stroll(start, end, 7), MetroResidents.stroll(start, end, 27))


func test_loaded_station_has_sleepers_and_walkers_without_blocking_routes() -> void:
	var zone := metro.stations[0]
	zone.load_room(10000)
	await wait_physics_frames(4)
	var residents := zone._content.get_node("ShelteringResidents") as MetroResidents
	assert_eq(residents.models.size(), 22)
	assert_eq(residents.sleeping.count(true), 14)
	assert_eq(residents.sleeping.count(false), 8)
	assert_eq(residents.find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(residents.find_children("*", "Light3D", true, false).size(), 0)
	for index: int in residents.models.size():
		var point := residents.starts[index]
		assert_almost_eq(point.y, 1.2, 0.001, "Feet on cabin/platform floor")
		if point.x < 2 and residents.sleeping[index]:
			var cushion := point + Vector3.UP * 0.48
			assert_false(cushion in MetroSeating.layout(), "Resident buckets are reserved")
			assert_eq(residents.models[index].avatar.locomotion, &"seated")
			assert_lt(residents.models[index].avatar._torso.rotation.x, 0.0)
		if not residents.sleeping[index]:
			assert_true(point.x == 0 or point.x == 9, "Stay in clear aisle/platform lane")
			assert_lte(absf(point.z), 55.0)
	var original := residents.models[2].position
	zone.unload_room()
	await wait_physics_frames(2)
	assert_false(is_instance_valid(residents))
	zone.load_room(10000)
	await wait_physics_frames(4)
	residents = zone._content.get_node("ShelteringResidents") as MetroResidents
	assert_eq(residents.models[2].position, original, "Loading mid-cycle samples the same phase")


func test_train_residents_follow_departure_and_transit_has_only_car_residents() -> void:
	var zone := metro.stations[0]
	zone.load_room(10000)
	await wait_physics_frames(3)
	var residents := zone._content.get_node("ShelteringResidents") as MetroResidents
	var sleeper := residents.models[0]
	metro.net_time = MetroRules.DEPART + 2
	zone.update_view()
	residents.update_view(0, true)
	assert_almost_eq(sleeper.position.z - residents.starts[0].z, zone.train.position.z, 0.001)
	assert_eq(residents.models[15].position, residents.starts[15], "Platform sleeper stays")
	metro.net_time = MetroRules.DEPART + 5
	zone.update_view()
	residents.update_view(0)
	assert_false(sleeper.visible)
	assert_true(residents.models[15].visible)
	metro.rides[0].load_room(10000)
	await wait_physics_frames(3)
	var ride_people := metro.rides[0]._content.get_node("ShelteringResidents") as MetroResidents
	assert_eq(ride_people.models.size(), 15)
	assert_eq(ride_people.sleeping.count(true), 10)
	assert_eq(ride_people.sleeping.count(false), 5)
	assert_eq(ride_people.models[0].position, ride_people.starts[0])
