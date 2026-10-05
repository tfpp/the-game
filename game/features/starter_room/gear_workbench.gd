class_name GearWorkbench
extends Node3D
## Authenticated owner-only recipes, using the inventory's existing atomic store.

signal changed
var items: Array = []
var materials: Dictionary = {}
var message := ""
var busy := false
var _generation := 0
@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var screen: CanvasLayer = get_node("../../WorkbenchScreen")


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _open)
	entity.register_action(&"upgrade", _validate, _upgrade, .2)
	entity.event_received.connect(_event)
	entity.request_finished.connect(_result)
	entity.session_reset.connect(_reset)


func interaction_text() -> String:
	return "Workbench · salvage upgrades"


func can_use(player: Player) -> bool:
	return entity.in_range(player)


func use() -> void:
	items = []
	materials = {}
	busy = true
	message = "Loading your gear…"
	screen.call("open", self)
	entity.request_use()


func store() -> InventoryPersistence:
	return get_tree().get_first_node_in_group(&"inventory_persistence") as InventoryPersistence


func _open(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var hand := Hand.for_peer(get_tree(), peer)
	if hand == null or hand.inventory().loading or store() == null or not store().can_commit(hand):
		entity.send_event(
			&"status", {"message": "Saved inventory unavailable. Try again shortly."}, peer
		)
		return false
	_publish(peer, hand.inventory(), "Use carried scrap and electronics to tune a stock weapon.")
	return true


func request_upgrade(slot: int, id: String) -> void:
	busy = true
	message = "Saving upgrade…"
	changed.emit()
	entity.request_action(&"upgrade", {"slot": slot, "id": id})


func _validate(peer: int, payload: Dictionary) -> bool:
	if payload.size() != 2 or not payload.get("slot") is int or not payload.get("id") is String:
		return false
	var hand := Hand.for_peer(get_tree(), peer)
	return (
		hand != null
		and store() != null
		and store().can_commit(hand)
		and not hand.inventory().loading
		and not hand.consumption.active()
		and can_use(entity.player_for_peer(peer))
		and not (
			WorkbenchRecipes
			. candidate(hand.inventory().snapshot(), payload["slot"], payload["id"])
			. is_empty()
		)
	)


func _upgrade(peer: int, payload: Dictionary) -> bool:
	var hand := Hand.for_peer(get_tree(), peer)
	hand.inventory().loading = true
	_settle(hand, peer, payload, _generation)
	return true


func _settle(hand: Hand, peer: int, payload: Dictionary, generation: int) -> void:
	var inventory := hand.inventory()
	var next := WorkbenchRecipes.candidate(inventory.snapshot(), payload["slot"], payload["id"])
	var persistence := store()
	var saved := not next.is_empty() and await persistence.commit_inventory(hand, next)
	if not is_instance_valid(hand) or not hand.is_inside_tree() or generation != _generation:
		return
	if saved:
		for slot: int in PlayerInventory.CAPACITY:
			inventory._set_item(slot, str(next["backpack"][slot]))
		inventory._set_item(-1, str(next["hand"]))
	inventory.loading = not persistence.can_commit(hand)
	_publish(
		peer,
		inventory,
		"Upgrade saved." if saved else "Save failed. Reconnect if inventory is locked."
	)


func _publish(peer: int, inventory: PlayerInventory, text: String) -> void:
	var gear: Array = []
	var snapshot := inventory.snapshot()
	for slot: int in range(-1, PlayerInventory.CAPACITY):
		var id := inventory.item_at(slot)
		if ItemCatalog.AMMO_PACKS.has(id) or id.begins_with("tuned:"):
			gear.append(
				{
					"slot": slot,
					"id": id,
					"available": not WorkbenchRecipes.candidate(snapshot, slot, id).is_empty()
				}
			)
	entity.send_event(
		&"gear",
		{
			"items": gear,
			"message": text,
			"materials":
			{
				"scrap": inventory.backpack.count("scrap"),
				"electronics": inventory.backpack.count("electronics")
			}
		},
		peer
	)


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"gear":
		items = payload.get("items", [])
		materials = payload.get("materials", {})
	if event in [&"gear", &"status"]:
		message = str(payload.get("message", ""))
		busy = false
		changed.emit()


func _result(_action: StringName, result: NetworkedEntity.Result) -> void:
	if result != NetworkedEntity.Result.ACCEPTED and busy:
		busy = false
		message = "Upgrade unavailable. Check materials and stay beside the workbench."
		changed.emit()


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	items = []
	busy = false
	screen.call("close", false)
