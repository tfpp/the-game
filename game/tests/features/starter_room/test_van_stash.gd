extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const REAL_TIME := preload("res://tests/fixtures/real_time.gd")
var _accounts: Dictionary
var _records: Dictionary = {}
var _fail_save := false
var _lose_response := false
var _unreachable := false
var _store: InventoryPersistence
var _roots: Array[Node] = []
var _peers: Array[ENetMultiplayerPeer] = []


func before_each() -> void:
	_accounts = Network.peer_accounts.duplicate(true)
	_records.clear()
	_fail_save = false
	_lose_response = false
	_unreachable = false
	_store = InventoryPersistence.new()
	_store.transport = _api
	_store.offline_path = "user://test-van-stash.json"
	_store.set_process(false)
	add_child_autofree(_store)


func after_each() -> void:
	for root: Node in _roots:
		var path := root.get_path()
		root.free()
		get_tree().set_multiplayer(null, path)
	for peer: ENetMultiplayerPeer in _peers:
		peer.close()
	_roots.clear()
	_peers.clear()
	Network.peer_accounts = _accounts
	DirAccess.remove_absolute(_store.offline_path)
	DirAccess.remove_absolute(_store.offline_path + ".tmp")


func _api(payload: Dictionary) -> Dictionary:
	await get_tree().process_frame
	if _unreachable:
		return {"error": "unreachable"}
	var account: int = payload["account_id"]
	if payload["action"] == "load":
		return {"inventory": _records.get(account)}
	if _fail_save:
		return {"error": "failed"}
	_records[account] = JSON.parse_string(JSON.stringify(payload["inventory"]))
	return {"error": "lost response"} if _lose_response else {"saved": true}


func _feature(parent: Node) -> VanStash:
	var feature := FEATURE.instantiate() as Node3D
	feature.name = "StarterRoom"
	parent.add_child(feature)
	(feature.get_node("Room") as StreamedRoom).set_physics_process(false)
	(feature.get_node("TravelPanel") as VanTravelPanel).set_process(false)
	(feature.get_node("Room/WorkshopLift") as WorkshopLift).set_physics_process(false)
	return feature.get_node("Room/Van/Stash") as VanStash


func _hand(parent: Node, peer: int, track := true) -> Hand:
	var hand := HAND.instantiate() as Hand
	hand.name = "Hand" + str(peer)
	hand.peer_id = peer
	parent.add_child(hand)
	hand.set_process(false)
	if track:
		_store._track(hand)
	return hand


func _player(parent: Node, peer: int, at: Vector3) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	player.get_node("Sync").free()
	parent.add_child(player)
	player.set_physics_process(false)
	player.net_position = at
	return player


func _offline() -> VanStash:
	var root := Node3D.new()
	add_child_autofree(root)
	return _feature(root)


func _payload(deposit: bool, index: int, id: String) -> Dictionary:
	return {"deposit": deposit, "index": index, "id": id}


func test_private_transfers_require_open_doors_range_capacity_and_expected_item() -> void:
	Network.peer_accounts[1] = {"account_id": 101}
	var stash := _offline()
	var hand := _hand(stash.get_parent().get_parent().get_parent(), 1)
	var inventory := hand.inventory()
	await wait_process_frames(3)
	var player := _player(hand.get_parent(), 1, stash.to_global(Vector3(0, 0, -1)))
	inventory._set_item(0, "banana")
	var deposit := _payload(true, 0, "banana")
	assert_false(stash._validate_transfer(1, deposit), "Closed cargo doors block access")
	(stash.van.get_node("Model/RearLeftDoor") as OperationsVanDoor).net_open = true
	assert_false(
		stash._validate_transfer(1, {"peer": 2, "deposit": true, "index": 0, "id": "banana"})
	)
	assert_false(stash._validate_transfer(1, _payload(true, 0, "pistol")), "Stale item cannot move")
	player.net_position += Vector3(5, 0, 0)
	assert_false(stash._validate_transfer(1, deposit))
	player.net_position = stash.to_global(Vector3(0, 0, -1))
	assert_true(stash._validate_transfer(1, deposit))
	assert_true(stash._transfer(1, deposit))
	assert_true(inventory.loading, "Locks inventory before asynchronous commit")
	assert_false(inventory.collect_into_slot("pistol", 1))
	await wait_process_frames(20)
	assert_eq(inventory.backpack[0], "")
	assert_eq(inventory.van_stash, PackedStringArray(["banana"]))
	assert_eq(_records[101]["van_stash"], ["banana"], "Acknowledged transfer is durable")
	assert_eq(_records[101]["backpack"][0], "", "Carried and stored items commit together")
	assert_true(stash._validate_transfer(1, _payload(false, 0, "banana")))
	stash._transfer(1, _payload(false, 0, "banana"))
	await wait_process_frames(20)
	assert_eq(inventory.backpack[0], "banana")
	assert_true(inventory.van_stash.is_empty())
	for _index: int in 24:
		inventory.van_stash.append("banana")
	assert_false(stash._validate_transfer(1, deposit), "24 items is the hard limit")
	inventory.van_stash.remove_at(23)
	assert_true(stash._validate_transfer(1, deposit), "The 24th item fits")
	stash._transfer(1, deposit)
	await wait_process_frames(20)
	assert_eq(inventory.van_stash.size(), 24)
	inventory.backpack.fill("pistol")
	assert_false(
		stash._validate_transfer(1, _payload(false, 0, "banana")), "Full bag refuses withdrawal"
	)
	stash.van.workshop_lift.net_height = 1
	assert_false(stash.can_use(player), "Raised van blocks storage transfers")


