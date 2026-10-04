extends GutTest

const HAND := preload("res://features/holdables/hand.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _hand: Hand
var _player: Player
var _shots := 0


func before_each() -> void:
	_shots = 0
	_player = PLAYER.instantiate() as Player
	_player.name = "1"
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_hand = HAND.instantiate() as Hand
	_hand.peer_id = 1
	add_child_autofree(_hand)
	_hand.set_process(false)
	_hand.net_item_id = "pistol"
	_hand.inventory().collect("ammo:pistol:20")
	_hand.pistol.advance(0.0)
	_hand.fired.connect(func(_id: String) -> void: _shots += 1)


func _shoot() -> void:
	_hand._fire_cooldown = 0.0
	_hand.request_primary_action()


func test_seven_shots_then_reload_blocks_firing_and_spends_ammo_once() -> void:
	for shot: int in 8:
		_shoot()
	assert_eq(_shots, 7)
	assert_eq(_hand.pistol.loaded(), 0)
	assert_eq(_hand.inventory().ammo_for("pistol"), 13)
	assert_eq(_hand.pistol.entity._evaluate(1, &"reload", {}), NetworkedEntity.Result.ACCEPTED)
	_shoot()
	assert_eq(_shots, 7)
	_hand.pistol.advance(1.0)
	assert_true(_hand.pistol.active())
	assert_eq(_hand.pistol.loaded(), 0)
	_hand.pistol.advance(.66)
	assert_false(_hand.pistol.active())
	assert_eq(_hand.pistol.loaded(), 7)
	assert_eq(_hand.inventory().ammo_for("pistol"), 13)
	_shoot()
	assert_eq(_shots, 8)
	assert_eq(_hand.pistol.loaded(), 6)
	assert_eq(_hand.inventory().ammo_for("pistol"), 12)


func test_foreign_payload_loading_and_full_magazine_requests_are_denied() -> void:
	assert_eq(_hand.pistol.entity._evaluate(1, &"reload", {}), NetworkedEntity.Result.DENIED)
	_shoot()
	assert_eq(_hand.pistol.entity._evaluate(2, &"reload", {}), NetworkedEntity.Result.DENIED)
	assert_eq(
		_hand.pistol.entity._evaluate(1, &"reload", {"rounds": 7}), NetworkedEntity.Result.DENIED
	)
	_hand.inventory().loading = true
	assert_eq(_hand.pistol.entity._evaluate(1, &"reload", {}), NetworkedEntity.Result.DENIED)
	assert_false(_hand.pistol.active())
	assert_eq(_hand.pistol.loaded(), 6)


func test_holster_cancels_reload_and_cannot_refill_magazine() -> void:
	_shoot()
	assert_eq(_hand.pistol.entity._evaluate(1, &"reload", {}), NetworkedEntity.Result.ACCEPTED)
	_hand.net_item_id = "banana"
	_hand.pistol.advance(2.0)
	assert_false(_hand.pistol.active())
	_hand.net_item_id = "pistol"
	_hand.pistol.advance(2.0)
	assert_eq(_hand.pistol.loaded(), 6)
	assert_eq(_hand.inventory().ammo_for("pistol"), 19)


func test_partial_reload_ammo_removal_and_death_cancellation() -> void:
	_hand.inventory().backpack = PackedStringArray(["ammo:pistol:3", "", "", "", "", "", "", ""])
	_hand.pistol.advance(0.0)
	assert_eq(_hand.pistol.loaded(), 3)
	_shoot()
	assert_eq(_hand.pistol.loaded(), 2)
	_hand.inventory().backpack = PackedStringArray(["ammo:pistol:5", "", "", "", "", "", "", ""])
	assert_eq(_hand.pistol.entity._evaluate(1, &"reload", {}), NetworkedEntity.Result.ACCEPTED)
	_hand.pistol.advance(2.0)
	assert_eq(_hand.pistol.loaded(), 5)
	_shoot()
	_hand.pistol.entity._evaluate(1, &"reload", {})
	_hand.pistol._died(1, 2)
	assert_false(_hand.pistol.active())
	assert_eq(_hand.pistol.loaded(), 4)
	assert_eq(_hand.inventory().ammo_for("pistol"), 4)
