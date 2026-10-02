class_name ZoneInstances
extends Node
## Server-owned registry of slum zone instances (see README.md). Shared zones such as
## the Crown are not tracked. Members leave on disconnect; callers report returns
## and deaths through `leave()`.

const GROUP := &"zone_instances"

var registry := ZoneRegistry.new()


func _ready() -> void:
	add_to_group(GROUP)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)


## The scene's registry, or `fallback` when the feature is not loaded (unit tests
## that build a single feature).
static func registry_for(tree: SceneTree, fallback: ZoneRegistry) -> ZoneRegistry:
	var node := tree.get_first_node_in_group(GROUP) as ZoneInstances
	return node.registry if node != null else fallback


func _on_peer_disconnected(peer_id: int) -> void:
	if multiplayer.is_server():
		registry.leave(peer_id)


func _on_mode_changed(_mode: Network.Mode) -> void:
	registry.clear()
