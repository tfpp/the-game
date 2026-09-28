extends GutTest
## The static AWP prop (features/awp/feature.tscn) sitting in the middle of the map.

const FEATURE_SCENE := "res://features/awp/feature.tscn"


func test_sits_at_the_middle_of_the_map() -> void:
	var awp: Node3D = add_child_autofree(load(FEATURE_SCENE).instantiate())
	assert_eq(awp.global_position.x, 0.0)
	assert_eq(awp.global_position.z, 0.0)


func test_rests_on_the_floor_without_clipping_through_it() -> void:
	var awp: Node3D = add_child_autofree(load(FEATURE_SCENE).instantiate())
	assert_gt(awp.global_position.y, 0.0)


func test_has_a_collision_shape_so_players_can_see_and_bump_it() -> void:
	var awp: Node = add_child_autofree(load(FEATURE_SCENE).instantiate())
	assert_not_null(awp.get_node_or_null("Collider"))
	var collider := awp.get_node("Collider") as CollisionShape3D
	assert_not_null(collider.shape)
