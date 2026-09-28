extends GutTest
## Coverage for the arena's target spawning (shooting_gallery.gd), the same
## MultiplayerSpawner-driven pattern test_frogs.gd would cover for
## features/frogs/frogs.gd.

const FeatureScene := preload("res://features/shooting_gallery/feature.tscn")

var _feature: Node3D


func before_each() -> void:
	_feature = FeatureScene.instantiate() as Node3D
	add_child_autofree(_feature)
	await get_tree().physics_frame
	_feature._on_mode_changed(Network.Mode.OFFLINE)


func test_spawns_one_target_per_configured_spawn_point() -> void:
	var targets := get_tree().get_nodes_in_group(&"shooting_gallery_targets")
	assert_eq(targets.size(), _feature.TARGET_SPAWNS.size())


func test_spawned_targets_are_killable_and_start_alive() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"shooting_gallery_targets"):
		var target := node as HumanoidTarget
		assert_not_null(target)
		assert_true(target.is_in_group(&"killable"))
		assert_true(target.net_alive)


func test_targets_are_scattered_not_stacked_on_one_spot() -> void:
	var positions: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group(&"shooting_gallery_targets"):
		positions.append((node as Node3D).position)
	for i: int in positions.size():
		for j: int in range(i + 1, positions.size()):
			assert_gt(positions[i].distance_to(positions[j]), 1.0)


func test_entrance_and_exit_portals_are_reachable_interactables() -> void:
	var entrance := _feature.get_node("Entrance") as TeleportPortal
	var exit := _feature.get_node("Arena/Exit") as TeleportPortal
	assert_true(entrance.is_in_group(&"interactables"))
	assert_true(exit.is_in_group(&"interactables"))
	assert_true(exit.destination.distance_to(entrance.global_position) > 3.0)
	assert_true(entrance.destination.distance_to(exit.global_position) > 3.0)
