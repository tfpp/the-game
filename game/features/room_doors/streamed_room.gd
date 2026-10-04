class_name StreamedRoom
extends Node3D
## A room whose contents live in their own scene (`room_scene`). In the game,
## RoomVisibility checks `bounds` on the server and tells only the owning peer
## to build the interior. A dedicated server never builds client-only geometry.
##
## Only put static or client-side cosmetic nodes in a room scene: it doesn't exist on
## every peer, so spawners, synchronizers and RPCs inside it would break. Keep doors
## (RoomDoor) and arrival markers as children of this node, outside the room scene,
## so their paths match everywhere.

## Persistent actors can attach cosmetic model lifetime to room presentation.
signal content_changed(loaded: bool)

const CONTENT_NAME := &"Content"

@export_file("*.tscn") var room_scene: String
## The room's extent, in this node's local space.
@export var bounds := AABB(Vector3(-5, -1, -5), Vector3(10, 5, 10))
## Optional scenery extent for camera clipping; room membership still uses bounds.
@export var render_bounds := AABB()
## Extra distance a loaded room keeps its contents for, so walking along the edge
## doesn't rebuild it every frame.
@export var unload_margin := 2.0

var _content: Node3D
var _hold_until_msec := 0


## Find an owning room without crossing server/client MultiplayerAPI branches.
static func for_position(caller: Node, point: Vector3) -> StreamedRoom:
	for node: Node in caller.get_tree().get_nodes_in_group(&"streamed_rooms"):
		var room := node as StreamedRoom
		if room.get_multiplayer() == caller.get_multiplayer() and room.contains(point):
			return room
	return null


func _enter_tree() -> void:
	# The GPS (features/gps) treats every streamed room as a region reached by doors.
	add_to_group(&"streamed_rooms")


## `bounds` in world space.
func global_bounds() -> AABB:
	return global_transform * bounds


func global_render_bounds() -> AABB:
	return (
		global_transform
		* (bounds.merge(render_bounds) if render_bounds.size != Vector3.ZERO else bounds)
	)


func _physics_process(_delta: float) -> void:
	# In the game, the server sends the current room through RoomVisibility.
	# Standalone room previews keep the local fallback for editor/tests.
	if get_tree().get_first_node_in_group(&"room_visibility") != null:
		set_physics_process(false)
		return
	var player := get_tree().get_first_node_in_group(&"local_player") as Node3D
	if player != null and contains(player.global_position, unload_margin if is_loaded() else 0.0):
		load_room()
	elif Time.get_ticks_msec() >= _hold_until_msec:
		unload_room()


func contains(global_point: Vector3, margin: float = 0.0) -> bool:
	return bounds.grow(margin).has_point(to_local(global_point))


func is_loaded() -> bool:
	return _content != null


## Builds the room's contents now. Doors call this just before asking the server to
## teleport, with `hold_msec` keeping it built until the teleport arrives, so the
## floor is already there on arrival.
func load_room(hold_msec: int = 0) -> void:
	_hold_until_msec = maxi(_hold_until_msec, Time.get_ticks_msec() + hold_msec)
	if _content != null:
		return
	var scene := load(room_scene) as PackedScene
	if scene == null:
		push_error("StreamedRoom %s: can't load %s" % [name, room_scene])
		return
	_content = scene.instantiate() as Node3D
	_content.name = CONTENT_NAME
	add_child(_content)
	content_changed.emit(true)


func unload_room() -> void:
	if _content == null:
		return
	remove_child(_content)
	_content.queue_free()
	_content = null
	content_changed.emit(false)


## Room assignment may still describe the departure room while a teleport is in flight.
func arrival_held() -> bool:
	return is_loaded() and Time.get_ticks_msec() < _hold_until_msec


## Once the server confirms this room, the next departure can unload it immediately.
func confirm_arrival() -> void:
	_hold_until_msec = 0
