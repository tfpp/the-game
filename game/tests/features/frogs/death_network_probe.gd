extends Node
## Real peers exercise authority, death events, dead late joins and respawning.


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	if multiplayer.is_server():
		_server()
	else:
		_client()


func _frog() -> Frog:
	return get_node_or_null("Game/Features/frogs/Pond/Frog0") as Frog


func _server() -> void:
	var frog := _frog()
	frog.set_physics_process(false)
	# Stress the gap between snapshots; alive and position must arrive together.
	frog.get_node("Sync").replication_interval = 0.25
	frog.position += Vector3(10, 2, 10)
	frog.net_position = frog.position
	while get_tree().get_nodes_in_group(&"players").is_empty():
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	frog.take_hit(1)
	await get_tree().create_timer(Frog.RESPAWN_DELAY_S).timeout
	frog._physics_process(Frog.RESPAWN_DELAY_S)
	print("FROG_SERVER_RESPAWNED")


func _client() -> void:
	while _frog() == null:
		await get_tree().process_frame
	var frog := _frog()
	await get_tree().process_frame
	await get_tree().process_frame
	var late: bool = Network.args.get("frog-role", "") == "late"
	if late:
		_check(not frog.net_alive, "Late join must receive the dead state")
		_check(_effects(frog) == 0, "Late join must not replay an old explosion")
	else:
		_check(frog.net_alive, "First client should see the live frog")
		frog.take_hit(multiplayer.get_unique_id())
		_check(frog.net_alive, "Clients cannot directly kill frogs")
		while frog.net_alive:
			await get_tree().process_frame
		await get_tree().process_frame
		_check(_effects(frog) == 1, "Current clients should play one explosion")
	_check(not frog.get_node("Body").visible, "Dead frog body must be hidden")
	_check(frog.get_node("Collider").disabled, "Dead frog collision must be disabled")
	print("FROG_CLIENT_DEAD")
	while not frog.net_alive:
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(frog.get_node("Body").visible, "Respawn body missing")
	_check(not frog.get_node("Collider").disabled, "Respawn collider missing")
	_check(frog.position.distance_to(frog._home) < 0.001, "Respawn must snap to home")
	_check(_effects(frog) == 0, "Explosion debris leaked past respawn")
	print("FROG_CLIENT_RESPAWNED")


func _effects(frog: Frog) -> int:
	var count := 0
	for child: Node in frog.get_children():
		if child is MeshExplosion:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		get_tree().quit(1)
