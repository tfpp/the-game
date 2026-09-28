extends GutTest
## Feature self-registration (core/features/feature_loader.gd).

const FIXTURES := "res://tests/fixtures/features/"


func test_finds_feature_dirs_sorted_and_skips_dirs_without_scene() -> void:
	assert_eq(FeatureLoader.find_features(FIXTURES), ["alpha", "zeta"] as Array[String])


func test_accepts_base_path_without_trailing_slash() -> void:
	assert_eq(
		FeatureLoader.find_features(FIXTURES.trim_suffix("/")), ["alpha", "zeta"] as Array[String]
	)


func test_missing_base_dir_finds_nothing() -> void:
	assert_eq(FeatureLoader.find_features("res://tests/fixtures/nope/"), [] as Array[String])


func test_loads_features_named_after_their_dirs_in_order() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var loaded := FeatureLoader.load_features(parent, FIXTURES)
	assert_eq(loaded, ["alpha", "zeta"] as Array[String])
	assert_eq(parent.get_child_count(), 2)
	assert_eq(parent.get_child(0).name, &"alpha")
	assert_eq(parent.get_child(1).name, &"zeta")
	assert_not_null(parent.get_node_or_null("alpha"))


func test_feature_keeps_its_own_transform() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	FeatureLoader.load_features(parent, FIXTURES)
	var alpha := parent.get_node("alpha") as Node3D
	assert_eq(alpha.global_position, Vector3(4, 0, -2))


func test_broken_feature_is_skipped_with_an_error() -> void:
	var parent: Node3D = add_child_autofree(Node3D.new())
	var loaded := FeatureLoader.load_features(parent, "res://tests/fixtures/broken_features/")
	assert_eq(loaded, ["good"] as Array[String])
	assert_eq(parent.get_child_count(), 1)
	assert_push_error("isn't a loadable scene")


func test_missing_scene_is_an_error() -> void:
	assert_null(FeatureLoader.instantiate_feature(FIXTURES + "missing/feature.tscn"))
	assert_push_error("not found")


func test_real_features_load_cleanly() -> void:
	# The game's own features directory (possibly empty) loads without errors.
	var parent: Node3D = add_child_autofree(Node3D.new())
	var loaded := FeatureLoader.load_features(parent)
	assert_eq(parent.get_child_count(), loaded.size())
