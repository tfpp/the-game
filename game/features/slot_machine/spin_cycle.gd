class_name SlotSpinCycle
extends RefCounted
## Server-only shuffled bags: exactly four wins and one loss per five accepted spins.

const SYMBOL_COUNT := 5
var _bag: Array[bool] = []
var _rng := RandomNumberGenerator.new()


func next_result() -> Array[int]:
	if _bag.is_empty():
		_bag.assign([true, true, true, true, false])
		for index: int in range(_bag.size() - 1, 0, -1):
			var other := _rng.randi_range(0, index)
			var value := _bag[index]
			_bag[index] = _bag[other]
			_bag[other] = value
	var symbol := _rng.randi_range(0, SYMBOL_COUNT - 1)
	if _bag.pop_back():
		return [symbol, symbol, symbol]
	# A loss can never accidentally contain three matching symbols.
	return [symbol, symbol, (symbol + _rng.randi_range(1, SYMBOL_COUNT - 1)) % SYMBOL_COUNT]


static func is_win(reels: Array[int]) -> bool:
	return reels.size() == 3 and reels[0] == reels[1] and reels[1] == reels[2]
