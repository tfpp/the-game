extends GutTest

const Population := preload("res://features/procedural_rooms/room_population.gd")
const RULE := preload("res://features/procedural_rooms/garage_population.tres")


func test_seed_reproduces_placements_and_other_seeds_produce_variety() -> void:
	var rule := RULE.duplicate() as ProceduralPopulationRule
	rule.density = 1
	var first := Population.plan(rule, 73021)
	assert_eq(first.size(), 6)
	assert_eq(first, Population.plan(rule, 73021))
	assert_ne(first, Population.plan(rule, 99021))
	for value: Dictionary in first:
		assert_true(value["kind"] in rule.allowed_sets)
		assert_true(value["yaw"] in rule.allowed_yaws)
		assert_true(rule.placement_bounds.encloses(value["bounds"]))
		for forbidden: AABB in rule.forbidden_volumes:
			assert_false(value["bounds"].intersects(forbidden))


func test_disallowed_sets_density_and_invalid_slots_never_spawn() -> void:
	var rule := RULE.duplicate() as ProceduralPopulationRule
	rule.density = 0
	assert_eq(Population.plan(rule, 1), [])
	rule.density = 1
	rule.allowed_sets = ["storage"]
	rule.weights = PackedFloat32Array([1])
	for value: Dictionary in Population.plan(rule, 1):
		assert_eq(value["kind"], "storage")
	rule.allowed_sets = ["unknown", "garage"]
	rule.weights = PackedFloat32Array([100, 0])
	assert_eq(Population.plan(rule, 1), [])
	rule.allowed_sets = ["garage"]
	rule.weights = PackedFloat32Array([1])
	rule.slots = [Vector3(0, 0, 4), Vector3(0, 0, 20), Vector3(40, 0, 20)]
	assert_eq(Population.plan(rule, 1), [])


func test_overlaps_and_arbitrary_rotations_are_rejected() -> void:
	var rule := RULE.duplicate() as ProceduralPopulationRule
	rule.density = 1
	rule.slots = [Vector3(-15, 0, 14), Vector3(-15, 0, 15)]
	assert_eq(Population.plan(rule, 1).size(), 1)
	rule.allowed_yaws = PackedFloat32Array([0.3])
	assert_eq(Population.plan(rule, 1), [])
