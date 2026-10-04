class_name VanStash
extends Node3D
## Owner-only rear storage. Contents stay in server inventory, never shared state.

signal contents_changed
const CAPACITY := PlayerInventory.VAN_STASH_CAPACITY
var contents := PackedStringArray()
var message := ""
var loaded := false
var _generation := 0
@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var van: OperationsVan = get_parent()
@onready var screen: CanvasLayer = get_node("../../../StashScreen")


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _open)
	entity.register_action(&"transfer", _validate_transfer, _transfer, .15)
	entity.event_received.connect(_event)
	entity.request_finished.connect(_result)
	entity.session_reset.connect(_reset)


func interaction_text() -> String:
	return "Van · private stash (24 items)"


func can_use(player: Player) -> bool:
	if (
		not entity.in_range(player)
		or (van.workshop_lift != null and not van.workshop_lift.grounded())
	):
		return false
	var left := van.get_node("Model/RearLeftDoor") as OperationsVanDoor
	var right := van.get_node("Model/RearRightDoor") as OperationsVanDoor
	return left.net_open or right.net_open


func use() -> void:
	loaded = false
	contents = PackedStringArray()
	message = "Loading your stash…"
	screen.call("open", self)
	entity.request_use()


func _persistence() -> InventoryPersistence:
	return get_tree().get_first_node_in_group(&"inventory_persistence") as InventoryPersistence


func _open(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var hand := Hand.for_peer(get_tree(), peer)
	var store := _persistence()
	if hand == null or store == null or hand.inventory().loading:
		entity.send_event(&"status", {"message": "Inventory is loading. Try again shortly."}, peer)
		return false
	if not store.can_commit(hand):
		entity.send_event(
			&"status", {"message": "Saved stash unavailable. Sign in or try again later."}, peer
		)
		return false
	_publish(peer, hand.inventory())
	return true


func request_transfer(deposit: bool, index: int, expected_id: String) -> void:
	entity.request_action(&"transfer", {"deposit": deposit, "index": index, "id": expected_id})


func _validate_transfer(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 3 or not payload.has_all(["deposit", "index", "id"]):
		return false
	if not payload["deposit"] is bool or not payload["index"] is int or not payload["id"] is String:
		return false
	var hand := Hand.for_peer(get_tree(), peer)
	var store := _persistence()
	if (
		hand == null
		or store == null
		or not store.can_commit(hand)
		or not can_use(entity.player_for_peer(peer))
	):
		return false
	var inventory := hand.inventory()
	if inventory.loading or hand.consumption.active() or str(payload["id"]).is_empty():
		return false
	var index: int = payload["index"]
	var id: String = payload["id"]
	if payload["deposit"]:
		return (
			index >= -4
			and index < PlayerInventory.CAPACITY
			and inventory.item_at(index) == id
			and inventory.van_stash.size() < CAPACITY
		)
	return (
		index >= 0
		and index < inventory.van_stash.size()
		and inventory.van_stash[index] == id
		and inventory.backpack.has("")
	)


func _transfer(peer: int, payload: Dictionary) -> bool:
	var hand := Hand.for_peer(get_tree(), peer)
	hand.inventory().loading = true
	_settle(peer, payload, hand, _generation)
	return true


func _settle(peer: int, payload: Dictionary, hand: Hand, generation: int) -> void:
	if not is_instance_valid(hand) or generation != _generation:
		return
	var inventory := hand.inventory()
	var candidate := inventory.snapshot()
	var bag: Array = candidate["backpack"]
	var stash: Array = candidate["van_stash"]
	var index: int = payload["index"]
	var id: String = payload["id"]
	var slot := index if payload["deposit"] else inventory.backpack.find("")
	if payload["deposit"]:
		stash.append(id)
		if slot < 0:
			candidate[["hand", "shirt", "pants", "hat"][-slot - 1]] = ""
		else:
			bag[slot] = ""
	else:
		stash.remove_at(index)
		bag[slot] = id
	inventory.loading = true
	entity.send_event(&"status", {"message": "Saving transfer…"}, peer)
	var store := _persistence()
	var saved := await store.commit_inventory(hand, candidate)
	if not is_instance_valid(hand) or not hand.is_inside_tree() or generation != _generation:
		return
	if saved:
		inventory._set_item(slot, "" if payload["deposit"] else id)
		inventory.van_stash = PackedStringArray(stash)
	inventory.loading = not store.can_commit(hand)
	_publish(
		peer,
		inventory,
		(
			"Saved."
			if saved
			else (
				"Save unavailable. Reconnect before moving items."
				if inventory.loading
				else "Save failed. Items have not moved; try again."
			)
		)
	)


func _publish(
	peer: int, inventory: PlayerInventory, text: String = "Only you can access these items."
) -> void:
	entity.send_event(&"contents", {"items": Array(inventory.van_stash), "message": text}, peer)


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"contents":
		contents = PackedStringArray(payload.get("items", []))
		loaded = true
	if event in [&"contents", &"status"]:
		message = str(payload.get("message", ""))
		contents_changed.emit()


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	contents = PackedStringArray()
	loaded = false
	message = ""
	screen.call("close", false)


func _result(_action: StringName, result: NetworkedEntity.Result) -> void:
	if (
		result != NetworkedEntity.Result.ACCEPTED
		and message in ["Saving transfer…", "Loading your stash…"]
	):
		message = "Transfer unavailable. Check free slots and try again."
		contents_changed.emit()
