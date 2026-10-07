extends GutTest
## Exercise uncertain and delayed receipts through the actual door settlement path.

const DOOR := preload("res://features/hotel_annex/guest_door.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _door: HotelGuestDoor
var _wallet: ReceiptWallet
var _player: Player


class ReceiptWallet:
	extends PlayerMoney
	signal finish
	var delayed := false
	var calls: Array[Dictionary] = []
	var response := {"error": "Connection lost"}

	func charge(peer: int, id: String, amount_cents: int) -> Dictionary:
		calls.append({"peer": peer, "id": id, "amount": amount_cents})
		if delayed:
			await finish
		return response


func before_each() -> void:
	_door = DOOR.instantiate()
	add_child_autofree(_door)
	_door.set_physics_process(false)
	_wallet = ReceiptWallet.new()
	add_child_autofree(_wallet)
	_wallet.set_process(false)
	_player = PLAYER.instantiate()
	_player.display_name = "Receipt resident"
	_player.net_position = Vector3(0, 1, -1.5)
	add_child_autofree(_player)
	_player.set_physics_process(false)


func _request(operation: String) -> NetworkedEntity.Result:
	var action: NetworkedEntity.Action = _door._entity._actions[&"manage"]
	action.next_msec = 0
	return _door._entity._evaluate(1, &"manage", {"operation": operation})


func test_uncertain_payment_locks_choice_and_reuses_exact_receipt() -> void:
	assert_eq(_request("rent"), NetworkedEntity.Result.ACCEPTED)
	await wait_process_frames(2)
	assert_eq(_door.occupant, "")
	assert_eq(_door.reservation, "Receipt resident")
	assert_false(_door._pending.is_empty())
	assert_eq(_request("buy"), NetworkedEntity.Result.DENIED)
	var receipt: Dictionary = _wallet.calls[0].duplicate()
	_wallet.response = {"balance": 1000}
	assert_eq(_request("rent"), NetworkedEntity.Result.ACCEPTED)
	await wait_process_frames(2)
	assert_eq(_wallet.calls[1], receipt)
	assert_eq(_door.occupant, "Receipt resident")
	assert_eq(_door.reservation, "")
	assert_eq(_request("rent"), NetworkedEntity.Result.DENIED)


func test_delayed_payment_blocks_duplicate_then_mode_change_prevents_stale_grant() -> void:
	_wallet.delayed = true
	_request("buy")
	await wait_process_frames(2)
	assert_true(_door._paying)
	assert_eq(_request("buy"), NetworkedEntity.Result.DENIED)
	_door._reset(Network.Mode.OFFLINE)
	_wallet.response = {"balance": 10000}
	_wallet.finish.emit()
	await wait_process_frames(2)
	assert_eq(_door.occupant, "")
	assert_eq(_door.reservation, "")
	assert_false(_door._paying)


func test_disconnect_before_deferred_charge_does_not_spend() -> void:
	_request("rent")
	_player.free()
	await wait_process_frames(2)
	assert_true(_wallet.calls.is_empty())
	assert_true(_door._pending.is_empty())
	assert_false(_door._paying)


func test_terminal_rejection_releases_payment_reservation() -> void:
	_wallet.response = {"error": "Rejected", "rejected": true}
	_request("buy")
	await wait_process_frames(2)
	assert_true(_door._pending.is_empty())
	assert_eq(_door.reservation, "")
	assert_eq(_request("rent"), NetworkedEntity.Result.ACCEPTED)
	await wait_process_frames(2)
