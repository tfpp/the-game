class_name SlotSpinCycle
extends RefCounted
## Independent, uniform reels. Used for temporary offline/dev wallets only;
## authenticated spins are generated and settled by the accounts API.

const SYMBOL_COUNT := 5
const PRIZES: Array[int] = [3000, 2000, 1000, 1500, 2500]
var _rng := RandomNumberGenerator.new()


func next_result() -> Array[int]:
	return [
		_rng.randi_range(0, SYMBOL_COUNT - 1),
		_rng.randi_range(0, SYMBOL_COUNT - 1),
		_rng.randi_range(0, SYMBOL_COUNT - 1)
	]


static func is_win(reels: Array[int]) -> bool:
	return reels.size() == 3 and reels[0] == reels[1] and reels[1] == reels[2]


## Prizes scale with wager_cents so any buy-in keeps the same 80% return.
static func payout(reels: Array[int], wager_cents: int = 100) -> int:
	if not is_win(reels) or reels[0] < 0 or reels[0] >= SYMBOL_COUNT:
		return 0
	return PRIZES[reels[0]] * wager_cents / 100
