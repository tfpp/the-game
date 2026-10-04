extends GutTest

const FEATURE := preload("res://features/procedural_rooms/prototype.tscn")
const ROOM := preload("res://world/room.tscn")
const ANNEX := preload("res://features/annex/feature.tscn")
const Cheats := preload("res://tests/features/dev_access/cheats_fixture.gd")


func test_shared_service_lift_has_closed_collision_and_rejects_calls_without_cheats() -> void:
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var lift := feature.get_node("Garage/CrownGarage/Lift") as ProceduralMovingLift
	lift.set_physics_process(false)
	assert_false(lift.available())
	assert_false(lift.request_floor(0))
	assert_eq(lift.gates[5]._amount, 0.0)
	assert_eq(lift.cab_door._amount, 0.0)
	await wait_physics_frames(2)
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(32, 1.2, -25.4), Vector3(35.5, 1.2, -25.4), 1
	)
	assert_false(
		feature.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),
		"Closed modeled doors physically block the casino bypass"
	)
	Cheats.enable(self)
	lift._update_doors()
	assert_true(lift.available())
	assert_eq(lift.gates[5]._amount, 1.0)
	assert_true(lift.request_floor(0))


func test_casino_is_sixth_stop_and_basements_clear_the_gaming_floor() -> void:
	Cheats.enable(self)
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var lift := feature.get_node("Garage/CrownGarage/Lift") as ProceduralMovingLift
	assert_eq(lift.gates.size(), 6)
	assert_eq(lift.net_floor, 5)
	assert_lt(lift.cab.global_position.distance_to(Vector3(35.5, 0, -25)), .001)
	assert_eq(lift.cab.get_node("Floor5").call("interaction_text"), "Already at C / CASINO")
	for index: int in 5:
		var deck := feature.get_node("Garage/CrownGarage/Deck%d" % index) as Node3D
		assert_almost_eq(deck.global_position.y, -22.0 + index * 4, .001)
	assert_lt(-6.0 + 3.5, -2.3, "Basement ceiling stays below sunken gaming-floor slab")
	lift._reset(Network.Mode.OFFLINE)
	assert_eq(lift.net_floor, 5)
	assert_eq(lift.net_height, 22.0)


func test_real_casino_doorway_has_full_capsule_clearance_and_continuous_support() -> void:
	Cheats.enable(self)
	var room := ROOM.instantiate()
	add_child_autofree(room)
	add_child_autofree(ANNEX.instantiate())
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	await wait_physics_frames(3)
	var space := feature.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .4064
	capsule.height = 1.8288
	for z: float in [-25.6, -25, -24.4]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = Vector3(31, .95, z)
		query.motion = Vector3(4.5, 0, 0)
		assert_almost_eq(space.cast_motion(query)[0], 1.0, .001, "Walk from casino into cab")
		for x: float in [33.8, 34.0, 34.15, 34.3, 35.5]:
			var ray := PhysicsRayQueryParameters3D.create(Vector3(x, .2, z), Vector3(x, -.2, z))
			var hit := space.intersect_ray(ray)
			assert_false(hit.is_empty(), "Continuous casino-to-cab footing")
			if not hit.is_empty():
				assert_almost_eq((hit["position"] as Vector3).y, 0.0, .05)
		var vertical := PhysicsShapeQueryParameters3D.new()
		vertical.shape = capsule
		vertical.transform.origin = Vector3(36.15, -5.05, z)
		vertical.motion = Vector3(0, 6, 0)
		vertical.exclude = [
			(feature.get_node("Garage/CrownGarage/Lift") as ProceduralMovingLift).cab.get_rid()
		]
		assert_almost_eq(
			space.cast_motion(vertical)[0], 1.0, .001, "Rider column has no casino or annex slab"
		)


func test_empty_casino_landing_closes_while_cab_is_below() -> void:
	Cheats.enable(self)
	var feature := FEATURE.instantiate() as Node3D
	add_child_autofree(feature)
	var lift := feature.get_node("Garage/CrownGarage/Lift") as ProceduralMovingLift
	lift.set_physics_process(false)
	lift.net_floor = 4
	lift.net_target = 4
	lift.net_height = 16
	lift.cab.position.y = 16
	lift.net_aperture = 1
	lift._update_doors()
	assert_eq(lift.gates[5]._amount, 0.0)
	assert_eq(lift.gates[4]._amount, 1.0)
	assert_true(lift.request_floor(5))
	assert_eq(lift.net_target, 5)
	assert_eq(lift.net_height, 16.0, "Calling C starts closing rather than teleporting")
