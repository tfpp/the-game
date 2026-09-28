extends GutTest

const PickupScene := preload("res://features/smeckles/pickup.tscn")
const PlayerScene := preload("res://core/player/player.tscn")

var _smeckles: Smeckles
var _pickup: SmecklePickup


func before_each() -> void:
	_smeckles = Smeckles.new()
	add_child_autofree(_smeckles)
	_pickup = PickupScene.instantiate() as SmecklePickup
	_smeckles.add_child(_pickup)
	_pickup.set_process(false)


func _player_at(position: Vector3, authority: int = 1) -> Player:
	var player := PlayerScene.instantiate() as Player
	player.set_multiplayer_authority(authority)
	player.position = position
	player.net_position = position
	add_child_autofree(player)
	return player


func test_nearby_player_can_use_an_available_pickup() -> void:
	var player := _player_at(Vector3.ZERO)
	assert_true(_pickup.can_use(player))


func test_far_player_cannot_use_the_pickup() -> void:
	var player := _player_at(Vector3(10, 0, 0))
	assert_false(_pickup.can_use(player))


func test_unavailable_pickup_cannot_be_used() -> void:
	var player := _player_at(Vector3.ZERO)
	_pickup.available = false
	assert_false(_pickup.can_use(player))


func test_collecting_grants_a_reward_and_disables_the_pickup() -> void:
	_player_at(Vector3.ZERO)
	_pickup.request_collect()
	assert_false(_pickup.available)
	assert_between(_smeckles.balance_for(1), SmecklePickup.REWARD_MIN, SmecklePickup.REWARD_MAX)


func test_unknown_player_cannot_collect() -> void:
	_pickup.request_collect()
	assert_true(_pickup.available)
	assert_eq(_smeckles.balance_for(1), 0)


func test_second_collect_is_ignored_until_cooldown() -> void:
	_player_at(Vector3.ZERO)
	_pickup.request_collect()
	var first_balance := _smeckles.balance_for(1)
	_pickup.request_collect()
	assert_eq(_smeckles.balance_for(1), first_balance)


func test_cooldown_reopens_the_pickup() -> void:
	_player_at(Vector3.ZERO)
	_pickup.request_collect()
	assert_false(_pickup.available)
	_pickup._on_cooldown_finished()
	assert_true(_pickup.available)
