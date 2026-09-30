extends Node


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	# Existing server HUD retains a freed remote hand on this base.
	if Network.mode == Network.Mode.SERVER:
		$Game/Features/weapon_hotbar.set_process(false)
	match Network.args.get("consume-role", ""):
		"driver":
			_drive()
		"observer":
			_observe()


func _drive() -> void:
	var hand: Hand
	var player: Player
	while hand == null or player == null:
		await get_tree().process_frame
		hand = Hand.for_peer(get_tree(), multiplayer.get_unique_id())
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	var shop: Node3D = $Game/Features/bar_companion/Bartender
	var entity := shop.get_node("NetworkedEntity") as NetworkedInteraction
	player.position = shop.global_position + Vector3(0, -0.3, 0.8)
	player.net_position = player.position
	await get_tree().create_timer(0.4).timeout
	entity.request_action(&"order", {"item": "cigarette", "price": 0})
	await get_tree().create_timer(0.2).timeout
	_check(hand.net_item_id == "", "Forged price accepted")
	entity.request_action(&"order", {"item": "cigarette"})
	while hand.net_item_id != "cigarette":
		await get_tree().process_frame
	hand.request_primary_action.rpc_id(1)
	while not hand.consumption.active():
		await get_tree().process_frame
	print("CONSUMABLE_STARTED")
	while hand.consumption.active():
		await get_tree().process_frame
	_check(hand.net_item_id == "", "Consumed cigarette retained")
	entity.request_action(&"order", {"item": "beer"})
	while hand.net_item_id != "beer":
		await get_tree().process_frame
	hand.request_primary_action.rpc_id(1)
	await get_tree().create_timer(0.3).timeout
	_check(hand.consumption.active(), "Beer animation absent")
	var bar: BarCompanion = $Game/Features/bar_companion
	await get_tree().create_timer(0.3).timeout
	_check(bar.intoxication_for(hand.peer_id) == 1, "Beer stats missing")
	print("CONSUMABLE_DRIVER_PASS")
	get_tree().quit()


func _observe() -> void:
	var remote: Hand
	while remote == null:
		await get_tree().process_frame
		for node: Node in get_tree().get_nodes_in_group(&"hands"):
			var hand := node as Hand
			if hand.peer_id != multiplayer.get_unique_id() and hand.consumption.active():
				remote = hand
	_check(remote.consumption.view_id() == "cigarette", "Late join missed active cigarette")
	_check(float(remote.consumption.state["left"]) < ConsumableUse.DURATION, "Animation restarted")
	remote.consumption.entity.request_action(&"consume")
	remote.inventory().request_drop.rpc_id(1, -1)
	await get_tree().create_timer(0.2).timeout
	_check(remote.consumption.active(), "Foreign request changed animation")
	_check(remote.held_view() != null, "Remote rig item missing")
	print("CONSUMABLE_LATE_PASS")
	while is_instance_valid(remote):
		await get_tree().process_frame
	print("CONSUMABLE_DISCONNECT_PASS")
	get_tree().quit()


func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		get_tree().quit(1)