func test_failed_and_lost_save_responses_do_not_duplicate_items_and_restart_restores_stash(
) -> void:
	Network.peer_accounts[1] = {"account_id": 102}
	var stash := _offline()
	var parent := stash.get_parent().get_parent().get_parent()
	var hand := _hand(parent, 1)
	await wait_process_frames(3)
	(stash.van.get_node("Model/RearLeftDoor") as OperationsVanDoor).net_open = true
	_player(parent, 1, stash.to_global(Vector3(0, 0, -1)))
	hand.inventory()._set_item(0, "pistol")
	_fail_save = true
	stash._transfer(1, _payload(true, 0, "pistol"))
	await wait_process_frames(20)
	assert_eq(hand.inventory().backpack[0], "pistol")
	assert_true(hand.inventory().van_stash.is_empty())
	assert_false(hand.inventory().loading)
	_fail_save = false
	_lose_response = true
	stash._transfer(1, _payload(true, 0, "pistol"))
	await wait_process_frames(20)
	assert_eq(
		hand.inventory().backpack[0], "", "Readback resolves a successful write with lost response"
	)
	assert_eq(hand.inventory().van_stash, PackedStringArray(["pistol"]))
	hand.free()
	var next := _hand(parent, 1)
	await wait_process_frames(3)
	assert_eq(next.inventory().van_stash, PackedStringArray(["pistol"]))
	assert_eq(next.inventory().backpack[0], "")
	_unreachable = true
	stash._transfer(1, _payload(false, 0, "pistol"))
	await wait_process_frames(20)
	assert_true(next.inventory().loading, "Uncertain writes stay locked until reconnect")
	assert_eq(next.inventory().backpack[0], "")
	assert_false(_store.can_commit(next))
	_unreachable = false


func test_offline_atomic_save_survives_new_persistence_and_hand_instances() -> void:
	Network.peer_accounts.erase(1)
	var stash := _offline()
	var parent := stash.get_parent().get_parent().get_parent()
	var hand := _hand(parent, 1)
	hand.inventory()._set_item(-1, "banana")
	stash._transfer(1, _payload(true, -1, "banana"))
	await wait_process_frames(20)
	assert_true(FileAccess.file_exists(_store.offline_path))
	assert_false(FileAccess.file_exists(_store.offline_path + ".tmp"))
	hand.free()
	_store._reset(Network.Mode.OFFLINE)
	var next := _hand(parent, 1)
	assert_eq(next.inventory().van_stash, PackedStringArray(["banana"]))
	assert_eq(next.net_item_id, "", "Local reload does not duplicate deposited hand item")
	next.inventory().restore({"van_stash": ["invalid", "upper_study_key", "pistol"]})
	assert_eq(
		next.inventory().van_stash,
		PackedStringArray(["pistol"]),
		"Invalid and key IDs are rejected"
	)


func _branch(title: String, peer: ENetMultiplayerPeer) -> VanStash:
	var root := Node3D.new()
	root.name = title
	add_child(root)
	_roots.append(root)
	_peers.append(peer)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	get_tree().set_multiplayer(api, root.get_path())
	return _feature(root)


