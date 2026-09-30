class_name PlayerInventory
extends Node
## Lives on each server-spawned Hand. Only the owner may request mutations.
## Eight backpack slots plus hand, shirt, pants and hat. New players own no items.

const CAPACITY := 8

@export var backpack := PackedStringArray(["", "", "", "", "", "", "", ""])
@export var shirt := ""
@export var pants := ""
@export var hat := ""
@export var keys := PackedStringArray()


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
		-4:
			return hat
	return backpack[slot] if slot >= 0 and slot < CAPACITY else ""


func can_collect(id: String) -> bool:
	var definition := ItemCatalog.find(id)
	if definition != null and definition.category == ItemDefinition.Category.KEY:
		return not has_key(id)
	return (
		ItemCatalog.find(id) != null
		and (item_at(_equipment_slot(id)).is_empty() or backpack.has(""))
	)


func collect(id: String) -> bool:
	if not multiplayer.is_server() or not can_collect(id):
		return false
	if ItemCatalog.find(id).category == ItemDefinition.Category.KEY:
		var next := keys.duplicate()
		next.append(id)
		keys = next
		hand()._play_inventory.rpc_id(hand().peer_id, &"key_pickup")
		return true
	var target := _equipment_slot(id)
	if not item_at(target).is_empty():
		target = backpack.find("")
	_set_item(target, id)
	if target == -1:
		_holster_gun_rig_if_weapon(id)
	hand()._play_inventory.rpc_id(hand().peer_id, &"pickup")
	return true


## Server-only transfer into a chosen empty backpack slot. Stash drags use this
## so the player's drop target, rather than the automatic equipment slot, wins.
func collect_into_slot(id: String, slot: int) -> bool:
	if not multiplayer.is_server() or slot < 0 or slot >= CAPACITY:
		return false
	var definition := ItemCatalog.find(id)
	if definition == null or definition.category == ItemDefinition.Category.KEY:
		return false
	if not backpack[slot].is_empty():
		return false
	_set_item(slot, id)
	hand()._play_inventory.rpc_id(hand().peer_id, &"pickup")
	return true


func has_key(id: String) -> bool:
	return not id.is_empty() and keys.has(id)


## Server-only: reserves one sellable item before an asynchronous wallet sale.
## Keeping it out of the inventory prevents a player from dropping or selling it
## twice while the accounts API is resolving the operation.
func take_first_valuable() -> String:
	if not multiplayer.is_server():
		return ""
	for slot: int in [-1, 0, 1, 2, 3, 4, 5, 6, 7]:
		var id := item_at(slot)
		var def := ItemCatalog.find(id)
		if def != null and def.sale_value_cents > 0:
			_set_item(slot, "")
			return id
	return ""


## Server-only: valuables are left where a slum player was killed, available
## for the killer or any other survivor to collect. Clothing, weapons and keys
## remain with the player after respawn.
func drop_valuables(at: Vector3) -> int:
	if not multiplayer.is_server():
		return 0
	var holdables := get_tree().get_first_node_in_group(&"holdables_root")
	if holdables == null:
		return 0
	var count := 0
	while true:
		var id := take_first_valuable()
		if id.is_empty():
			break
		var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
		holdables.call("spawn_thrown_item", id, at + Vector3.UP * 0.7, at + offset)
		count += 1
	return count


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
	if not _authorized() or slot not in [-1, -2, -3, -4]:
		return
	var empty := backpack.find("")
	if empty == -1 or item_at(slot).is_empty():
		return
	_set_item(empty, item_at(slot))
	_set_item(slot, "")
	hand()._play_inventory.rpc_id(hand().peer_id, &"equip")


@rpc("any_peer", "call_local", "reliable")
func request_drop(slot: int) -> void:
	if not _authorized() or slot < -4 or slot >= CAPACITY:
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
	if hand().consumption.active():
		return false
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
		"hat":
			return -4
	return -1


func _set_item(slot: int, id: String) -> void:
	match slot:
		-1:
			hand().net_item_id = id
		-2:
			shirt = id
		-3:
			pants = id
		-4:
			hat = id
		_:
			var next := backpack.duplicate()
			next[slot] = id
			backpack = next
