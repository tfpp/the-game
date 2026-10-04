class_name ZoneScope
extends Node3D
## Root of a privately spawned slum. Set membership before attaching the scene so
## child synchronizers never advertise initial state to unrelated peers.

@export var instance_id := -1
@export var members: Array[int] = []


func _enter_tree() -> void:
	add_to_group(&"zone_scopes")


func _ready() -> void:
	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:members"))
	config.property_set_spawn(NodePath(".:members"), true)
	config.property_set_replication_mode(
		NodePath(".:members"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE
	)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "ScopeSync"
	sync.replication_config = config
	sync.root_path = NodePath("..")
	sync.add_visibility_filter(network_peer_allowed)
	add_child(sync)
	sync.update_visibility()


func network_peer_allowed(peer: int) -> bool:
	# The server must receive client-owned movement and simulate every instance.
	return peer == MultiplayerPeer.TARGET_PEER_SERVER or peer in members


func replace_members(peers: Array[int]) -> void:
	members = peers.duplicate()
	if is_inside_tree():
		refresh_visibility(self)


static func refresh_visibility(root: Node) -> void:
	var synchronizers: Array[MultiplayerSynchronizer] = []
	_collect_synchronizers(root, synchronizers)
	# Stop descendant state before a root visibility change despawns its subtree.
	# Use the synchronized target depth, independent of scene child order.
	synchronizers.sort_custom(
		func(a: MultiplayerSynchronizer, b: MultiplayerSynchronizer) -> bool:
			return (
				a.get_node(a.root_path).get_path().get_name_count()
				> b.get_node(b.root_path).get_path().get_name_count()
			)
	)
	for sync: MultiplayerSynchronizer in synchronizers:
		sync.update_visibility()


static func _collect_synchronizers(node: Node, result: Array[MultiplayerSynchronizer]) -> void:
	if node is MultiplayerSynchronizer and node.is_multiplayer_authority():
		result.append(node as MultiplayerSynchronizer)
	for child: Node in node.get_children():
		_collect_synchronizers(child, result)
