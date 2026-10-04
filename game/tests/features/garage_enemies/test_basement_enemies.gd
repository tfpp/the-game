extends GutTest
## The basement garage (features/procedural_rooms, B1 at the top, B5 at the
## bottom) holds brawlers near the elevator arrival, knifers further down and
## gunmen on the lowest floors. Every enemy stands on real deck floor, clear of
## geometry, in the lanes the population rules keep free of set pieces.

const DECK_SPACING := 4.0

var _rooms: SlumInstance
var _enemies: Node3D


func before_all() -> void:
	_rooms = SlumInstance.new()
	_rooms.enemy_plan = GarageRunPlan.enemies(73021)
	_rooms.position = Vector3(0, 0, 12000)
	_rooms.rotation.y = -PI / 2
	add_child(_rooms)
	_enemies = _rooms.get_node("Map/CrownGarage/Enemies") as Node3D
	for enemy: GarageEnemy in _list():
		enemy.set_physics_process(false)
	await wait_physics_frames(3)


func after_all() -> void:
	_rooms.free()


func _list() -> Array[GarageEnemy]:
	var out: Array[GarageEnemy] = []
	for child: Node in _enemies.get_children():
		out.append(child as GarageEnemy)
	return out


func test_deep_encounter_tuning_keeps_base_profiles_and_other_floors_unchanged() -> void:
	var deep_gunman: GarageEnemy
	var upper_gunman: GarageEnemy
	for enemy: GarageEnemy in _list():
		if enemy.tier != GarageEnemyTiers.Tier.GUNMAN:
			continue
		if is_zero_approx(enemy.home().y):
			deep_gunman = enemy
		else:
			upper_gunman = enemy
	assert_not_null(deep_gunman)
	assert_not_null(upper_gunman)
	assert_eq(deep_gunman.profile()["damage"], 22.5)
	assert_almost_eq(deep_gunman.profile()["windup"], .45, .0001)
	assert_eq(upper_gunman.profile()["damage"], 15.0)
	assert_eq(upper_gunman.profile()["windup"], .6)
	assert_eq(GarageEnemyTiers.profile(GarageEnemyTiers.Tier.GUNMAN)["damage"], 15.0)
	assert_eq(GarageEnemyTiers.profile(GarageEnemyTiers.Tier.GUNMAN)["windup"], .6)


## B1 is 1, B5 is 5.
func _basement_level(enemy: GarageEnemy) -> int:
	return 5 - roundi(enemy.position.y / DECK_SPACING)


func test_basement_lines_up_with_the_procedural_garage() -> void:
	var garage := _rooms.get_node("Map/CrownGarage") as Node3D
	var basement := _enemies
	assert_true(basement.global_transform.is_equal_approx(garage.global_transform))


func test_enemies_stand_on_deck_floor() -> void:
	var space := get_tree().root.get_world_3d().direct_space_state
	for enemy: GarageEnemy in _list():
		var at := enemy.global_position
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN)
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		assert_false(hit.is_empty(), "%s needs floor" % enemy.name)
		if not hit.is_empty():
			assert_almost_eq((hit["position"] as Vector3).y, at.y, 0.05, str(enemy.name))


func test_enemies_start_clear_of_geometry_and_in_open_lanes() -> void:
	var space := get_tree().root.get_world_3d().direct_space_state
	var rule := ProceduralPopulationRule.new()
	for enemy: GarageEnemy in _list():
		var query := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.5
		capsule.height = 1.6
		query.shape = capsule
		query.transform = Transform3D(Basis(), enemy.global_position + Vector3.UP * 1.0)
		query.collision_mask = 1
		assert_eq(space.intersect_shape(query).size(), 0, "%s clips geometry" % enemy.name)
		# Front and back lanes are reserved from set pieces (z < 8 or z > 34).
		var local := enemy.position
		local.y = 0.5
		var lane := rule.forbidden_volumes[1].has_point(local)
		lane = lane or rule.forbidden_volumes[2].has_point(local)
		assert_true(lane, "%s stands in a set-piece-free lane" % enemy.name)


func test_danger_rises_towards_b5_and_arrival_is_safe() -> void:
	var arrival := _rooms.arrival.global_position
	var strongest := {}
	for enemy: GarageEnemy in _list():
		var level := _basement_level(enemy)
		var rank := GarageEnemyTiers.rank(enemy.tier)
		strongest[level] = maxi(int(strongest.get(level, 0)), rank)
		if level == 1:
			assert_eq(enemy.tier, GarageEnemyTiers.Tier.LURKER)
			assert_gt(enemy.global_position.distance_to(arrival), 20.0, str(enemy.name))
		if enemy.tier == GarageEnemyTiers.Tier.GUNMAN:
			assert_gte(level, 4, "%s: gunmen only on the lowest floors" % enemy.name)
	assert_eq(strongest.size(), 5)
	for level: int in range(1, 5):
		assert_lte(int(strongest[level]), int(strongest[level + 1]))
	assert_eq(int(strongest[5]), GarageEnemyTiers.rank(GarageEnemyTiers.Tier.GUNMAN))


func test_facing_is_correct_under_the_rotated_basement() -> void:
	var enemy := _list()[0]
	var toward := Vector3(1, 0, 0)
	enemy.net_yaw = GarageEnemyTiers.facing_yaw(enemy._parent_direction(toward))
	enemy.get_node("Model").rotation.y = enemy.net_yaw
	var forward := -(enemy.get_node("Model") as Node3D).global_basis.z
	assert_almost_eq(forward.x, 1.0, 0.01)
