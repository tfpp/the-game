extends GutTest
## Live casino cleanup preserves travel endpoints without loading the old room.

const SCENES: Array[PackedScene] = [
	preload("res://features/dev_room/feature.tscn"),
	preload("res://features/starter_room/feature.tscn"),
	preload("res://features/street_district/feature.tscn"),
	preload("res://features/slum_runs/feature.tscn"),
	preload("res://features/strip_mall/feature.tscn"),
	preload("res://features/chicken_betting/feature.tscn"),
]
const Cheats := preload("res://tests/features/dev_access/cheats_fixture.gd")


func test_old_casino_is_not_discovered_or_listed_even_with_cheats() -> void:
	assert_false(FeatureLoader.find_features().has("casino_legacy"))
	assert_false(ResourceLoader.exists("res://features/casino_legacy/feature.tscn"))
	Cheats.enable(self)
	var gps := preload("res://features/gps/feature.tscn").instantiate() as Gps
	add_child_autofree(gps)
	for scene: PackedScene in SCENES:
		add_child_autofree(scene.instantiate())
	for destination: GpsDestination in gps.destinations():
		assert_ne(destination.label, "Old Golden Crown Casino")
	for link: Dictionary in gps.links():
		assert_ne(link["label"], "Visit the old casino")
	assert_true(
		ResourceLoader.exists("res://world/room.tscn"),
		"Shared legacy authoring/test assets are retained"
	)


func test_main_casino_overhead_signs_stay_absent_on_late_load_and_cheat_toggle() -> void:
	var noclip := Cheats.enable(self)
	for repeat: int in 2:
		for scene: PackedScene in SCENES:
			var feature := scene.instantiate() as Node3D
			add_child_autofree(feature)
			_assert_no_overhead_signs(feature)
		noclip.set(&"cheats_enabled", repeat != 0)
		for gate: Node in get_tree().get_nodes_in_group(&"dev_gates"):
			(gate as DevGate).refresh()
		for feature: Node in get_children():
			if feature is Node3D:
				_assert_no_overhead_signs(feature)


func test_unsigned_doors_keep_positions_prompts_and_destinations() -> void:
	var paths: Array[String] = [
		"CasinoArrival", "CasinoReturn", "CasinoStreetEntrance", "Gate", "Entrance", "Entrance"
	]
	var positions: Array[Vector3] = [
		Vector3(12, 1.2, -17.4),
		Vector3(-7, 1.1, -19.7),
		Vector3(7, 1.1, -19.7),
		Vector3(18, 1.1, 19.8),
		Vector3(1.8, 1.25, 25),
		Vector3(-20, 1.25, -19.65),
	]
	for i: int in SCENES.size():
		var feature := SCENES[i].instantiate() as Node3D
		add_child_autofree(feature)
		var door := feature.get_node(paths[i]) as Node3D
		assert_true(door.global_position.is_equal_approx(positions[i]))
		if door is GarageDoor:
			var portal := door as GarageDoor
			assert_false(portal.door_label.is_empty(), "Use still identifies the destination")
			assert_not_null(portal.get_node_or_null(portal.destination))
		if i == 4 or i == 5:
			var return_sign := feature.get_node("Room/Exit/Sign") as Node3D
			assert_true(return_sign.visible, "Remote return signage is not part of cleanup")


func _assert_no_overhead_signs(feature: Node) -> void:
	for node: Node in feature.find_children("*", "Node3D", true, false):
		var spatial := node as Node3D
		var point := spatial.global_position
		# The Crown and its south corridor, not remote rooms or gameplay displays.
		if absf(point.x) > 35 or point.z < -25 or point.z > 40:
			continue
		if node is Label3D or node is SignBoard:
			assert_false(spatial.visible, "No overhead sign at %s" % node.get_path())
