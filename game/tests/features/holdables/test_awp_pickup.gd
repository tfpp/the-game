extends GutTest
## The AWP used to be a static prop (features/awp/); it's now a holdable pickup like
## any other (see item_catalog.gd), still sitting in the middle of the map.

const FEATURE_SCENE := "res://features/holdables/feature.tscn"


func test_sits_in_the_middle_of_the_map() -> void:
	var holdables: Node3D = add_child_autofree(load(FEATURE_SCENE).instantiate())
	var awp := holdables.get_node("Pickups/Awp") as ItemPickup
	assert_eq(awp.item_id, "awp")
	assert_eq(awp.global_position.x, 0.0)
	assert_eq(awp.global_position.z, 0.0)


func test_view_has_a_muzzle_marker_for_the_fire_flash() -> void:
	var def := ItemCatalog.find("awp")
	var view: Node3D = add_child_autofree(def.view_scene.instantiate())
	assert_not_null(view.get_node_or_null("Muzzle"))
