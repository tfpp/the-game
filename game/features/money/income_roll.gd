class_name IncomeRoll
extends RefCounted
## Integer-only heavy tail: $1-$9, then independently promote x10 with odds 1/20.
## Stop only when the next decade cannot fit the existing signed 64-bit wallet.

const MAX_CENTS := 9223372036854775807
const DEFAULT_UNITS := 30000


static func sample(units: int, draw: Callable) -> int:
	var cents: int = (int(draw.call(9)) + 1) * 100
	while cents <= MAX_CENTS / 10 and int(draw.call(20)) == 0:
		cents *= 10
	# Split before multiplying to avoid overflow; units is a weighted minute rate.
	return (cents / DEFAULT_UNITS) * units + (cents % DEFAULT_UNITS) * units / DEFAULT_UNITS
