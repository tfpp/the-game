extends GutTest

const FEATURE := preload("res://features/starter_room/feature.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _feature: Node3D
var _van: OperationsVan
var _player: Player


func before_each() -> void:
	_feature = FEATURE.instantiate()
	add_child_autofree(_feature)
	_van = _feature.get_node("Room/Van")
	_van.set_physics_process(false)
	_player = PLAYER.instantiate()
	_player.name = "1"
	_player.position = _van.to_global(Vector3(-1.6, 1, 1))
	_player.net_position = _player.position
	add_child_autofree(_player)
	_player.set_physics_process(false)


func after_each() -> void:
	_van.panel.close(false)


func test_use_is_authenticated_and_only_opens_a_private_modal() -> void:
	assert_eq(_van.entity._evaluate(99, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_van.entity._evaluate(1, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	_van.use()
	assert_true(_van.panel.is_open())
	assert_true(_van.panel.is_in_group(&"modal_ui"))
	assert_eq(_van._pending.size(), 0)
	_van.panel.close()
	assert_false(_van.panel.is_in_group(&"modal_ui"))


func test_shared_garage_route_is_hidden_and_rejected_without_cheats() -> void:
	var marker := Marker3D.new()
	marker.name = "DevelopmentGarage"
	_feature.add_child(marker)
	_van.arrivals[1] = _van.get_path_to(marker)
	assert_null(_van.arrival(1))
	assert_eq(_van.entity._evaluate(1, &"travel", {"zone": 1}), NetworkedEntity.Result.DENIED)
	_van.use()
	assert_false(_van.panel._buttons[1].visible)
	var cheats := preload("res://tests/features/dev_access/cheats_fixture.gd").enable(self)
	assert_eq(_van.arrival(1), marker)
	assert_true(_van._validate_trip(1, {"zone": 1}))
	_van.panel.open_map(_van)
	assert_true(_van.panel._buttons[1].visible)
	cheats.set("cheats_enabled", false)
	assert_false(_van._validate_trip(1, {"zone": 1}), "Stale open menus cannot bypass the lock")


func test_rejects_unknown_zone_wrong_types_extra_fields_and_distant_players() -> void:
	for payload: Dictionary in [
		{}, {"zone": -1}, {"zone": 30}, {"zone": 0.0}, {"zone": "0"}, {"zone": 0, "peer": 1}
	]:
		assert_eq(_van.entity._evaluate(1, &"travel", payload), NetworkedEntity.Result.DENIED)
	assert_eq(_van.entity._evaluate(8, &"travel", {"zone": 0}), NetworkedEntity.Result.DENIED)
	_player.net_position += Vector3(10, 0, 0)
	assert_eq(_van.entity._evaluate(1, &"travel", {"zone": 0}), NetworkedEntity.Result.DENIED)
	assert_eq(_van._pending.size(), 0)


func test_trip_waits_for_driving_then_uses_existing_owner_teleport() -> void:
	var start := _player.net_position
	_van.request_trip(0)
	assert_true(_van.panel.is_open())
	assert_eq(_player.net_position, start)
	assert_eq(_van.entity._evaluate(1, &"travel", {"zone": 0}), NetworkedEntity.Result.DENIED)
	_van._physics_process(OperationsVan.TRAVEL_SECONDS * .5)
	assert_eq(_player.net_position, start)
	_van._physics_process(OperationsVan.TRAVEL_SECONDS)
	assert_eq(_player.net_position, _van.arrival(0).global_position)
	assert_eq(_van._pending.size(), 0)
	_van.panel._process(OperationsVan.TRAVEL_SECONDS)
	assert_false(_van.panel.is_open())


func test_walking_exit_and_casino_return_preserve_streamed_floor_preload() -> void:
	var room := _feature.get_node("Room") as StreamedRoom
	var returning := _feature.get_node("CasinoReturn") as RoomDoor
	_player.net_position = returning.global_position
	returning.use()
	assert_true(room.is_loaded())
	assert_true(room.arrival_held())
	assert_eq(_player.net_position, (_feature.get_node("Room/Arrival") as Marker3D).global_position)
	var exit := _feature.get_node("Room/WalkingExit") as RoomDoor
	_player.net_position = exit.global_position
	exit.use()
	assert_eq(_player.net_position, _van.arrival(0).global_position)


func test_death_disconnect_session_reset_and_walking_away_cancel_trips() -> void:
	var start := _player.net_position
	_van.request_trip(0)
	_van._on_death(1, 2)
	assert_eq(_van._pending.size(), 0)
	_van._physics_process(10)
	assert_eq(_player.net_position, start)
	assert_false(_van.panel.is_open())
	_van.request_trip(0)
	_van._cancel_peer(1)
	assert_eq(_van._pending.size(), 0)
	_van.request_trip(0)
	_van._reset(Network.Mode.OFFLINE)
	assert_eq(_van._pending.size(), 0)
	_van.request_trip(0)
	_player.net_position += Vector3(8, 0, 0)
	_van._physics_process(10)
	assert_eq(_van._pending.size(), 0)
	assert_false(_van.panel.is_open())


func test_two_players_can_prepare_independent_trips_without_global_cooldown() -> void:
	var other := PLAYER.instantiate() as Player
	other.name = "2"
	other.set_multiplayer_authority(2)
	other.net_position = _player.net_position
	add_child_autofree(other)
	other.set_physics_process(false)
	# Validate both before applying: transport's owner events require a connected peer.
	assert_true(_van._validate_trip(1, {"zone": 0}))
	assert_true(_van._validate_trip(2, {"zone": 0}))
	_van._pending[2] = {"zone": 0, "remaining": 2.0}
	_van.request_trip(0)
	assert_eq(_van._pending.size(), 2)
	assert_false(_van._validate_trip(2, {"zone": 0}))
	_van._cancel_peer(2)
	assert_true(_van._pending.has(1))


func test_destination_button_preserves_input_lock_but_modal_blocks_gameplay() -> void:
	_van.use()
	assert_true(_van.panel.is_open())
	_van.panel._buttons[0].pressed.emit()
	assert_true(_van.panel._travelling)
	assert_true(_van.panel.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	assert_true(Controls.playing, "recaptured within the button gesture, not on arrival")


func test_respawning_players_cannot_open_map_or_depart() -> void:
	var combat := Combat.new()
	add_child_autofree(combat)
	combat.apply_damage(1, Combat.MAX_HEALTH, 1)
	assert_true(combat.is_respawning(1))
	assert_eq(_van.entity._evaluate(1, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_van.entity._evaluate(1, &"travel", {"zone": 0}), NetworkedEntity.Result.DENIED)


func test_map_pins_stay_on_image_and_do_not_overlap_at_small_sizes() -> void:
	_van.use()
	var map := _van.panel._map
	assert_true(map is TextureRect)
	assert_not_null((map as TextureRect).texture)
	for side: float in [274.0, 366.0, 424.0]:
		map.size = Vector2.ONE * side
		map._layout()
		for i: int in _van.panel._buttons.size():
			var pin := _van.panel._buttons[i]
			assert_true(Rect2(Vector2.ZERO, map.size).encloses(pin.get_rect()))
			assert_gte(pin.size.y, 43.99)
			for j: int in range(i + 1, _van.panel._buttons.size()):
				assert_false(pin.get_rect().intersects(_van.panel._buttons[j].get_rect()))
	assert_false(_van.panel._buttons[0].disabled)
	assert_eq(_van.panel._buttons.size(), 5)
	assert_true(_van.panel._buttons[3].disabled, "missing destination cannot be selected")
	assert_true(_van.panel._buttons[4].disabled, "missing mall cannot be selected")


func test_driving_vignette_animates_only_during_travel() -> void:
	_van.use()
	var drive := _van.panel._drive
	assert_false(drive.visible)
	_van.panel._buttons[0].pressed.emit()
	assert_true(drive.visible)
	assert_false(_van.panel._map.visible)
	drive._process(.1)
	assert_gt(float(drive.elapsed), 0.0)
	assert_ne(drive._van.position.y, 0.0)
	_van.panel.close(false)
	assert_false(drive.visible)
