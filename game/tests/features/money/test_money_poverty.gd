extends GutTest
## Wealth ranking and the poverty flies cosmetic (features/money/money.gd,
## features/money/poverty_flies.gd).

const PLAYER := preload("res://core/player/player.tscn")
const MoneyScene := preload("res://features/money/feature.tscn")

var _money: PlayerMoney


func before_each() -> void:
	_money = MoneyScene.instantiate() as PlayerMoney
	add_child_autofree(_money)
	_money.set_process(false)


func after_each() -> void:
	Network.peer_accounts.erase(2)
	Network.peer_accounts.erase(3)


## Registers `peer` the same way a connected client would, so `PlayerMoney`'s stale-wallet
## cleanup (money.gd, peers absent from `Network.peer_accounts` get pruned) leaves it alone.
func _remote_player(peer: int) -> Player:
	var player := PLAYER.instantiate() as Player
	player.set_multiplayer_authority(peer)
	add_child_autofree(player)
	Network.peer_accounts[peer] = {"account_id": 0}
	return player


func test_poorest_peers_needs_at_least_two_known_wallets() -> void:
	assert_eq(PlayerMoney.poorest_peers({}), {})
	assert_eq(PlayerMoney.poorest_peers({1: 500}), {})


func test_poorest_peers_flags_the_bottom_80_percent_by_balance() -> void:
	var balances := {1: 500, 2: 100, 3: 300, 4: 200, 5: 400}
	var poorest := PlayerMoney.poorest_peers(balances)
	assert_eq(poorest.size(), 4)
	for peer: int in [2, 3, 4, 5]:
		assert_true(poorest.has(peer), "peer %d should be flagged" % peer)
	assert_false(poorest.has(1), "the richest peer should not be flagged")


func test_poorest_peers_breaks_ties_by_peer_id() -> void:
	var balances := {5: 100, 2: 100, 8: 100, 1: 500}
	var poorest := PlayerMoney.poorest_peers(balances)
	assert_eq(poorest.size(), 3)
	for peer: int in [2, 5, 8]:
		assert_true(poorest.has(peer), "peer %d should be flagged" % peer)
	assert_false(poorest.has(1))


func test_flies_appear_on_the_poorest_and_not_the_richest() -> void:
	var poor := _remote_player(2)
	var rich := _remote_player(3)
	_money.balances = {2: 100, 3: 100000}
	_money._process(0.0)
	assert_not_null(poor.get_node_or_null("PovertyFlies"))
	assert_null(rich.get_node_or_null("PovertyFlies"))


func test_a_lone_remote_player_never_gets_flies() -> void:
	var solo := _remote_player(2)
	_money.balances = {2: 100}
	_money._process(0.0)
	assert_null(solo.get_node_or_null("PovertyFlies"))


func test_flies_are_removed_once_the_wealth_ranking_changes() -> void:
	var poor := _remote_player(2)
	var rich := _remote_player(3)
	_money.balances = {2: 100, 3: 100000}
	_money._process(0.0)
	assert_not_null(poor.get_node_or_null("PovertyFlies"))
	_money.balances = {2: 100000, 3: 100}
	_money._process(0.0)
	await wait_frames(1)
	assert_null(poor.get_node_or_null("PovertyFlies"))
	assert_not_null(rich.get_node_or_null("PovertyFlies"))


func test_local_player_is_skipped_but_does_not_block_remote_flies() -> void:
	var local := PLAYER.instantiate() as Player
	add_child_autofree(local)
	var remote := _remote_player(2)
	_money.balances = {multiplayer.get_unique_id(): 100000, 2: 100}
	_money._process(0.0)
	assert_null(local.get_node_or_null("PovertyFlies"))
	assert_not_null(remote.get_node_or_null("PovertyFlies"))
