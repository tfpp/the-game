class_name ZoneRegistry
extends RefCounted
## Pure bookkeeping for slum zone instances: which peers form each group, which slum
## arrival it uses and which far-apart world slot it occupies. A peer belongs to at
## most one instance; an instance is freed when its last member leaves.

signal instance_created(instance_id: int)
signal instance_freed(instance_id: int)
signal membership_changed(instance_id: int)

## Distance between instance slots along +X. Slot 0 is the slum's authored position.
const OFFSET_STEP_M := 4000.0

var _next_id: int = 1
## instance id -> {"members": Dictionary[int, bool], "arrival": Node3D, "slot": int}
var _instances: Dictionary = {}
var _peer_instance: Dictionary = {}


## Creates an instance for `peers` (moved out of any instance they were in) and
## returns its id, or -1 when there is nobody to send.
func create(peers: Array[int], arrival: Node3D) -> int:
	if peers.is_empty():
		return -1
	for peer_id: int in peers:
		leave(peer_id)
	var instance_id := _next_id
	_next_id += 1
	_instances[instance_id] = {"members": {}, "arrival": arrival, "slot": _free_slot()}
	for peer_id: int in peers:
		_add(instance_id, peer_id)
	instance_created.emit(instance_id)
	return instance_id


## Adds a peer to an existing instance. Returns false if the instance is gone.
func join(instance_id: int, peer_id: int) -> bool:
	if not _instances.has(instance_id):
		return false
	if instance_of(peer_id) == instance_id:
		return true
	leave(peer_id)
	_add(instance_id, peer_id)
	return true


## Removes a peer from its instance, freeing the instance if it was the last member.
func leave(peer_id: int) -> void:
	var instance_id := instance_of(peer_id)
	if instance_id == -1:
		return
	_peer_instance.erase(peer_id)
	var group: Dictionary = _instances[instance_id]["members"]
	group.erase(peer_id)
	if group.is_empty():
		_instances.erase(instance_id)
		instance_freed.emit(instance_id)
	else:
		membership_changed.emit(instance_id)


func clear() -> void:
	var ids := _instances.keys()
	_instances.clear()
	_peer_instance.clear()
	for instance_id: int in ids:
		instance_freed.emit(instance_id)


func instance_of(peer_id: int) -> int:
	return int(_peer_instance.get(peer_id, -1))


func has_instance(instance_id: int) -> bool:
	return _instances.has(instance_id)


func instance_ids() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_instances.keys())
	return ids


func members(instance_id: int) -> Array[int]:
	var result: Array[int] = []
	if _instances.has(instance_id):
		result.assign((_instances[instance_id]["members"] as Dictionary).keys())
	return result


func arrival_of(instance_id: int) -> Node3D:
	if not _instances.has(instance_id):
		return null
	return _instances[instance_id]["arrival"] as Node3D


func slot_of(instance_id: int) -> int:
	if not _instances.has(instance_id):
		return -1
	return int(_instances[instance_id]["slot"])


## World offset of the instance's copy of its slum, relative to the authored scene.
func offset_of(instance_id: int) -> Vector3:
	return offset_for_slot(maxi(slot_of(instance_id), 0))


static func offset_for_slot(slot: int) -> Vector3:
	return Vector3(OFFSET_STEP_M * slot, 0.0, 0.0)


func _add(instance_id: int, peer_id: int) -> void:
	(_instances[instance_id]["members"] as Dictionary)[peer_id] = true
	_peer_instance[peer_id] = instance_id
	membership_changed.emit(instance_id)


## Lowest slot not used by a live instance, so freed slots are reused.
func _free_slot() -> int:
	var used := {}
	for data: Dictionary in _instances.values():
		used[int(data["slot"])] = true
	var slot := 0
	while used.has(slot):
		slot += 1
	return slot
