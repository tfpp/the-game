extends GutTest

const SmecklesScene := preload("res://features/smeckles/feature.tscn")

var _smeckles: Smeckles


func before_each() -> void:
	_smeckles = SmecklesScene.instantiate() as Smeckles
	add_child_autofree(_smeckles)


func test_unknown_peer_has_zero_balance() -> void:
	assert_eq(_smeckles.balance_for(1), 0)


func test_grant_credits_the_peer_and_accumulates() -> void:
	_smeckles.grant(1, 5)
	assert_eq(_smeckles.balance_for(1), 5)
	_smeckles.grant(1, 3)
	assert_eq(_smeckles.balance_for(1), 8)


func test_grant_keeps_separate_balances_per_peer() -> void:
	_smeckles.grant(1, 5)
	_smeckles.grant(2, 1)
	assert_eq(_smeckles.balance_for(1), 5)
	assert_eq(_smeckles.balance_for(2), 1)


func test_places_three_pickups_in_the_world() -> void:
	var pickups := 0
	for child: Node in _smeckles.get_children():
		if child is SmecklePickup:
			pickups += 1
	assert_eq(pickups, 3)
