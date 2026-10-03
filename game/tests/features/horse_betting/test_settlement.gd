extends GutTest

const SCENE := preload("res://features/horse_betting/feature.tscn")
var race: HorseBetting
var wallet: FlakyWallet
var ticket_owner: Node


class FlakyWallet:
	extends PlayerMoney
	var ids: Array[String] = []
	var calls: Array[Array] = []

	func settle_roulette(
		peer: int, account: int, id: String, wager: int, payout: int
	) -> Dictionary:
		ids.append(id)
		calls.append([peer, account, wager, payout])
		if ids.size() < 3:
			return {"error": "Lost reply"}
		balances[peer] = int(balances.get(peer, 2000)) - wager + payout
		return {"balance": balances[peer]}


func before_each() -> void:
	wallet = FlakyWallet.new()
	add_child_autofree(wallet)
	wallet.set_process(false)
	wallet.balances = {2: 2000}
	race = SCENE.instantiate() as HorseBetting
	add_child_autofree(race)
	race.set_process(false)
	ticket_owner = Node.new()
	add_child_autofree(ticket_owner)
	var next := race.state.duplicate(true)
	next["phase"] = "result"
	next["round"] = 1
	next["results"] = {2: "Settling…"}
	race.state = next


func ticket(account: int = 0) -> Dictionary:
	return {"horse": 0, "stake": 100, "account": account, "player": ticket_owner, "id": "test-id"}


func test_unknown_reply_retries_same_operation_and_blocks_next_round() -> void:
	race._locked[2] = ticket()
	race._settle(2, race._locked[2], 0)
	race._process(8)
	assert_eq(race.state["phase"], "result", "unresolved settlement blocks new tickets")
	await wait_seconds(1.7)
	assert_eq(wallet.ids, ["test-id", "test-id", "test-id"])
	assert_eq(wallet.balances[2], 2300, "one successful settlement")
	assert_true(race._locked.is_empty())
	assert_eq(race.state["results"][2], "Won $4.00")
	race._process(0.1)
	assert_eq(race.state["phase"], "idle")


func test_session_change_invalidates_retry_callback() -> void:
	race._locked[2] = ticket()
	race._settle(2, race._locked[2], 0)
	race._reset(Network.Mode.OFFLINE)
	await wait_seconds(0.7)
	assert_eq(wallet.ids.size(), 1, "no stale settlement retry in the next session")
	assert_eq(race.state, HorseBetting.initial_state())
	assert_eq(wallet.balances[2], 2000)


func test_locked_account_ticket_keeps_captured_account_after_disconnect() -> void:
	race._locked[2] = ticket(77)
	ticket_owner.free()
	race._settle(2, race._locked[2], 1)
	await wait_seconds(1.7)
	assert_eq(wallet.calls, [[2, 77, 100, 0], [2, 77, 100, 0], [2, 77, 100, 0]])
	assert_eq(race.state["results"][2], "Lost ticket")


func test_disconnected_temporary_ticket_never_pays_replacement_peer() -> void:
	race._locked[2] = ticket()
	ticket_owner.free()
	race._settle(2, race._locked[2], 0)
	assert_true(wallet.ids.is_empty())
	assert_eq(wallet.balances[2], 2000)
	assert_true(race._locked.is_empty())
