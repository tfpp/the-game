extends GutTest
## Every enemy stands on real garage floor, clear of cars and columns, away
## from the arrival door, and danger rises with each floor above it.

const GARAGE := preload("res://features/parking_garage/feature.tscn")
const ENEMIES := preload("res://features/garage_enemies/feature.tscn")
const ARRIVAL := Vector3(-10, 0, 595)

var _enemies: Node3D

var _garage: Node


func before_all() -> void:
	_garage = GARAGE.instantiate()
	add_child(_garage)
	_enemies = ENEMIES.instantiate() as Node3D
	add_child(_enemies)
	for enemy: GarageEnemy in _list():
		enemy.set_physics_process(false)
	await wait_physics_frames(3)


func after_all() -> void:
	_garage.free()
	_enemies.free()


func _list() -> Array[GarageEnemy]:
	var out: Array[GarageEnemy] = []
	for child: Node in _enemies.get_children():
		out.append(child as GarageEnemy)
	return out


func test_enemies_stand_on_a_floor_slab() -> void:
	for enemy: GarageEnemy in _list():
		var at := enemy.global_position
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN)
		query.collision_mask = 1
		var hit := get_tree().root.get_world_3d().direct_space_state.intersect_ray(query)
		assert_false(hit.is_empty(), "%s needs floor" % enemy.name)
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, at.y, 0.05, str(enemy.name))


func test_enemies_start_clear_of_obstacles() -> void:
	var space := get_tree().root.get_world_3d().direct_space_state
	for enemy: GarageEnemy in _list():
		var query := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.5
		capsule.height = 1.6
		query.shape = capsule
		query.transform = Transform3D(Basis(), enemy.global_position + Vector3.UP * 1.0)
		query.collision_mask = 1
		assert_eq(space.intersect_shape(query).size(), 0, "%s clips geometry" % enemy.name)


func test_arrival_level_is_the_gentlest() -> void:
	var max_tier_by_floor := {}
	for enemy: GarageEnemy in _list():
		var level := roundi(enemy.position.y / 3.3)
		max_tier_by_floor[level] = maxi(int(max_tier_by_floor.get(level, 0)), enemy.tier)
		if level == 0:
			assert_eq(enemy.tier, GarageEnemyTiers.Tier.LURKER)
			var gap := GarageEnemyTiers.flat_distance(enemy.global_position, ARRIVAL)
			assert_gt(gap, 10.0, "%s too close to the door" % enemy.name)
	assert_lt(int(max_tier_by_floor[0]), int(max_tier_by_floor[1]))
	assert_lt(int(max_tier_by_floor[1]), int(max_tier_by_floor[2]))
	assert_eq(max_tier_by_floor.size(), 3)
