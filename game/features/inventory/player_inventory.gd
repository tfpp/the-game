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

## Server-only: true while features/inventory/inventory_persistence.gd loads this
## player's saved items, so nothing can change until they are merged in.
var loading := false


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
	if loading:
		return false
	if not ItemCatalog.ammo_weapon(id).is_empty():
		return backpack.has("")
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
	var target := (
		backpack.find("") if not ItemCatalog.ammo_weapon(id).is_empty() else _equipment_slot(id)
	)
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


## Read-only count for the HUD. Packs in the backpack feed the held stock gun.
func ammo_for(weapon: String) -> int:
	var rounds := 0
	for id: String in backpack:
		if ItemCatalog.ammo_weapon(id) == weapon:
			rounds += ItemCatalog.ammo_rounds(id)
	return rounds


## Server-only: spend one round per trigger, including a shotgun's whole pellet burst.
func spend_ammo(weapon: String) -> bool:
	if not multiplayer.is_server() or loading or hand().consumption.active():
		return false
	for slot: int in CAPACITY:
		var id := backpack[slot]
		if ItemCatalog.ammo_weapon(id) == weapon:
			_set_item(slot, ItemCatalog.ammo_id(weapon, ItemCatalog.ammo_rounds(id) - 1))
			return true
	return false


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
	return drop_valuable_ids(at).size()


## Server-only: like `drop_valuables`, but returns the dropped item ids so the
## death message can name them.
func drop_valuable_ids(at: Vector3) -> Array[String]:
	var dropped: Array[String] = []
	if not multiplayer.is_server():
		return dropped
	var holdables := get_tree().get_first_node_in_group(&"holdables_root")
	if holdables == null:
		return dropped
	while true:
		var id := take_first_valuable()
		if id.is_empty():
			break
		var offset := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
		holdables.call("spawn_thrown_item", id, at + Vector3.UP * 0.7, at + offset)
		dropped.append(id)
	return dropped


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
	if loading:
		return false
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


## Everything this player carries, as plain strings for the accounts database.
func snapshot() -> Dictionary:
	return {
		"hand": hand().net_item_id,
		"shirt": shirt,
		"pants": pants,
		"hat": hat,
		"backpack": Array(backpack),
		"keys": Array(keys),
	}


## Server-only: merges a saved snapshot into this inventory. Unknown or misplaced
## IDs are skipped. A saved item whose slot is already taken moves to a free
## backpack slot, or is dropped at the player if the backpack is full.
func restore(saved: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	for id: Variant in _array(saved.get("keys")):
		var definition := ItemCatalog.find(str(id))
		if definition != null and definition.category == ItemDefinition.Category.KEY:
			if not has_key(str(id)):
				var next := keys.duplicate()
				next.append(str(id))
				keys = next
	# Backpack slots first, so displaced equipment never takes a saved slot.
	var wanted := {}
	var bag := _array(saved.get("backpack"))
	for slot: int in CAPACITY:
		wanted[slot] = bag[slot] if slot < bag.size() else ""
	wanted[-1] = saved.get("hand")
	wanted[-2] = saved.get("shirt")
	wanted[-3] = saved.get("pants")
	wanted[-4] = saved.get("hat")
	for slot: int in wanted:
		var id := str(wanted[slot]) if wanted[slot] is String else ""
		if not _restorable(id, slot):
			continue
		if item_at(slot).is_empty():
			_set_item(slot, id)
			if slot == -1:
				_holster_gun_rig_if_weapon(id)
		elif backpack.has(""):
			_set_item(backpack.find(""), id)
		else:
			hand().drop_inventory_item(id)


## Server-only: throws away the held item and every backpack item, for
## features/inventory/garbage_can.gd. Worn clothes and keys stay. Returns the count.
func clear_carried() -> int:
	if not multiplayer.is_server() or loading or hand().consumption.active():
		return 0
	var count := 0
	for slot: int in [-1, 0, 1, 2, 3, 4, 5, 6, 7]:
		if not item_at(slot).is_empty():
			_set_item(slot, "")
			count += 1
	return count


func _restorable(id: String, slot: int) -> bool:
	var definition := ItemCatalog.find(id)
	if definition == null or definition.category == ItemDefinition.Category.KEY:
		return false
	return slot >= 0 or _equipment_slot(id) == slot


static func _array(value: Variant) -> Array:
	return value if value is Array else []