func test_real_peers_receive_only_their_own_stash_and_late_join_has_no_private_snapshot() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	assert_eq(server_peer.create_server(0), OK)
	var server := _branch("StashServer", server_peer)
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var client := _branch("StashClient", client_peer)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 1, 5
		)
	)
	var id := client_peer.get_unique_id()
	Network.peer_accounts[id] = {"account_id": 103}
	_records[103] = {"van_stash": ["pistol"]}
	var server_root := server.get_parent().get_parent().get_parent()
	var hand := _hand(server_root, id)
	_hand(client.get_parent().get_parent().get_parent(), id, false)
	_player(server_root, id, server.to_global(Vector3(0, 0, -1)))
	(server.van.get_node("Model/RearLeftDoor") as OperationsVanDoor).net_open = true
	assert_eq(server.entity._evaluate(id, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	assert_eq(client.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	await REAL_TIME.wait_until(get_tree(), func() -> bool: return not hand.inventory().loading, 5)
	client.entity.request_use()
	assert_true(await REAL_TIME.wait_until(get_tree(), func() -> bool: return client.loaded, 5))
	assert_eq(client.contents, PackedStringArray(["pistol"]))
	var late_peer := ENetMultiplayerPeer.new()
	assert_eq(late_peer.create_client("127.0.0.1", server_peer.host.get_local_port()), OK)
	var late := _branch("StashLate", late_peer)
	_hand(late.get_parent().get_parent().get_parent(), id, false)
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(), func() -> bool: return server.multiplayer.get_peers().size() == 2, 5
		)
	)
	var late_id := late_peer.get_unique_id()
	Network.peer_accounts[late_id] = {"account_id": 104}
	_records[104] = {"van_stash": ["banana"]}
	var late_hand := _hand(server_root, late_id)
	_hand(client.get_parent().get_parent().get_parent(), late_id, false)
	_hand(late.get_parent().get_parent().get_parent(), late_id, false)
	_player(server_root, late_id, server.to_global(Vector3(0, 0, -1)))
	assert_false(late.loaded)
	assert_true(late.contents.is_empty(), "Late join never receives someone else's private items")
	await REAL_TIME.wait_until(
		get_tree(), func() -> bool: return not late_hand.inventory().loading, 5
	)
	late.entity.request_use()
	assert_true(await REAL_TIME.wait_until(get_tree(), func() -> bool: return late.loaded, 5))
	assert_eq(late.contents, PackedStringArray(["banana"]))
	assert_eq(client.contents, PackedStringArray(["pistol"]), "Other owner's view stays unchanged")
	client.request_transfer(false, 0, "pistol")
	assert_true(
		await REAL_TIME.wait_until(
			get_tree(),
			func() -> bool:
				return hand.inventory().backpack[0] == "pistol" and client.contents.is_empty(),
			5
		)
	)
	assert_eq(late.contents, PackedStringArray(["banana"]))
	assert_eq(_records[103]["van_stash"], [])
	assert_eq(_records[104]["van_stash"], ["banana"])


func test_phone_layout_has_large_tap_targets_and_can_store_without_dragging() -> void:
	Network.peer_accounts[1] = {"account_id": 105}
	var stash := _offline()
	var parent := stash.get_parent().get_parent().get_parent()
	var hand := _hand(parent, 1)
	await wait_process_frames(3)
	var player := _player(parent, 1, stash.to_global(Vector3(0, 0, -1)))
	(stash.van.get_node("Model/RearLeftDoor") as OperationsVanDoor).net_open = true
	hand.inventory()._set_item(0, "banana")
	stash.loaded = true
	stash.message = "Only you can access these items."
	var screen := stash.screen
	screen.set_process(false)
	var window := get_window()
	var original_size := window.size
	window.size = Vector2i(390, 844)
	screen.call("open", stash)
	await wait_process_frames(3)
	var buttons: Array = screen.get("_carried")
	var button := buttons[0] as Button
	assert_eq((button.get_parent() as GridContainer).columns, 2)
	assert_gte(button.size.y, 48.0)
	assert_gte(button.size.x, 48.0)
	assert_string_contains(button.text, "BAG 1")
	assert_string_contains(button.text, "Banana")
	var root := screen.get("_root") as Control
	assert_almost_eq(root.size.x, 390.0, 1.0)
	var close_button := root.find_children("*", "Button", true, false).back() as Button
	assert_lte(
		close_button.global_position.y + close_button.size.y,
		root.size.y,
		"Back button stays visible outside item scroll"
	)
	button.pressed.emit()
	await wait_process_frames(20)
	assert_true(hand.inventory().backpack[0].is_empty())
	assert_eq(hand.inventory().van_stash, PackedStringArray(["banana"]))
	assert_true(stash.can_use(player))
	screen.call("close")
	window.size = original_size


func test_disconnect_during_a_transfer_loads_the_committed_snapshot_on_reconnect() -> void:
	Network.peer_accounts[1] = {"account_id": 106}
	var stash := _offline()
	var parent := stash.get_parent().get_parent().get_parent()
	var hand := _hand(parent, 1)
	await wait_process_frames(3)
	hand.inventory()._set_item(0, "banana")
	stash._transfer(1, _payload(true, 0, "banana"))
	assert_true(hand.inventory().loading)
	hand.free()
	var next := _hand(parent, 1)
	await wait_process_frames(20)
	assert_false(next.inventory().loading)
	assert_eq(next.inventory().van_stash, PackedStringArray(["banana"]))
	assert_eq(next.inventory().backpack[0], "")
