class_name RouletteWheel
extends RefCounted
## Server-only wheel: each spin is an independent, uniform pocket draw.

## American wheel: 0-36 plus a double zero, stored as DOUBLE_ZERO.
const POCKET_COUNT := 38
const DOUBLE_ZERO := 37
const RED_NUMBERS: Array[int] = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

var _rng := RandomNumberGenerator.new()


func next_result() -> int:
	return _rng.randi_range(0, POCKET_COUNT - 1)


## American wheel colors: 0 and 00 are green, 1-36 split red/black.
static func color_for(number: int) -> String:
	if number == 0 or number == DOUBLE_ZERO:
		return "green"
	return "red" if RED_NUMBERS.has(number) else "black"


## Player-facing pocket name: "00" for the double zero, otherwise the number.
static func label_for(number: int) -> String:
	return "00" if number == DOUBLE_ZERO else str(number)
