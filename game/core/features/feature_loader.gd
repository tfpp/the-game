class_name FeatureLoader
extends RefCounted
## Self-registration for features: every `res://features/<name>/feature.tscn` is
## instanced as a child named `<name>` of the Features node, in name order, so node paths
## match on every peer. Directories without a `feature.tscn` are skipped.
## Uses ResourceLoader.list_directory, which also works in exported builds (remapped and
## converted resources), unlike plain DirAccess file names.

const DEFAULT_BASE_PATH := "res://features/"
const SCENE_FILE := "feature.tscn"


## Names of feature directories under `base_path` that contain a feature scene, sorted.
static func find_features(base_path: String = DEFAULT_BASE_PATH) -> Array[String]:
	var base := base_path if base_path.ends_with("/") else base_path + "/"
	var names: Array[String] = []
	for entry: String in ResourceLoader.list_directory(base):
		if not entry.ends_with("/"):
			continue
		var feature_name := entry.trim_suffix("/")
		if ResourceLoader.exists(base + feature_name + "/" + SCENE_FILE):
			names.append(feature_name)
	names.sort()
	return names


## Instances each feature scene under `parent`. Broken features are reported and skipped.
## Returns the names of the features that were added.
static func load_features(parent: Node, base_path: String = DEFAULT_BASE_PATH) -> Array[String]:
	var base := base_path if base_path.ends_with("/") else base_path + "/"
	var loaded: Array[String] = []
	for feature_name: String in find_features(base):
		var node := instantiate_feature(base + feature_name + "/" + SCENE_FILE)
		if node == null:
			continue
		node.name = feature_name
		parent.add_child(node)
		if node.name != feature_name:
			push_error("Feature '%s' isn't a valid node name, got '%s'" % [feature_name, node.name])
		loaded.append(feature_name)
	return loaded


static func instantiate_feature(scene_path: String) -> Node:
	if not ResourceLoader.exists(scene_path):
		push_error("Feature scene not found: %s" % scene_path)
		return null
	var scene := ResourceLoader.load(scene_path) as PackedScene
	if scene == null:
		push_error("Feature scene isn't a loadable scene: %s" % scene_path)
		return null
	if not scene.can_instantiate():
		push_error("Feature scene can't be instanced: %s" % scene_path)
		return null
	var node := scene.instantiate()
	if node == null:
		push_error("Feature scene has no root node: %s" % scene_path)
		return null
	return node
