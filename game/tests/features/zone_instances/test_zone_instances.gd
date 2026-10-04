extends GutTest

const ZONES_SCENE := preload("res://features/zone_instances/feature.tscn")
const RUN_SCENE := preload("res://features/slum_runs/feature.tscn")
const HOLDABLES_SCENE := preload("res://features/holdables/feature.tscn")


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


func test_membership_notifications_cover_join_leave_and_transfer() -> void:
	var registry := ZoneRegistry.new()
	var changed: Array[int] = []
	registry.membership_changed.connect(func(id: int) -> void: changed.append(id))
	var arrival := _arrival(Vector3.ZERO)
	var first := registry.create([1, 2] as Array[int], arrival)
	var second := registry.create([3] as Array[int], arrival)
	changed.clear()
	assert_true(registry.join(second, 2))
	assert_eq(changed, [first, second] as Array[int])
	changed.clear()
	assert_true(registry.join(second, 2))
	assert_true(changed.is_empty(), "Repeated joins do not trigger redundant updates")
	registry.leave(3)
	assert_eq(changed, [second] as Array[int])
	assert_eq(registry.members(second), [2] as Array[int])


func test_bound_scene_tracks_members_and_is_freed_when_group_empties() -> void:
	var zones := ZONES_SCENE.instantiate() as ZoneInstances
	add_child_autofree(zones)
	var id := zones.registry.create([1, 2] as Array[int], _arrival(Vector3.ZERO))
	var scope := ZoneScope.new()
	assert_true(zones.bind_scope(id, scope))
	assert_eq(scope.members, [1, 2] as Array[int])
	assert_eq(scope.instance_id, id)
	add_child(scope)
	assert_false(zones.bind_scope(id, scope), "Cannot replace an existing scene")
	zones.registry.leave(2)
	assert_eq(scope.members, [1] as Array[int])
	zones.registry.join(id, 3)
	assert_eq(scope.members, [1, 3] as Array[int])
	zones.registry.leave(1)
	zones.registry.leave(3)
	assert_null(zones.scope_for(id))
	assert_true(scope.is_queued_for_deletion())
	assert_false(scope.network_peer_allowed(3), "No stale member during deferred removal")
	await wait_physics_frames(1)
	assert_false(is_instance_valid(scope))


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


func test_excursion_scenes_are_real_separate_copies_and_empty_group_is_removed() -> void:
	var zones := ZONES_SCENE.instantiate() as ZoneInstances
	add_child_autofree(zones)
	var arrival := _arrival(Vector3.ZERO)
	var first := zones.create_excursion(
		[1] as Array[int], arrival, SlumInstance.Destination.ALLEYS, 42
	)
	var second := zones.create_excursion(
		[2] as Array[int], arrival, SlumInstance.Destination.ALLEYS, 43
	)
	assert_not_null(first)
	assert_not_null(second)
	assert_ne(first.instance_id, second.instance_id)
	assert_eq(second.position - first.position, Vector3(4000, 0, 0))
	assert_not_null(first.arrival)
	assert_not_null(second.arrival)
	assert_false(first.arrival.is_in_group(&"slum_arrival_points"))
	assert_true(first.is_ancestor_of(first.arrival))
	assert_ne(first.get_node("Map/District/Ground"), second.get_node("Map/District/Ground"))
	zones.registry.leave(1)
	await wait_physics_frames(1)
	assert_false(is_instance_valid(first))
	assert_true(is_instance_valid(second))
	assert_null(
		zones.create_excursion([] as Array[int], arrival, SlumInstance.Destination.GARAGE, 42)
	)


func test_dropped_items_follow_their_instance_and_are_removed_with_it() -> void:
	var zones := ZONES_SCENE.instantiate() as ZoneInstances
	add_child_autofree(zones)
	var holdables := HOLDABLES_SCENE.instantiate()
	add_child_autofree(holdables)
	var first := zones.create_excursion(
		[2] as Array[int], _arrival(Vector3.ZERO), SlumInstance.Destination.ALLEYS, 42
	)
	var second := zones.create_excursion(
		[3] as Array[int], _arrival(Vector3.ZERO), SlumInstance.Destination.ALLEYS, 43
	)
	var origin := first.global_position + Vector3(0, 1, 0)
	holdables.spawn_thrown_item("scrap", origin, origin)
	holdables.spawn_thrown_item("scrap", Vector3.ZERO, Vector3.ZERO)
	var private_drop := holdables.get_node("Thrown/Thrown1") as ThrownItem
	var shared_drop := holdables.get_node("Thrown/Thrown2") as ThrownItem
	assert_eq(private_drop.instance_id, first.instance_id)
	assert_true(private_drop.network_peer_allowed(2))
	assert_true(private_drop.network_peer_allowed(1), "Server retains simulation access")
	assert_false(private_drop.network_peer_allowed(3))
	assert_false(private_drop.network_peer_allowed(4))
	assert_true(shared_drop.network_peer_allowed(4))
	assert_false(shared_drop.network_peer_allowed(2), "Slum members cannot observe hub drops")
	zones.registry.leave(2)
	assert_false(
		private_drop.network_peer_allowed(2), "Returning immediately revokes pickup access"
	)
	await wait_physics_frames(1)
	assert_false(is_instance_valid(private_drop))
	assert_true(is_instance_valid(shared_drop))
	assert_true(is_instance_valid(second))
