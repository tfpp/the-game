class_name SlotSpinCycle
extends RefCounted
## Uniform unblessed reels, with matching blessed odds for offline/dev wallets;
## authenticated spins are generated and settled by the accounts API.

const SYMBOL_COUNT := 5
const PRIZES: Array[int] = [3000, 2000, 1000, 1500, 2500]
var _rng := RandomNumberGenerator.new()


func next_result() -> Array[int]:
	return blessed_result(0)


## Each blessing adds 200% of the base chance (8 percentage points), capped at five.
func blessed_result(blessings: int) -> Array[int]:
	return result_for_ticket(_rng.randi_range(0, 124), blessings)


## A uniform ticket preserves all 125 unblessed outcomes and equal winning symbols.
static func result_for_ticket(ticket: int, blessings: int) -> Array[int]:
	if ticket < 5 + 10 * clampi(blessings, 0, 5):
		var symbol := ticket % SYMBOL_COUNT
		return [symbol, symbol, symbol]
	# Map the remaining tickets onto non-triples, skipping indices 0,31,62,93,124.
	var losing := ticket - 5
	@warning_ignore("integer_division")
	var index := losing + 1 + losing / 30
	@warning_ignore("integer_division")
	return [index / 25, (index / 5) % SYMBOL_COUNT, index % SYMBOL_COUNT]


static func win_chance(blessings: int) -> float:
	return (5.0 + 10.0 * clampi(blessings, 0, 5)) / 125.0


static func is_win(reels: Array[int]) -> bool:
	return reels.size() == 3 and reels[0] == reels[1] and reels[1] == reels[2]


## Prizes scale with wager_cents so any buy-in keeps the same 80% return.
static func payout(reels: Array[int], wager_cents: int = 100) -> int:
	if not is_win(reels) or reels[0] < 0 or reels[0] >= SYMBOL_COUNT:
		return 0
	return PRIZES[reels[0]] * wager_cents / 100
