extends GutTest

const STAND := preload("res://features/food_court/wendys_stand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")
const RealTime := preload("res://tests/fixtures/real_time.gd")

var _stand: Node3D
var _player: Player
var _hand: Hand


func before_each() -> void:
	_stand = STAND.instantiate()
	add_child_autofree(_stand)
	_player = _customer(1)
	_hand = _make_hand(1)


func test_use_delivers_one_burger_and_repeated_use_cannot_duplicate() -> void:
	_stand.use()
	assert_eq(_hand.net_item_id, "wendys_burger")
	_stand.use()
	assert_eq(_hand.inventory().backpack.count(""), 8)
	assert_eq(_request(), NetworkedEntity.Result.COOLDOWN)


func test_occupied_hand_collects_into_backpack() -> void:
	_hand.inventory().collect("kebab")
	assert_eq(_request(), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_hand.net_item_id, "kebab")
	assert_eq(_hand.inventory().backpack[0], "wendys_burger")


func test_full_bag_does_not_start_cooldown() -> void:
	for index: int in 9:
		_hand.inventory().collect("banana")
	assert_eq(_request(), NetworkedEntity.Result.DENIED)
	assert_string_contains(_stand.interaction_text(), "make room")
	_hand.net_item_id = ""
	assert_eq(_request(), NetworkedEntity.Result.ACCEPTED)


func test_rejects_missing_peer_payload_backside_range_and_non_authority() -> void:
	var entity := _stand.get_node("NetworkedEntity") as NetworkedInteraction
	assert_eq(entity._evaluate(77, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(entity._evaluate(1, &"use", {"peer": 2}), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(0, 1, -1)
	assert_eq(_request(), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(0, 1, 8)
	assert_eq(_request(), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(0, 1, 1.7)
	entity.set_multiplayer_authority(77)
	assert_eq(_request(), NetworkedEntity.Result.DENIED)
	assert_eq(_hand.net_item_id, "")


func test_two_customers_serialize_then_session_reset_restores_service() -> void:
	var second := _customer(2)
	assert_eq(_request(), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_request(2), NetworkedEntity.Result.COOLDOWN)
	await RealTime.wait(get_tree(), 1.05)
	assert_true(_stand.can_use(second))
	assert_eq(_request(2), NetworkedEntity.Result.DENIED, "No inventory means no delivery")
	assert_eq(_request(), NetworkedEntity.Result.ACCEPTED)
	_stand.get_node("NetworkedEntity")._on_session_changed(Network.Mode.OFFLINE)
	assert_eq(_request(), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_hand.inventory().backpack.count("wendys_burger"), 2)


func test_burger_eats_once_heals_and_preserves_other_food() -> void:
	var combat := Combat.new()
	add_child_autofree(combat)
	combat.apply_damage(1, 90.0, 2)
	_request()
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")
	assert_eq(combat.health_for(1), Combat.MAX_HEALTH)
	_hand.request_primary_action()
	assert_eq(_hand.net_item_id, "")
	assert_eq(ItemCatalog.find("kebab").heal_amount, 100.0)
	assert_eq(ItemCatalog.find("poke_bowl").heal_amount, 100.0)


func test_catalog_view_ground_clearance_and_late_join_hand_snapshot() -> void:
	_request()
	var late := _make_hand(9)
	late.net_item_id = _hand.net_item_id
	var sync := late.get_node("Sync") as MultiplayerSynchronizer
	assert_eq(sync.get_multiplayer_authority(), 1)
	assert_true(sync.replication_config.property_get_spawn(NodePath(".:net_item_id")))
	var view := ItemCatalog.create_view(late.net_item_id)
	add_child_autofree(view)
	assert_true(view.has_node("Grip"))
	assert_true(view.has_node("SquarePatty"))
	var bottom := view.get_node("BottomBun") as MeshInstance3D
	var mesh := bottom.mesh as CylinderMesh
	assert_almost_eq(
		bottom.position.y - mesh.height * 0.5,
		-ItemCatalog.find("wendys_burger").ground_clearance,
		0.0001
	)


func _request(peer := 1) -> NetworkedEntity.Result:
	return _stand.get_node("NetworkedEntity")._evaluate(peer, &"use", {})


func _customer(peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.name = str(peer)
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	player.set_physics_process(false)
	player.net_position = Vector3(0, 1, 1.7)
	return player


func _make_hand(peer: int) -> Hand:
	var hand := HAND.instantiate() as Hand
	hand.peer_id = peer
	add_child_autofree(hand)
	return hand
