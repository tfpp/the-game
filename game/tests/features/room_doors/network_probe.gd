extends Game
## Real Player/Hand spawners and hotel endpoints; excludes unrelated game features.

var _role := ""
var _observer_done := false
var _seen: Array[int] = []
var _seen_gallery: Array[int] = []
var _quiesced := false
var _saw_counter := false
var _saw_despawn := false
var _action_result := -1
var _saw_sewer_player := false
var _audio_events: Array[StringName] = []

@onready var _hotel: StreamedRoom = $Features/hotel_annex/Hotel
@onready var _locked: SwingDoor = $Features/hotel_annex/Hotel/RoomDoors/UpperStudyDoor
@onready var _gallery: SwingDoor = $Features/hotel_annex/Hotel/RoomDoors/GalleryDoor
@onready var _key: ItemPickup = $Features/hotel_annex/Hotel/StudyKey
@onready var _ladder: ClimbableLadder = $Features/hotel_annex/Hotel/SewerLadder
@onready var _sewer: SwingDoor = $Features/hotel_annex/Hotel/SewerDoor


func _ready() -> void:
	($Features/game_audio as GameAudio).sound_started.connect(
		func(cue: StringName, _positional: bool, _at: Vector3) -> void: _audio_events.append(cue)
	)
	_spawner.spawn_function = _spawn_player
	($EntitySpawner as MultiplayerSpawner).spawn_function = _spawn_counter
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)
	Network.start_from_environment()
	_role = str(Network.args.get("door-role", "server"))
	if multiplayer.is_server():
		($EntitySpawner as MultiplayerSpawner).spawn("Counter")
	_run.call_deferred()


func _spawn_counter(data: Variant) -> Node:
	var counter := preload("res://tests/fixtures/networked_counter.tscn").instantiate()
	counter.name = str(data)
	return counter


func _spawn_player(data: Variant) -> Node:
	var player := super._spawn_player(data) as Player
	player.set_physics_process(false)
	return player


func _process(_delta: float) -> void:
	for player: Player in get_players():
		if player.net_position.distance_to(_ladder.to_global(_ladder.bottom_landing)) < 0.2:
			_saw_sewer_player = true
	if $Entities.has_node("Counter"):
		_saw_counter = true
	elif _saw_counter and not _saw_despawn:
		_saw_despawn = true
		print("ENTITY_DESPAWN_OBSERVED")
	if _seen.is_empty() or _seen.back() != int(_locked.net_state):
		_seen.append(int(_locked.net_state))
	if _seen_gallery.is_empty() or _seen_gallery.back() != int(_gallery.net_state):
		_seen_gallery.append(int(_gallery.net_state))
	var stop := str(Network.args.get("probe-stop", ""))
	if not _quiesced and FileAccess.file_exists(stop + ".pause"):
		# Stop replication on all peers before closing sockets during harness teardown.
		get_tree().multiplayer_poll = false
		_quiesced = true
		print("DOORS_QUIESCED")
	if FileAccess.file_exists(stop):
		get_tree().quit()


func _run() -> void:
	if _role == "server":
		print("DOORS_SERVER_READY")
		return
	while _local() == null or Hand.for_peer(get_tree(), multiplayer.get_unique_id()) == null:
		await get_tree().process_frame
	if _role == "driver":
		while get_players().size() < 2:
			await get_tree().process_frame
		await _drive()
	elif _role == "late":
		await _late_join()


func _drive() -> void:
	await _pause()
	await _counter_requests()
	await _ladder_trip()
	_gallery.use()
	_key.request_pickup.rpc_id(1)
	await _pause()
	_check(_gallery.net_state == SwingDoor.State.CLOSED and not _key.net_taken, "Range checks")
	await _move_to(_gallery.to_global(Vector3(0, 1, -1.5)))
	_gallery.use()
	await _expect(_gallery, SwingDoor.State.OPEN_IN)
	_gallery.use()
	await _expect(_gallery, SwingDoor.State.CLOSED)
	await _move_to(_locked.to_global(Vector3(0, 1, -1.5)))
	_locked.use()
	await _pause()
	_check(_locked.net_state == SwingDoor.State.LOCKED, "Missing key rejected")
	await _move_to(_key.global_position + Vector3(0, 0, -1))
	# Existing pickup callers still enter the same component validation path.
	_key.request_pickup.rpc_id(1)
	await _pause()
	_check(_key.net_taken, "Shared pickup taken")
	_check(
		Hand.for_peer(get_tree(), multiplayer.get_unique_id()).inventory().has_key(
			"upper_study_key"
		),
		"Key ring replicated"
	)
	await _move_to(_locked.to_global(Vector3(0, 1, -1.5)))
	_locked.use()
	await _expect(_locked, SwingDoor.State.OPEN_IN)
	await _move_to(Vector3(0, 1, 0))
	_hotel._hold_until_msec = 0
	_hotel.unload_room()
	await _pause()
	_check(not _hotel.is_loaded(), "Visitor unloaded geometry")
	for player: Player in get_players():
		if player.get_multiplayer_authority() != multiplayer.get_unique_id():
			_observer_turn.rpc_id(player.get_multiplayer_authority())
	while not _observer_done:
		await get_tree().process_frame
	_check(_locked.net_state == SwingDoor.State.CLOSED, "Other player's changes replicated")
	_check(_seen.has(SwingDoor.State.OPEN_IN), "Saw unlock")
	print("DOORS_DRIVER_PASSED")


