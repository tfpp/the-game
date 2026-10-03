extends "res://tests/features/frogs/death_network_probe.gd"
## Reuse real frog authority/late-join/death assertions at the mall colony path.

const RealTime := preload("res://tests/fixtures/real_time.gd")


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
	# Keep the frog alive until the first purchase settles, so the extended
	# probe's network waits cannot race the original live-frog assertion.
	var purchased := false
	while not purchased:
		for hand: Hand in get_tree().get_nodes_in_group(&"hands"):
			purchased = purchased or hand.net_item_id == "poke_bowl"
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
	_food_client()
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


func _food_client() -> void:
	var late: bool = Network.args.get("frog-role", "") == "late"
	var path := "CitySushiShop" if late else "CityWokShop"
	var stand := get_node("Game/Features/strip_mall/Room/" + path) as PokeStand
	_check(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					stand.entity.player_for_peer(multiplayer.get_unique_id()) != null
					and Hand.for_peer(get_tree(), multiplayer.get_unique_id()) != null
				),
			5.0
		),
		"Receive buyer and inventory"
	)
	var peer := multiplayer.get_unique_id()
	var player := stand.entity.player_for_peer(peer)
	var hand := Hand.for_peer(get_tree(), peer)
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	_check(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return wallet.balances.has(peer), 5.0
		),
		"Receive wallet snapshot"
	)
	if late:
		var previous := false
		for other: Hand in get_tree().get_nodes_in_group(&"hands"):
			if other.peer_id != peer and other.net_item_id == "poke_bowl":
				previous = true
		_check(previous, "Late visitor sees first customer's purchased bowl")
	player.set_physics_process(false)
	player.net_position = stand.to_global(Vector3(0, 1, 1.7))
	player.global_position = player.net_position
	await RealTime.wait(get_tree(), .4)
	var balance: int = wallet.balances[peer]
	stand.entity.request_action(&"order", {"tip": 0, "price": 1})
	await RealTime.wait(get_tree(), .2)
	_check(hand.net_item_id.is_empty(), "Forged price cannot deliver food")
	_check(wallet.balances[peer] == balance, "Forged price cannot spend money")
	stand.use()
	var menu: CanvasLayer = stand.get_node("Menu")
	_check(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return menu.is_in_group(&"modal_ui"), 5.0
		),
		"Validated Use opens owner's menu"
	)
	menu._buttons[0].pressed.emit()
	_check(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					hand.net_item_id == "poke_bowl"
					and wallet.balances[peer] == balance - stand.price_cents
				),
			5.0
		),
		"Server charges counter price and replicates purchased food"
	)
	stand.entity.request_action(&"order", {"tip": 0})
	await RealTime.wait(get_tree(), .2)
	_check(
		wallet.balances[peer] == balance - stand.price_cents, "Repeat request cannot charge twice"
	)
	menu._close()
	print("CITY_FOOD_PURCHASED")
