extends "res://tests/features/frogs/death_network_probe.gd"
## Reuse real frog authority/late-join/death assertions at the mall colony path.


func _frog() -> Frog:
	return get_node_or_null("Game/Features/strip_mall/Room/FrogDisplay/Colony/Pond/Frog0") as Frog


func _server() -> void:
	while _frog() == null:
		await get_tree().process_frame
	var frog := _frog()
	var rivalry := get_node("Game/Features/strip_mall/Room/Rivalry")
	rivalry.set_physics_process(false)
	rivalry.net_turn = 2
	rivalry.net_remaining = 2.0
	frog.set_physics_process(false)
	while multiplayer.get_peers().is_empty():
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	frog.take_hit(1)
	while multiplayer.get_peers().size() < 2:
		await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	rivalry.advance(2.0)
	frog._physics_process(Frog.RESPAWN_DELAY_S)
	print("FROG_SERVER_RESPAWNED")


func _client() -> void:
	while _frog() == null:
		await get_tree().process_frame
	_check(_frog().get_parent().get_child_count() == 3, "Receive exactly three spawned frogs")
	_check(is_equal_approx(_frog().body_size, .325), "Receive the authored small profile")
	_check(not _frog().is_physics_processing(), "Only the server simulates frogs")
	var rivalry := get_node("Game/Features/strip_mall/Room/Rivalry")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(rivalry.net_turn == 2, "Visitor/late join receives current rivalry turn")
	# Continuous countdown may follow the on-change turn snapshot by one interval.
	await get_tree().create_timer(0.3).timeout
	_check(is_equal_approx(rivalry.net_remaining, 2.0), "Receive current countdown")
	rivalry.advance(100.0)
	_check(rivalry.net_turn == 2, "Client cannot advance server argument")
	await super._client()
	while rivalry.net_turn != 3:
		await get_tree().process_frame
	_check(rivalry.active_speaker() == 1, "Server advances speaker on both clients")
	print("RIVALRY_CLIENT_SYNCED")