@rpc("any_peer", "reliable")
func _observer_turn() -> void:
	var driver := multiplayer.get_remote_sender_id()
	_check(
		(
			_audio_events.has(&"door_open")
			and _audio_events.has(&"door_close")
			and _audio_events.has(&"door_unlock")
		),
		"Door audio reaches observing peers"
	)
	_check(
		not _audio_events.has(&"key_pickup") and not _audio_events.has(&"door_locked"),
		"Private feedback only reaches requesting owner"
	)
	_check(_saw_sewer_player, "Other peer sees player climb into sewer")
	_check(_ladder._player == null, "Mount event only reaches the requesting owner")
	_check(_sewer.net_state == SwingDoor.State.CLOSED, "Sewer door close is shared")
	_check(_seen_gallery.has(SwingDoor.State.OPEN_IN), "Observer saw gallery open")
	_check(_gallery.net_state == SwingDoor.State.CLOSED, "Observer saw gallery close")
	_check(
		_locked.net_state == SwingDoor.State.OPEN_IN and _key.net_taken,
		"Observer saw unlock and pickup"
	)
	_check(
		not Hand.for_peer(get_tree(), multiplayer.get_unique_id()).inventory().has_key(
			"upper_study_key"
		),
		"Observer has no key"
	)
	await _move_to(_locked.to_global(Vector3(0, 1, -1.5)))
	_locked.use()
	await _expect(_locked, SwingDoor.State.CLOSED)
	_locked.use()
	await _expect(_locked, SwingDoor.State.OPEN_IN)
	_locked.use()
	await _expect(_locked, SwingDoor.State.CLOSED)
	await _move_to(Vector3(0, 1, 0))
	_done.rpc_id(driver)
	print("DOORS_OBSERVER_PASSED")


@rpc("any_peer", "reliable")
func _done() -> void:
	_observer_done = true


func _late_join() -> void:
	await _pause()
	_check(_audio_events.is_empty(), "Late join does not replay sound events")
	_check(_ladder._player == null, "Late join does not replay an earlier ladder mount")
	var counter := $Entities/Counter
	_check(int(counter.get("value")) == 9, "Late join receives current spawned entity state")
	_check(
		_locked.net_state == SwingDoor.State.CLOSED and _key.net_taken,
		"Late join receives unlocked door and missing pickup"
	)
	await _move_to(_locked.to_global(Vector3(0, 1, -1.5)))
	_locked.use()
	await _expect(_locked, SwingDoor.State.OPEN_IN)
	_locked.use()
	await _expect(_locked, SwingDoor.State.CLOSED)
	_despawn_counter.rpc_id(1)
	await _pause()
	_check(not $Entities.has_node("Counter"), "Spawner removes entity and its endpoint")
	print("DOORS_LATE_JOIN_PASSED")


func _counter_requests() -> void:
	var counter := $Entities/Counter
	var entity := counter.get_node("NetworkedEntity") as NetworkedEntity
	entity.request_finished.connect(_result_received)
	_check(int(counter.get("value")) == 7, "Server spawn state")
	entity.request_action(&"set", {"value": 999})
	await _pause()
	_check(_action_result == NetworkedEntity.Result.UNKNOWN_ACTION, "Unknown action rejected")
	entity.request_action(&"add", {"amount": 2, "peer": 1})
	await _pause()
	_check(_action_result == NetworkedEntity.Result.DENIED, "Forged identity field rejected")
	_check(int(counter.get("value")) == 7, "Rejected actions preserve shared state")
	entity.request_action(&"add", {"amount": 2})
	await _pause()
	_check(_action_result == NetworkedEntity.Result.ACCEPTED, "Server acknowledges action")
	_check(int(counter.get("value")) == 9, "Accepted state replicated")
	_check(
		int(counter.get("last_peer")) == multiplayer.get_unique_id(),
		"Authenticated sender retained"
	)


func _ladder_trip() -> void:
	await _move_to(_ladder.to_global(_ladder.top_landing))
	(_ladder.get_node("TopUse") as NetworkedInteraction).request_use()
	await _pause()
	_check(_ladder._player == null, "Closed sewer door prevents descending")
	await _move_to(_sewer.to_global(Vector3(0, 1, -1.5)))
	_sewer.use()
	await _expect(_sewer, SwingDoor.State.OPEN_IN)
	await _move_to(_ladder.to_global(_ladder.top_landing))
	_ladder.use()
	await _pause()
	_check(_ladder._player == _local(), "Server mounts the requesting player")
	_ladder._climb(-1, 3)
	await _pause()
	_check(
		_local().net_position.distance_to(_ladder.to_global(_ladder.bottom_landing)) < 0.15,
		"Down ladder"
	)
	_check(_hotel.is_loaded(), "Sewer stays loaded below hotel")
	_ladder.use()
	await _pause()
	_ladder._climb(1, 3)
	await _pause()
	_check(
		_local().net_position.distance_to(_ladder.to_global(_ladder.top_landing)) < 0.15,
		"Up ladder"
	)
	await _move_to(_sewer.to_global(Vector3(0, 1, -1.5)))
	_sewer.use()
	await _expect(_sewer, SwingDoor.State.CLOSED)
	await _move_to(Vector3(0, 1, 0))


func _result_received(_action: StringName, result: NetworkedEntity.Result) -> void:
	_action_result = int(result)


@rpc("any_peer", "call_local", "reliable")
func _despawn_counter() -> void:
	if multiplayer.is_server():
		$Entities/Counter.queue_free()


func _local() -> Player:
	return get_tree().get_first_node_in_group(&"local_player") as Player


func _move_to(at: Vector3) -> void:
	_local().global_position = at
	_local().net_position = at
	await _pause()


func _expect(door: SwingDoor, state: SwingDoor.State) -> void:
	await _pause()
	_check(door.net_state == state, "Door state expected %d, got %d" % [state, door.net_state])


func _pause() -> void:
	await get_tree().create_timer(0.65).timeout


func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error("DOORS_PROBE: " + message)
		get_tree().quit(1)
