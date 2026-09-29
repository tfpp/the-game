extends Node
## Standalone real-WebSocket coverage probe.


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	# Force a large gap between original spawn data and the current snapshot.
	if multiplayer.is_server():
		for frog: Node3D in $Game/Features/frogs/Pond.get_children():
			frog.set_physics_process(false)
			frog.position = Vector3(15, 2, 20)
			frog.net_position = frog.position
	else:
		get_tree().node_added.connect(_on_node_added)
	match Network.args.get("inventory-role", ""):
		"driver":
			_drive()
		"observer":
			_observe()


func _drive() -> void:
	var player: Player
	var hand: Hand
	while player == null or hand == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
		hand = Hand.for_peer(get_tree(), multiplayer.get_unique_id())
	player.set_physics_process(false)
	var inventory := hand.inventory()
	_check(
		inventory.shirt.is_empty() and inventory.pants.is_empty(), "New players must be undressed"
	)
	var shirt := $Game/Features/inventory/TealShirt as ItemPickup
	player.position = Vector3(0, 1, 25)
	player.net_position = player.position
	await get_tree().create_timer(0.4).timeout
	shirt.request_pickup.rpc_id(1)
	await get_tree().create_timer(0.3).timeout
	_check(not shirt.net_taken, "Out-of-range request accepted")
	for path: String in [
		"inventory/TealShirt",
		"inventory/BluePants",
		"holdables/Pickups/Pistol",
		"holdables/Pickups/Banana"
	]:
		var pickup := get_node("Game/Features/" + path) as ItemPickup
		player.position = pickup.position + Vector3.UP * 0.8
		player.net_position = player.position
		await get_tree().create_timer(0.4).timeout
		pickup.request_pickup.rpc_id(1)
		pickup.request_pickup.rpc_id(1)
		while not pickup.net_taken:
			await get_tree().process_frame
	_check(inventory.backpack.count("banana") == 1, "Duplicate pickup created an extra item")
	_check(inventory.shirt == "shirt:2" and inventory.pants == "pants:3", "Clothes not replicated")
	print("INVENTORY_DRIVER_READY")
	while get_tree().get_nodes_in_group(&"players").size() < 2:
		await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	inventory.request_equip.rpc_id(1, 0)
	inventory.request_drop.rpc_id(1, -2)
	inventory.request_drop.rpc_id(1, -3)
	while inventory.shirt != "" or inventory.pants != "" or hand.net_item_id != "banana":
		await get_tree().process_frame
	_check(inventory.backpack[0] == "pistol", "Swap lost the held item")
	print("INVENTORY_DRIVER_DONE")


func _observe() -> void:
	var remote: Player
	var hand: Hand
	while hand == null:
		await get_tree().process_frame
		for node: Node in get_tree().get_nodes_in_group(&"players"):
			var candidate := node as Player
			if candidate != null and not candidate.is_local():
				remote = candidate
				hand = Hand.for_peer(get_tree(), remote.get_multiplayer_authority())
	var inventory := hand.inventory()
	while inventory.shirt != "shirt:2" or inventory.pants != "pants:3":
		await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	var model := remote.get_node("Body/Avatar") as BlockPlayerModel
	_check(model.skin_color == PlayerSkin.TONES[hand.skin_tone_index()], "Late skin tone mismatch")
	_check(hand._arms._glove.albedo_color == model.skin_color, "Held hands have wrong skin")
	_check(
		model.shirt_id == "shirt:2" and model.pants_id == "pants:3", "Late avatar clothing missing"
	)
	_check(
		hand.net_item_id == "pistol" and inventory.backpack[0] == "banana", "Late bag state missing"
	)
	inventory.request_stow.rpc_id(1, -2)
	inventory.request_drop.rpc_id(1, -3)
	inventory.request_equip.rpc_id(1, 0)
	await get_tree().create_timer(0.5).timeout
	_check(
		inventory.shirt == "shirt:2" and inventory.pants == "pants:3",
		"Foreign clothing request accepted"
	)
	_check(hand.net_item_id == "pistol", "Foreign equip request accepted")
	print("INVENTORY_OWNER_CHECK_PASSED")
	while inventory.shirt != "" or inventory.pants != "" or hand.net_item_id != "banana":
		await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	_check(model.shirt_id.is_empty() and model.pants_id.is_empty(), "Remote removal not applied")
	_check(
		not bool(model.human.material.get_shader_parameter("pants_equipped")),
		"Remote underwear not restored"
	)
	_check(inventory.backpack[0] == "pistol", "Remote backpack swap missing")
	print("INVENTORY_OBSERVER_DONE")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		get_tree().quit(1)


func _on_node_added(node: Node) -> void:
	if node is Frog and not multiplayer.is_server():
		(node as Frog).ready.connect(_check_frog_spawn.bind(node), CONNECT_DEFERRED)


func _check_frog_spawn(frog: Frog) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(frog):
		_check(frog.position.distance_to(Vector3(15, 2, 20)) < 0.001, "Late frog slid from spawn")
