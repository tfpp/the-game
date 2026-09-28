class_name PlayerInventory
extends Node
## Lives on each server-spawned Hand. Only the owner may request mutations.
## Eight backpack slots plus hand, shirt and pants. New players own no items.

const CAPACITY := 8

@export var backpack := PackedStringArray(["", "", "", "", "", "", "", ""])
@export var shirt := ""
@export var pants := ""


func hand() -> Hand:
	return get_parent() as Hand


func item_at(slot: int) -> String:
	match slot:
		-1:
			return hand().net_item_id
		-2:
			return shirt
		-3:
			return pants
	return backpack[slot] if slot >= 0 and slot < CAPACITY else ""


func can_collect(id: String) -> bool:
	return (
		ItemCatalog.find(id) != null
		and (item_at(_equipment_slot(id)).is_empty() or backpack.has(""))
	)


func collect(id: String) -> bool:
	if not multiplayer.is_server() or not can_collect(id):
		return false
	var target := _equipment_slot(id)
	if not item_at(target).is_empty():
		target = backpack.find("")
	_set_item(target, id)
	if target == -1:
		_holster_gun_rig_if_weapon(id)
	hand()._play_inventory.rpc_id(hand().peer_id, &"pickup")
	return true


@rpc("any_peer", "call_local", "reliable")
func request_equip(index: int) -> void:
	if not _authorized() or index < 0 or index >= CAPACITY:
		return
	var id := backpack[index]
	if ItemCatalog.find(id) == null:
		return
	var target := _equipment_slot(id)
	var previous := item_at(target)
	_set_item(target, id)
	_set_item(index, previous)
	if target == -1:
		_holster_gun_rig_if_weapon(id)
	hand()._play_inventory.rpc_id(hand().peer_id, &"equip")


@rpc("any_peer", "call_local", "reliable")
func request_stow(slot: int) -> void:
	if not _authorized() or slot not in [-1, -2, -3]:
		return
	var empty := backpack.find("")
	if empty == -1 or item_at(slot).is_empty():
		return
	_set_item(empty, item_at(slot))
	_set_item(slot, "")
	hand()._play_inventory.rpc_id(hand().peer_id, &"equip")


@rpc("any_peer", "call_local", "reliable")
func request_drop(slot: int) -> void:
	if not _authorized() or slot < -3 or slot >= CAPACITY:
		return
	var id := item_at(slot)
	if id.is_empty() or not hand().drop_inventory_item(id):
		return
	_set_item(slot, "")
	hand()._play_inventory.rpc_id(hand().peer_id, &"drop")


## Server-only: moves whatever weapon is currently held out of the hand and into an
## empty backpack slot, dropping it instead if the backpack is full. Called by
## features/gun_machine's GunRig before it takes over the hand, so a rig gun and a
## holdable weapon can never both be equipped at once (see also
## `_holster_gun_rig_if_weapon`, which does the reverse).
func holster_weapon() -> void:
	if not multiplayer.is_server():
		return
	var id := hand().net_item_id
	var def := ItemCatalog.find(id)
	if def == null or def.category != ItemDefinition.Category.WEAPON:
		return
	var empty := backpack.find("")
	if empty != -1:
		_set_item(empty, id)
	else:
		hand().drop_inventory_item(id)
	_set_item(-1, "")


## Server-only: if `id` is a weapon that just moved into the hand, holsters the gun
## machine's rig (features/gun_machine) for the same peer so it can't stay equipped
## alongside a holdable weapon.
func _holster_gun_rig_if_weapon(id: String) -> void:
	var def := ItemCatalog.find(id)
	if def == null or def.category != ItemDefinition.Category.WEAPON:
		return
	var rig := GunRig.for_peer(get_tree(), hand().peer_id)
	if rig != null:
		rig.holster()


func _authorized() -> bool:
	if not multiplayer.is_server():
		return false
	var sender := multiplayer.get_remote_sender_id()
	return (sender if sender != 0 else multiplayer.get_unique_id()) == hand().peer_id


func _equipment_slot(id: String) -> int:
	match ClothingCatalog.slot(id):
		"shirt":
			return -2
		"pants":
			return -3
	return -1


func _set_item(slot: int, id: String) -> void:
	match slot:
		-1:
			hand().net_item_id = id
		-2:
			shirt = id
		-3:
			pants = id
		_:
			var next := backpack.duplicate()
			next[slot] = id
			backpack = next
