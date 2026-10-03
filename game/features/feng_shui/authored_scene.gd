extends RefCounted
## Read authored geometry without running gameplay scripts (_init included).
## Temporary plain nodes never enter the SceneTree and are freed after snapshotting.

const GEOMETRY_PROPERTIES: Array[StringName] = [
	&"transform",
	&"position",
	&"rotation",
	&"rotation_degrees",
	&"scale",
	&"mesh",
	&"size",
	&"radius",
	&"height",
	&"metadata/prop_id",
	&"metadata/feng_shui_element"
]


static func geometry(scene: PackedScene) -> Node:
	var root := _build(scene.get_state())
	root.scene_file_path = scene.resource_path
	return root


static func _build(state: SceneState) -> Node:
	var root: Node
	var base := state.get_base_scene_state()
	if base != null:
		root = _build(base)
	for index: int in state.get_node_count():
		var path := state.get_node_path(index)
		var node := root.get_node_or_null(path) if root != null else null
		if node == null:
			var instance := state.get_node_instance(index)
			node = (
				geometry(instance) if instance != null else _plain_node(state.get_node_type(index))
			)
			var node_name := state.get_node_name(index)
			if not node_name.is_empty():
				node.name = node_name
			if root == null:
				root = node
			else:
				var parent := root.get_node_or_null(state.get_node_path(index, true))
				if parent == null:
					node.free()
					continue
				parent.add_child(node)
		for property_index: int in state.get_node_property_count(index):
			var property := state.get_node_property_name(index, property_index)
			if property not in GEOMETRY_PROPERTIES:
				continue
			# Ignore e.g. Control.size on a plain grouping node.
			if property.begins_with("metadata/"):
				node.set_meta(
					property.trim_prefix("metadata/"),
					state.get_node_property_value(index, property_index)
				)
			elif _has_property(node, property):
				node.set(property, state.get_node_property_value(index, property_index))
	return root


static func _plain_node(type: StringName) -> Node:
	match type:
		&"MeshInstance3D":
			return MeshInstance3D.new()
		&"CSGBox3D":
			return CSGBox3D.new()
		&"CSGCylinder3D":
			return CSGCylinder3D.new()
		&"CSGSphere3D":
			return CSGSphere3D.new()
		&"OmniLight3D", &"SpotLight3D", &"DirectionalLight3D":
			return OmniLight3D.new()
		&"CharacterBody3D":
			return CharacterBody3D.new()
		&"GridMap":
			return GridMap.new()
	if ClassDB.is_parent_class(type, &"Node3D"):
		return Node3D.new()
	return Node.new()


static func _has_property(node: Node, property: StringName) -> bool:
	for descriptor: Dictionary in node.get_property_list():
		if descriptor["name"] == property:
			return true
	return false
