extends GutTest

const FEATURE := preload("res://features/apartments/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _home: Apartments


func before_each() -> void:
	_home = FEATURE.instantiate() as Apartments
	add_child_autofree(_home)


func after_each() -> void:
	Network.peer_accounts.clear()


func _player(peer: int = 1) -> Player:
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(peer)
	player.position = _home.get_node("Lobby/Desk").global_position + Vector3(0, 0, 1.5)
	player.net_position = player.position
	add_child_autofree(player)
	player.set_physics_process(false)
	return player


func test_front_desk_claim_is_free_and_idempotent() -> void:
	_player()
	var desk := _home.get_node("Lobby/Desk")
	desk.request_room()
	desk.request_room()
	assert_eq(_home.unit_for(1), 1)
	assert_eq(_home.floors.get_child_count(), 1)
	assert_string_contains(desk.interaction_text(), "Unit 101")


func test_missing_and_distant_senders_cannot_claim() -> void:
	assert_eq(_home.claim(999), 0)
	var player := _player()
	player.net_position += Vector3(20, 0, 0)
	_home.get_node("Lobby/Desk").request_room()
	assert_eq(_home.unit_for(1), 0)
	assert_eq(_home.floors.get_child_count(), 0)


func test_expansion_happens_only_after_ten_distinct_residents() -> void:
	for peer: int in range(1, 22):
		_player(peer)
		assert_eq(_home.claim(peer), peer)
		assert_eq(_home.floors.get_child_count(), Apartments.floor_number(peer))
		assert_eq(_home.claim(peer), peer)
	assert_eq(Apartments.unit_label(10), "110")
	assert_eq(Apartments.unit_label(11), "201")
	assert_eq(Apartments.unit_label(21), "301")


func test_disconnect_reuses_guest_vacancy_without_removing_floors() -> void:
	_player(1)
	_player(2)
	_home.claim(1)
	_home.claim(2)
	_home._disconnected(1)
	assert_eq(_home.unit_for(1), 0)
	assert_eq(_home.unit_for(2), 2)
	assert_eq(_home.floors.get_child_count(), 1)
	_player(3)
	assert_eq(_home.claim(3), 1)


func test_account_reconnect_reclaims_reservation() -> void:
	Network.peer_accounts[2] = {"account_id": 123}
	_player(2)
	_home.claim(2)
	_home._disconnected(2)
	Network.peer_accounts.erase(2)
	Network.peer_accounts[3] = {"account_id": 123}
	_player(3)
	assert_eq(_home.claim(3), 1)
	assert_eq(_home.floors.get_child_count(), 1)


func test_elevator_preloads_floor_and_returns_to_lobby() -> void:
	var player := _player()
	_home.claim(1)
	var lift := _home.get_node("Lobby/Elevator") as RoomDoor
	var floor_node := _home.floor_for(1)
	player.global_position = lift.global_position + Vector3(0, 0, 1.5)
	player.net_position = player.global_position
	lift.use()
	assert_true(floor_node.is_loaded())
	assert_eq(player.net_position, floor_node.get_node("Arrival").global_position)
	var back := floor_node.get_node("Elevator") as RoomDoor
	assert_true(back.can_use(player))
	back.use()
	assert_true((_home.get_node("Lobby") as StreamedRoom).is_loaded())
	assert_eq(player.net_position, _home.get_node("Lobby/Arrival").global_position)


func test_elevator_rejects_unregistered_and_remote_use() -> void:
	var player := _player()
	var lift := _home.get_node("Lobby/Elevator") as RoomDoor
	player.net_position = lift.global_position
	lift.request_enter()
	assert_eq(player.net_position, lift.global_position)
	player.net_position = _home.get_node("Lobby/Desk").global_position
	_home.claim(1)
	var start := player.net_position
	lift.request_enter()
	assert_eq(player.net_position, start)


func test_late_snapshot_selects_same_floor_and_shows_room() -> void:
	var floor_node := _home._spawn_floor(2) as StreamedRoom
	_home.floors.add_child(floor_node)
	_home.assignments = {1: 11}
	assert_eq(_home.floor_for(1), floor_node)
	assert_string_contains(_home.get_node("Lobby/Desk").interaction_text(), "Unit 201")
	assert_string_contains(_home.get_node("Lobby/Elevator").interaction_text(), "floor 2")
	assert_false(floor_node.is_loaded())


func test_mode_change_discards_old_reservations_and_floors() -> void:
	_player()
	_home.claim(1)
	_home._reset(Network.Mode.OFFLINE)
	await wait_process_frames(1)
	assert_eq(_home.unit_for(1), 0)
	assert_eq(_home.floors.get_child_count(), 0)
	assert_eq(_home.claim(1), 1)


func test_clerk_death_survives_room_streaming_and_does_not_block_claims() -> void:
	_player()
	var lobby := _home.get_node("Lobby") as StreamedRoom
	var clerk := lobby.get_node("Clerk") as StationaryPatron
	clerk.set_physics_process(false)
	assert_eq(clerk.global_position, Vector3(200, 0, 1196))
	clerk.take_hit(1)
	lobby.load_room(10000)
	lobby.unload_room()
	lobby.load_room(10000)
	await wait_physics_frames(2)
	assert_false(clerk.net_alive)
	assert_false(clerk._body.visible)
	_home.get_node("Lobby/Desk").request_room()
	assert_eq(_home.unit_for(1), 1)
	clerk._physics_process(StationaryPatron.RESPAWN_DELAY_S)
	assert_true(clerk.net_alive)
