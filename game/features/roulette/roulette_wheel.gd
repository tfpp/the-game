class_name RouletteWheel
extends RefCounted
## Server-only wheel: each spin is an independent, uniform pocket draw.

const POCKET_COUNT := 37
const RED_NUMBERS: Array[int] = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

var _rng := RandomNumberGenerator.new()


func next_result() -> int:
	return _rng.randi_range(0, POCKET_COUNT - 1)


## European wheel colors: 0 is green, the rest split red/black.
static func color_for(number: int) -> String:
	if number == 0:
		return "green"
	return "red" if RED_NUMBERS.has(number) else "black"
