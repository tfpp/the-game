extends GutTest

const ZONES_SCENE := preload("res://features/zone_instances/feature.tscn")
const RUN_SCENE := preload("res://features/slum_runs/feature.tscn")


func _arrival(at: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.position = at
	add_child_autofree(marker)
	return marker


func test_two_groups_get_two_far_apart_instances() -> void:
	var registry := ZoneRegistry.new()
	var garage := _arrival(Vector3.ZERO)
	var alley := _arrival(Vector3(0, 0, 900))
	var a := registry.create([1, 2] as Array[int], garage)
	var b := registry.create([3] as Array[int], alley)
	assert_ne(a, b)
	assert_eq(registry.instance_of(1), a)
	assert_eq(registry.instance_of(2), a)
	assert_eq(registry.instance_of(3), b)
	assert_eq(registry.arrival_of(a), garage)
	assert_eq(registry.arrival_of(b), alley)
	assert_eq(registry.offset_of(a), Vector3.ZERO)
	assert_eq(registry.offset_of(b), Vector3(ZoneRegistry.OFFSET_STEP_M, 0, 0))
	assert_eq(registry.instance_of(99), -1)


func test_last_member_leaving_frees_the_instance_and_its_slot() -> void:
	var registry := ZoneRegistry.new()
	var freed: Array[int] = []
	registry.instance_freed.connect(func(id: int) -> void: freed.append(id))
	var a := registry.create([1, 2] as Array[int], _arrival(Vector3.ZERO))
	var b := registry.create([3] as Array[int], _arrival(Vector3.ZERO))
	registry.leave(1)
	assert_true(registry.has_instance(a))
	assert_eq(registry.members(a), [2] as Array[int])
	registry.leave(2)
	assert_false(registry.has_instance(a))
	assert_eq(freed, [a] as Array[int])
	var c := registry.create([4] as Array[int], _arrival(Vector3.ZERO))
	assert_eq(registry.slot_of(c), 0, "freed slot is reused")
	assert_eq(registry.slot_of(b), 1)
	registry.leave(1)
	assert_eq(freed, [a] as Array[int], "leaving twice is harmless")


func test_peers_belong_to_one_instance_at_a_time() -> void:
	var registry := ZoneRegistry.new()
	var a := registry.create([1] as Array[int], _arrival(Vector3.ZERO))
	var b := registry.create([2] as Array[int], _arrival(Vector3.ZERO))
	assert_true(registry.join(b, 1))
	assert_false(registry.has_instance(a))
	assert_eq(registry.members(b).size(), 2)
	assert_false(registry.join(a, 3), "cannot join a freed instance")
	assert_eq(registry.create([] as Array[int], _arrival(Vector3.ZERO)), -1)


func test_disconnect_frees_and_offline_single_peer_works() -> void:
	var zones := ZONES_SCENE.instantiate() as ZoneInstances
	add_child_autofree(zones)
	assert_eq(ZoneInstances.registry_for(get_tree(), null), zones.registry)
	var id := zones.registry.create([1] as Array[int], _arrival(Vector3.ZERO))
	assert_eq(zones.registry.instance_of(1), id)
	zones._on_peer_disconnected(1)
	assert_false(zones.registry.has_instance(id))


func test_gate_runs_are_recorded_in_the_shared_registry() -> void:
	var zones := ZONES_SCENE.instantiate() as ZoneInstances
	add_child_autofree(zones)
	var runs := RUN_SCENE.instantiate() as SlumRuns
	add_child_autofree(runs)
	var arrival := SlumArrivalPoint.new()
	add_child_autofree(arrival)
	runs.begin(1, arrival)
	runs.begin(2, arrival)
	var id := zones.registry.instance_of(1)
	assert_ne(id, -1)
	assert_eq(zones.registry.instance_of(2), id)
	assert_eq(runs.choose_arrival(), arrival)
	runs.finish(1)
	zones._on_peer_disconnected(2)
	assert_false(runs.is_active(2))
	assert_false(zones.registry.has_instance(id))
	runs.begin(3, arrival)
	assert_ne(zones.registry.instance_of(3), id, "a new run gets a new instance")
