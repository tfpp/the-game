extends GutTest
## Buying guns off the pawn shop wall: the shared wallet pays, the inventory
## receives, and forged, far-away or duplicate requests change nothing.

const GUN := preload("res://features/pawn_shop/wall_gun.tscn")
const PLAYER := preload("res://core/player/player.tscn")
const HAND := preload("res://features/holdables/hand.tscn")

var _gun: WallGun
var _player: Player
var _hand: Hand
var _wallet: PlayerMoney
var _drops: DropRecorder


class DropRecorder:
	extends Node
	var items: Array[String] = []

	func spawn_thrown_item(id: String, _from: Vector3, _to: Vector3) -> void:
		items.append(id)


class SlowWallet:
	extends PlayerMoney
	signal complete
	var calls := 0

	func charge(_peer: int, _id: String, amount: int) -> Dictionary:
		calls += 1
		await complete
		return {"balance": 10000 - amount}


func before_each() -> void:
	_gun = GUN.instantiate() as WallGun
	_gun.item_id = "shotgun"
	_gun.price_cents = 1  # Ready must override stale scene prices from the trusted catalog.
	add_child_autofree(_gun)
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.net_position = Vector3(0, -0.9, 1.2)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 1200000}
	_drops = DropRecorder.new()
	_drops.add_to_group(&"holdables_root")
	add_child_autofree(_drops)


func test_shows_the_gun_and_its_price() -> void:
	assert_not_null(_gun.get_node_or_null("View"))
	var tag := _gun.get_node("PriceTag") as Label3D
	assert_string_contains(tag.text, "$5,550.00")
	assert_eq(_gun.interaction_text(), "Buy Shotgun — $5,550.00")


func test_buying_charges_the_wallet_and_equips_the_gun() -> void:
	assert_eq(_request(1), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 645000)
	assert_eq(_hand.net_item_id, "shotgun")
	assert_eq(_hand.inventory().ammo_for("shotgun"), 8)
	# Unlimited stock: a second purchase goes into the backpack.
	assert_eq(_request(1), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 90000)
	assert_eq(_hand.inventory().backpack.count("shotgun"), 1)


func test_cannot_afford_keeps_money_and_hands_empty() -> void:
	_wallet.balances = {1: 554999}
	_request(1)
	assert_eq(_wallet.balances[1], 554999)
	assert_eq(_hand.net_item_id, "")
	assert_true(_drops.items.is_empty())


func test_rejects_unknown_peer_payloads_and_distance() -> void:
	assert_eq(_gun.entity._evaluate(77, &"use", {}), NetworkedEntity.Result.DENIED)
	assert_eq(_gun.entity._evaluate(1, &"use", {"peer": 1}), NetworkedEntity.Result.DENIED)
	_player.net_position = Vector3(0, 0, 6)
	assert_eq(_request(1), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 1200000)


func test_full_bag_is_refused_before_paying() -> void:
	for index: int in 9:
		_hand.inventory().collect("banana")
	assert_eq(_request(1), NetworkedEntity.Result.DENIED)
	assert_eq(_wallet.balances[1], 1200000)


func test_pending_payment_blocks_a_double_purchase() -> void:
	var slow := _slow_wallet()
	_request(1)
	assert_eq(_request(1), NetworkedEntity.Result.DENIED)
	assert_eq(slow.calls, 1)
	slow.complete.emit()
	assert_eq(_hand.net_item_id, "shotgun")
	assert_true(_gun._busy.is_empty())


func test_bag_filling_during_payment_drops_the_paid_gun() -> void:
	var slow := _slow_wallet()
	_request(1)
	for index: int in 9:
		_hand.inventory().collect("banana")
	slow.complete.emit()
	assert_eq(_drops.items, ["shotgun", "ammo:shotgun:8"])


func test_session_reset_ignores_an_old_payment() -> void:
	var slow := _slow_wallet()
	_request(1)
	_gun.entity.session_reset.emit(Network.Mode.OFFLINE)
	slow.complete.emit()
	assert_eq(_hand.net_item_id, "")
	assert_true(_drops.items.is_empty())


func _request(peer: int) -> NetworkedEntity.Result:
	return _gun.entity._evaluate(peer, &"use", {})


func _slow_wallet() -> SlowWallet:
	_wallet.free()
	var slow := SlowWallet.new()
	add_child_autofree(slow)
	slow.set_process(false)
	slow.balances = {1: 10000}
	_wallet = slow
	return slow


func test_top_hat_sells_for_ten_thousand_and_goes_on_the_head() -> void:
	_gun.item_id = ClothingCatalog.TOP_HAT
	_gun.price_cents = 1000000
	_wallet.balances = {1: 1000000}
	assert_eq(_gun.interaction_text(), "Buy Top hat — %s" % PlayerMoney.format_money(1000000))
	assert_eq(_request(1), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 0)
	assert_eq(_hand.inventory().hat, ClothingCatalog.TOP_HAT)
	assert_eq(_hand.net_item_id, "")
	assert_eq(_request(1), NetworkedEntity.Result.ACCEPTED)
	assert_eq(_wallet.balances[1], 0, "Can't afford a second hat")
	assert_false(_hand.inventory().backpack.has(ClothingCatalog.TOP_HAT))
