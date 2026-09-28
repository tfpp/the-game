extends Node

var _shots := 0
var _pickups := 0
var _position := Vector3.ZERO


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	$Game/Features/game_audio.sound_started.connect(_on_sound)
	match Network.args.get("audio-role", ""):
		"driver":
			_driver()
		"observer":
			_observer()


func _on_sound(cue: StringName, positional: bool, at: Vector3) -> void:
	if cue == &"pistol":
		_shots += 1
		_position = at
		_check(positional, "Shots must be positional")
	if cue == &"pickup":
		_pickups += 1


func _driver() -> void:
	var hand: Hand
	var player: Player
	while hand == null or player == null:
		await get_tree().process_frame
		hand = Hand.for_peer(get_tree(), multiplayer.get_unique_id())
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	var pickup := $Game/Features/holdables/Pickups/Pistol as ItemPickup
	player.position = pickup.position + Vector3.UP * 0.8
	player.net_position = player.position
	await get_tree().create_timer(0.3).timeout
	pickup.request_pickup.rpc_id(1)
	while hand.net_item_id != "pistol" or _pickups == 0:
		await get_tree().process_frame
	hand.request_primary_action.rpc_id(1)
	hand.request_primary_action.rpc_id(1)
	await get_tree().create_timer(0.4).timeout
	_check(_shots == 1, "Cooldown must suppress duplicate shot audio")
	print("AUDIO_DRIVER_READY")
	while get_tree().get_nodes_in_group(&"players").size() < 2:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	player.position = Vector3(3, 2, 10)
	player.net_position = player.position
	await get_tree().create_timer(0.3).timeout
	hand.request_primary_action.rpc_id(1)
	await get_tree().create_timer(0.4).timeout
	_check(_shots == 2, "Owner must hear exactly one new shot")
	print("AUDIO_DRIVER_DONE")


func _observer() -> void:
	var hand: Hand
	while hand == null:
		await get_tree().process_frame
		for node: Node in get_tree().get_nodes_in_group(&"hands"):
			if (node as Hand).peer_id != multiplayer.get_unique_id():
				hand = node as Hand
	await get_tree().create_timer(0.2).timeout
	_check(_shots == 0 and _pickups == 0, "Late join must not replay old sounds")
	hand.request_primary_action.rpc_id(1)
	await get_tree().create_timer(0.3).timeout
	_check(_shots == 0, "Foreign fire requests must not create sound")
	print("AUDIO_OBSERVER_READY")
	while _shots == 0:
		await get_tree().process_frame
	_check(_shots == 1 and _pickups == 0, "Remote shot should play once without private UI audio")
	_check(absf(_position.x - 3.0) < 0.01, "Remote sound must use server firing position")
	_check(absf(_position.z - 10.0) < 0.01, "Remote sound must use server firing position")
	print("AUDIO_OBSERVER_DONE")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		get_tree().quit(1)
