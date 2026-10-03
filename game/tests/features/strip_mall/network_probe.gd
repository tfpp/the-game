extends "res://tests/features/frogs/death_network_probe.gd"
## Reuse real frog authority/late-join/death assertions at the mall colony path.


func _frog() -> Frog:
	return get_node_or_null("Game/Features/strip_mall/Room/FrogDisplay/Colony/Pond/Frog0") as Frog


func _server() -> void:
	while _frog() == null:
		await get_tree().process_frame
	var frog := _frog()
	frog.set_physics_process(false)
	while multiplayer.get_peers().is_empty():
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	frog.take_hit(1)
	while multiplayer.get_peers().size() < 2:
		await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	frog._physics_process(Frog.RESPAWN_DELAY_S)
	print("FROG_SERVER_RESPAWNED")


func _client() -> void:
	while _frog() == null:
		await get_tree().process_frame
	_check(_frog().get_parent().get_child_count() == 3, "Receive exactly three spawned frogs")
	_check(is_equal_approx(_frog().body_size, .325), "Receive the authored small profile")
	_check(not _frog().is_physics_processing(), "Only the server simulates frogs")
	await super._client()
