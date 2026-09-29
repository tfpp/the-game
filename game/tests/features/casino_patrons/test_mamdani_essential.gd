extends GutTest
## Mamdani is essential: guns knock him out instead of killing him, and talking to
## him pays subway fare into the shared wallet once an hour. Single-process, so
## peer 1 is the server and the talking player.

const PatronScene := preload("res://features/casino_patrons/patron.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _patron: CasinoPatron
var _player: Player
var _wallet: PlayerMoney


func before_each() -> void:
	_wallet = PlayerMoney.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_wallet.balances = {1: 2000}
	_player = PlayerScene.instantiate() as Player
	_player.name = "1"
	_player.set_multiplayer_authority(1)
	add_child_autofree(_player)
	_patron = _make(PatronModel.MAMDANI_LOOK)
	await get_tree().physics_frame
	_patron.set_physics_process(false)
	_player.net_position = _patron.global_position + Vector3(0, 0, 1.5)
	_player.global_position = _player.net_position


func _make(look: int) -> CasinoPatron:
	var patron := PatronScene.instantiate() as CasinoPatron
	patron.route = [Vector3(0, 0, 0), Vector3(0, 0, -10)] as Array[Vector3]
	patron.look = look
	add_child_autofree(patron)
	return patron


func _step(seconds: float) -> void:
	var dt := 1.0 / 30.0
	for _i: int in int(seconds / dt):
		_patron._physics_process(dt)
		_patron._process(dt)


func test_fare_cooldown_math() -> void:
	assert_eq(PatronMath.fare_wait_s(-1.0, 10.0), 0.0)
	assert_eq(PatronMath.fare_wait_s(100.0, 100.0), PatronMath.FARE_COOLDOWN_S)
	assert_eq(PatronMath.fare_wait_s(0.0, PatronMath.FARE_COOLDOWN_S + 1.0), 0.0)
	assert_eq(PatronMath.wait_text(3599.0), "60 min")
	assert_eq(PatronMath.wait_text(5.0), "1 min")


func test_a_gunshot_knocks_him_out_and_he_wakes_up() -> void:
	_patron.take_hit(2)
	assert_true(_patron.net_alive, "essential: never dies")
	assert_true(_patron.net_ragdoll)
	_step(PatronMath.KNOCKOUT_S - 0.5)
	assert_true(_patron.net_ragdoll, "still out a few moments later")
	_step(1.0)
	assert_false(_patron.net_ragdoll, "wakes up")
	assert_true(_patron.net_alive)


func test_other_patrons_still_die() -> void:
	var other := _make(1)
	await get_tree().physics_frame
	other.set_physics_process(false)
	other.take_hit(2)
	assert_false(other.net_alive)
	assert_false(other.is_in_group(&"interactables"))


func test_talking_pays_fare_once_an_hour() -> void:
	assert_true(_patron.is_in_group(&"interactables"))
	assert_true(_patron.can_use(_player))
	assert_true(_patron._give_fare(_player))
	await wait_frames(2)
	assert_eq(int(_wallet.balances[1]), 2000 + PlayerMoney.COIN_CREDIT_CENTS)
	assert_true(_patron._give_fare(_player))
	await wait_frames(2)
	assert_eq(int(_wallet.balances[1]), 2000 + PlayerMoney.COIN_CREDIT_CENTS, "cooldown")
	_patron._fare_claims["peer:1"] -= PatronMath.FARE_COOLDOWN_S
	_patron._give_fare(_player)
	await wait_frames(2)
	assert_eq(int(_wallet.balances[1]), 2000 + 2 * PlayerMoney.COIN_CREDIT_CENTS)


func test_cannot_talk_while_knocked_out_or_out_of_range() -> void:
	_patron.take_hit(2)
	assert_false(_patron.can_use(_player))
	_step(PatronMath.KNOCKOUT_S + 0.5)
	assert_true(_patron.can_use(_player))
	_player.net_position = _patron.global_position + Vector3(0, 0, 10)
	assert_false(_patron.can_use(_player))


func test_talk_request_goes_through_the_entity() -> void:
	_patron.use()
	await wait_frames(3)
	assert_eq(int(_wallet.balances[1]), 2000 + PlayerMoney.COIN_CREDIT_CENTS)
	var speech := _patron.get_node("Speech") as Label3D
	assert_true(speech.visible)
	assert_string_contains(speech.text, "subway")
