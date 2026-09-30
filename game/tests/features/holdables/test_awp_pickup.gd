extends GutTest
## The AWP used to be a static prop (features/awp/); it's now a holdable like any
## other (see item_catalog.gd), sold on the pawn shop wall (features/pawn_shop).


func test_lobby_no_longer_gives_away_guns() -> void:
	var holdables: Node3D = add_child_autofree(
		load("res://features/holdables/feature.tscn").instantiate()
	)
	for pickup: Node in holdables.get_node("Pickups").get_children():
		var def := ItemCatalog.find(str(pickup.get("item_id")))
		assert_ne(def.category, ItemDefinition.Category.WEAPON, "%s is free" % pickup.name)


func test_view_has_a_muzzle_marker_for_the_fire_flash() -> void:
	var def := ItemCatalog.find("awp")
	var view: Node3D = add_child_autofree(def.view_scene.instantiate())
	assert_not_null(view.get_node_or_null("Muzzle"))
