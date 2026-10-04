extends GutTest
## InventoryPersistence against a fake accounts API: load before use, ordered saves,
## a final save on disconnect, and guests/unreachable storage never overwriting data.

const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const ACCOUNT := 42

var _persistence: InventoryPersistence
var _requests: Array[Dictionary] = []
var _stored: Variant = null
var _online := true
var _saved_accounts: Dictionary


func before_each() -> void:
	_requests.clear()
	_stored = null
	_online = true
	_saved_accounts = Network.peer_accounts.duplicate()
	Network.peer_accounts[1] = {"account_id": ACCOUNT, "name": "Ivy"}
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	add_child_autofree(player)
	player.set_physics_process(false)
	_persistence = InventoryPersistence.new()
	_persistence.transport = _fake_api
	_persistence.offline_path = ""
	add_child_autofree(_persistence)


func after_each() -> void:
	Network.peer_accounts = _saved_accounts
	await get_tree().process_frame


func test_saved_items_load_into_a_new_hand_before_it_accepts_changes() -> void:
	_stored = {
		"hand": "pistol",
		"shirt": "shirt:2",
		"pants": "not-an-item",
		"backpack": ["banana", "", "cash_bundle"],
		"keys": ["upper_study_key", "banana"],
	}
	var hand := _spawn_hand()
	assert_true(hand.inventory().loading or hand.net_item_id == "pistol")
	await wait_process_frames(2)
	var inventory := hand.inventory()
	assert_false(inventory.loading)
	assert_eq(hand.net_item_id, "pistol")
	assert_eq(inventory.shirt, "shirt:2")
	assert_eq(inventory.pants, "", "Unknown IDs are skipped")
	assert_eq(inventory.backpack[0], "banana")
	assert_eq(inventory.backpack[2], "cash_bundle")
	assert_eq(inventory.keys, PackedStringArray(["upper_study_key"]), "Only real keys load")
	assert_eq(_requests[0]["action"], "load")
	assert_eq(_requests[0]["account_id"], ACCOUNT)


func test_loading_blocks_pickups_and_requests() -> void:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	hand.inventory().loading = true
	assert_false(hand.inventory().collect("banana"))
	hand.inventory().loading = false
	assert_true(hand.inventory().collect("banana"))


func test_changes_are_saved_and_survive_into_the_next_session() -> void:
	var hand := _spawn_hand()
	await wait_process_frames(2)
	assert_true(hand.inventory().collect("banana"))
	assert_true(hand.inventory().collect("shirt:4"))
	await wait_seconds(InventoryPersistence.SAVE_INTERVAL + 0.2)
	assert_eq(_requests[-1]["action"], "save")
	var saved := _stored as Dictionary
	assert_eq(saved["hand"], "banana")
	assert_eq(saved["shirt"], "shirt:4")
	var count := _requests.size()
	await wait_seconds(InventoryPersistence.SAVE_INTERVAL + 0.2)
	assert_eq(_requests.size(), count, "Unchanged inventories are not saved again")
	# A "server restart": a fresh hand for the same account loads the saved items.
	remove_child(hand)
	hand.free()
	var next := _spawn_hand()
	await wait_process_frames(2)
	assert_eq(next.net_item_id, "banana")
	assert_eq(next.inventory().shirt, "shirt:4")


func test_disconnect_saves_the_final_inventory_immediately() -> void:
	var hand := _spawn_hand()
	await wait_process_frames(2)
	hand.inventory().collect("pistol")
	remove_child(hand)
	hand.free()
	assert_eq((_stored as Dictionary)["hand"], "pistol")


func test_unreachable_storage_never_overwrites_saved_items() -> void:
	_stored = {"hand": "pistol"}
	_online = false
	var hand := _spawn_hand()
	await wait_process_frames(2)
	assert_false(hand.inventory().loading, "The session stays playable")
	_online = true
	hand.inventory().collect("banana")
	await wait_seconds(InventoryPersistence.SAVE_INTERVAL + 0.2)
	remove_child(hand)
	hand.free()
	assert_eq(_stored, {"hand": "pistol"})


func test_guests_without_an_account_use_memory_only() -> void:
	Network.peer_accounts.erase(1)
	var hand := _spawn_hand()
	await wait_process_frames(2)
	hand.inventory().collect("banana")
	await wait_seconds(InventoryPersistence.SAVE_INTERVAL + 0.2)
	assert_eq(_requests.size(), 0)


func test_restore_moves_items_whose_slot_is_taken_into_the_backpack() -> void:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	var inventory := hand.inventory()
	inventory.collect("banana")
	inventory.restore({"hand": "pistol", "backpack": ["kebab"]})
	assert_eq(hand.net_item_id, "banana")
	assert_eq(inventory.backpack[0], "kebab")
	assert_eq(inventory.backpack[1], "pistol")


func _spawn_hand() -> Hand:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = 1
	add_child_autofree(hand)
	_persistence._process(0.0)
	return hand


func _fake_api(payload: Dictionary) -> Dictionary:
	_requests.append(payload.duplicate(true))
	if not _online:
		return {"error": "offline"}
	if payload["action"] == "load":
		return {"inventory": _stored}
	_stored = JSON.parse_string(JSON.stringify(payload["inventory"]))
	return {"saved": true}
