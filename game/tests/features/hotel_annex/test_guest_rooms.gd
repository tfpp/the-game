extends GutTest

const DOOR := preload("res://features/hotel_annex/guest_door.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _door: HotelGuestDoor
var _player: Player
var _wallet: PlayerMoney


func before_each() -> void:
	_door = DOOR.instantiate()
	add_child_autofree(_door)
	_door.set_physics_process(false)
	_player = _make_player(1)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 20000, 2: 20000}


func after_each() -> void:
	Network.peer_accounts.clear()
	if is_instance_valid(_door._panel):
		_door._panel.call("close")


func _make_player(peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.display_name = "Resident %d" % peer
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = Vector3(0, 1, -1.5)
	player.position = player.net_position
	return player


func _request(operation: String, peer: int = 1, guest: int = 0) -> NetworkedEntity.Result:
	var action: NetworkedEntity.Action = _door._entity._actions[&"manage"]
	action.next_msec = 0
	var payload := {"operation": operation}
	if operation == "guest":
		payload["guest"] = guest
	return _door._entity._evaluate(peer, &"manage", payload)


func _rent() -> void:
	assert_eq(_request("rent"), NetworkedEntity.Result.ACCEPTED)
	await wait_process_frames(2)
	assert_eq(_door.occupant, "Resident 1")


func test_real_wallet_rent_reserves_once_and_expires_without_moving_leaf() -> void:
	assert_eq(_request("rent"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_request("buy"), NetworkedEntity.Result.DENIED, "Pending payment locks vacancy")
	await wait_process_frames(2)
	assert_eq(_wallet.balances[1], 19000)
	assert_eq(_door.tenure, "Rental")
	assert_true(_door.locked)
	assert_eq(_request("rent"), NetworkedEntity.Result.DENIED)
	assert_eq(_request("toggle"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_door.net_state, SwingDoor.State.OPEN_IN)
	_door._physics_process(HotelGuestDoor.RENT_SECONDS)
	assert_eq(_door.occupant, "")
	assert_false(_door.locked)
	assert_eq(_door.net_state, SwingDoor.State.OPEN_IN, "Expiry never slams a door")
	assert_eq(_wallet.balances[1], 19000)


func test_purchase_has_no_timer_and_release_has_no_refund() -> void:
	assert_eq(_request("buy"), NetworkedEntity.Result.ACCEPTED)
	await wait_process_frames(2)
	assert_eq(_wallet.balances[1], 10000)
	assert_eq(_door.tenure, "Purchased (session)")
	_door._physics_process(10000)
	assert_eq(_door.occupant, "Resident 1")
	assert_eq(_request("leave"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_door.occupant, "")
	assert_eq(_wallet.balances[1], 10000)


func test_insufficient_funds_preserve_vacancy_and_balance() -> void:
	_wallet.balances[1] = 999
	_request("rent")
	await wait_process_frames(2)
	assert_eq(_wallet.balances[1], 999)
	assert_eq(_door.occupant, "")
	assert_true(_door._pending.is_empty())


func test_lock_guest_grant_revoke_and_inside_escape_reuse_physical_swing() -> void:
	await _rent()
	var other := _make_player(2)
	assert_eq(_request("toggle", 2), NetworkedEntity.Result.DENIED)
	assert_eq(_request("lock", 2), NetworkedEntity.Result.DENIED)
	assert_eq(_request("leave", 2), NetworkedEntity.Result.DENIED)
	assert_eq(_request("guest", 2, 1), NetworkedEntity.Result.DENIED)
	assert_eq(_request("guest", 1, 2), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_request("toggle", 2), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_door.net_state, SwingDoor.State.OPEN_IN)
	assert_eq(_request("guest", 1, 2), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_request("toggle", 2), NetworkedEntity.Result.DENIED)
	other.net_position = Vector3(-1.6, 1, 1.3)
	_player.net_position = Vector3(10, 1, 10)
	assert_eq(_request("toggle", 2), NetworkedEntity.Result.ACCEPTED, "Inside can always exit")
	assert_eq(_door.net_state, SwingDoor.State.CLOSED)
	other.net_position = Vector3(0, 1, -1.5)
	_player.net_position = Vector3(0, 1, -1.5)
	assert_eq(_request("lock"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_request("toggle", 2), NetworkedEntity.Result.ACCEPTED, "Unlocked admits everyone")


func test_payload_range_missing_peer_and_cooldown_are_enforced() -> void:
	for payload: Dictionary in [
		{},
		{"operation": 1},
		{"operation": "rent", "peer": 1},
		{"operation": "guest", "guest": "2"},
		{"operation": "unknown"}
	]:
		assert_eq(_door._entity._evaluate(1, &"manage", payload), NetworkedEntity.Result.DENIED)
	assert_eq(_request("rent", 999), NetworkedEntity.Result.DENIED)
	_player.net_position.z = -10
	assert_eq(_request("rent"), NetworkedEntity.Result.DENIED)
	_player.net_position.z = -1.5
	assert_eq(_request("toggle"), NetworkedEntity.Result.ACCEPTED)
	assert_eq(
		_door._entity._evaluate(1, &"manage", {"operation": "toggle"}),
		NetworkedEntity.Result.COOLDOWN
	)


func test_obstruction_does_not_move_leaf_and_mode_change_resets_everything() -> void:
	await _rent()
	var other := _make_player(2)
	other.net_position = Vector3(0, 1, 0.8)
	assert_eq(_request("toggle"), NetworkedEntity.Result.DENIED)
	assert_eq(_door.net_state, SwingDoor.State.CLOSED)
	_request("guest", 1, 2)
	_door._reset(Network.Mode.OFFLINE)
	assert_eq(_door.occupant, "")
	assert_eq(_door.guests, [] as Array[int])
	assert_false(_door.locked)


func test_guest_disconnect_releases_room_and_revokes_guest_permission() -> void:
	await _rent()
	_make_player(2)
	_request("guest", 1, 2)
	_door._disconnected(2)
	assert_eq(_door.guests, [] as Array[int])
	_door._disconnected(1)
	assert_eq(_door.occupant, "")


func test_account_reconnect_and_respawn_retain_owner_not_peer_number() -> void:
	await _rent()
	_door._owner = "account:123"
	Network.peer_accounts[1] = {"account_id": 123}
	_door._disconnected(1)
	assert_eq(_door.occupant, "Resident 1")
	Network.peer_accounts.erase(1)
	assert_eq(_request("lock"), NetworkedEntity.Result.DENIED, "Reused peer is not owner")
	Network.peer_accounts[2] = {"account_id": 123}
	_make_player(2)
	assert_eq(_request("lock", 2), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_request("lock", 2), NetworkedEntity.Result.ACCEPTED, "Respawn keeps identity")


func test_use_opens_modal_and_close_restores_controls() -> void:
	_door.request_use()
	assert_not_null(_door._panel)
	assert_true(_door._panel.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	_door._panel.call("close")
	assert_false(_door._panel.is_in_group(&"modal_ui"))
	assert_eq(_door.net_state, SwingDoor.State.CLOSED, "Opening management doesn't open leaf")


func test_collision_and_nameplates_follow_the_original_hinge() -> void:
	_door.occupant = "Resident 1"
	await wait_physics_frames(3)
	var space := _door.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, -1), Vector3(0, 1, 1))
	ray.exclude = [_player.get_rid()]
	assert_false(space.intersect_ray(ray).is_empty(), "Closed guest leaf blocks the doorway")
	assert_eq(_request("toggle"), NetworkedEntity.Result.ACCEPTED)
	_door._physics_process(0.5)
	await wait_physics_frames(2)
	assert_true(space.intersect_ray(ray).is_empty(), "Open guest leaf clears the doorway")
	assert_almost_eq(_door._pivot.rotation.y, -PI / 2, 0.001)
	for plate: Label3D in _door._nameplates:
		assert_same(plate.get_parent(), _door._pivot)
		assert_string_contains(plate.text, "Resident 1")


func test_all_eighteen_doors_keep_positions_names_and_inside_escape_direction() -> void:
	var feature := preload("res://features/hotel_annex/feature.tscn").instantiate()
	add_child_autofree(feature)
	var doors := feature.get_node("Atrium/RoomDoors")
	assert_eq(doors.get_child_count(), 18)
	for node: Node in doors.get_children():
		var door := node as HotelGuestDoor
		assert_not_null(door)
		assert_eq(door.door_label, "Room " + str(door.name).trim_prefix("Room"))
		assert_eq(door.width, 1.8)
		assert_true(door.position.y in [4.0, 8.0, 12.0])
		assert_true(door.position.z in [5.5, 17.0, 28.5])
		var sign_x := -1.0 if door.position.x < 0 else 1.0
		_player.net_position = door.global_position + Vector3(sign_x * 1.5, 1, 0)
		assert_true(door._inside(_player))
		_player.net_position = door.global_position - Vector3(sign_x * 1.5, -1, 0)
		assert_false(door._inside(_player))
		assert_true(NodePath(".:occupant") in door._entity.replicated_properties)
		assert_false(NodePath(".:_owner") in door._entity.replicated_properties)
