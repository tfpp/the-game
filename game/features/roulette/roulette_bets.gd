class_name RouletteBets
extends RefCounted
## American roulette bet spots, payouts and hit-testing on the painted table layout.
## Pure static rules shared by the server (validation, settlement) and clients (UI).
##
## Positions are texture pixels of `roulette_layout_albedo.png` (256x128), which the
## model maps across the table-local rectangle LAYOUT_MIN..LAYOUT_MAX at LAYOUT_Y.
## Spot keys are the covered pockets, sorted and joined with "-" (00 is 37), e.g.
## "17", "17-20", "0-1-2-3-37"; outside bets use names such as "red" or "dozen2".
##
## Odds follow Barboianu's model (https://probability.infarom.ro/roulette.html): a
## simple bet covering n of the 38 pockets wins with probability n/38 and pays
## k = 36/n - 1 to 1, so every bet carries the same 2/38 house edge. The page's
## tables omit the American five-number top line (0-00-1-2-3), where 36/5 - 1 = 6.2
## is not a whole payout; casinos round it down to 6 to 1, which is what it pays here
## (a 3/38 house edge, the one worse bet on the layout).

## Chip values in cents, matching assets/casino_chips/models/chip_<dollars>.glb.
const DENOMINATIONS: Array[int] = [100, 500, 5000, 10000, 50000, 100000, 500000, 2500000]
## Placements one player may have on the table in a round; bounds replicated state.
const MAX_PLACEMENTS := 60

const LAYOUT_MIN := Vector2(-0.3, -0.4)
const LAYOUT_MAX := Vector2(1.3, 0.4)
const LAYOUT_Y := 0.86125
const TEXTURE_SIZE := Vector2(256, 128)

## Number grid: 12 columns of three pockets between these pixel edges.
const GRID_LEFT := 23.0
const GRID_RIGHT := 231.0
const GRID_TOP := 52.0
const ROW_HEIGHT := 21.0
const GRID_BOTTOM := 115.0
const ZERO_LEFT := 4.0
const ZERO_SPLIT_Y := 83.5
const COLUMN_BET_RIGHT := 252.0
const OUTSIDE_LEFT := 11.0
const OUTSIDE_RIGHT := 246.0
const EVEN_MONEY_TOP := 12.0
const DOZEN_TOP := 33.0
## Line bets (splits, corners, streets) must be this many times closer than a pocket.
const LINE_WEIGHT := 2.5
## Clicks just above the grid's top edge still reach streets and six lines.
const LINE_REACH := 2.5

const EVEN_MONEY: Array[String] = ["low", "even", "red", "black", "odd", "high"]

static var _spots: Dictionary = {}


## Every valid spot: key -> {"numbers": Array[int], "anchor": Vector2 (pixels), "kind"}.
static func spots() -> Dictionary:
	if _spots.is_empty():
		_spots = _build()
	return _spots


static func is_valid(key: String) -> bool:
	return spots().has(key)


static func numbers(key: String) -> Array[int]:
	var spot: Dictionary = spots().get(key, {})
	var result: Array[int] = []
	result.assign(spot.get("numbers", []))
	return result


## "x to 1" winnings for a winning bet on `key` (stake returned on top): 36/n - 1,
## rounded down for the five-number top line (6.2 -> 6).
static func payout_to_one(key: String) -> int:
	var count := numbers(key).size()
	return 36 / count - 1 if count > 0 else 0


## Chance that `key` wins one spin: covered pockets / 38.
static func probability(key: String) -> float:
	return numbers(key).size() / float(RouletteWheel.POCKET_COUNT)


## Odds against `key` winning, (38 - n) : n, as losses per win.
static func odds_against(key: String) -> float:
	var count := numbers(key).size()
	return (RouletteWheel.POCKET_COUNT - count) / float(count) if count > 0 else 0.0


## Expected profit per unit staked; -2/38 for every bet but the top line (-3/38).
static func expected_return(key: String) -> float:
	var win := probability(key)
	return win * payout_to_one(key) - (1.0 - win)


## "5.26% (18 : 1)", truncated the way the source tables print them.
static func odds_text(key: String) -> String:
	var percent := floorf(probability(key) * 10000.0) / 100.0
	var odds := floorf(odds_against(key) * 10.0) / 10.0
	var odds_label := str(int(odds)) if is_equal_approx(odds, roundf(odds)) else "%.1f" % odds
	return "%.2f%% (%s : 1)" % [percent, odds_label]


## Returned to the player when `number` wins: stake plus winnings, or 0.
static func return_for(key: String, cents: int, number: int) -> int:
	return cents * (payout_to_one(key) + 1) if numbers(key).has(number) else 0


## Total wager and total return for a list of [key, cents] placements.
static func settle(placements: Array, number: int) -> Dictionary:
	var wager := 0
	var payout := 0
	for placement: Array in placements:
		wager += int(placement[1])
		payout += return_for(str(placement[0]), int(placement[1]), number)
	return {"wager": wager, "payout": payout}


static func total(placements: Array) -> int:
	var sum := 0
	for placement: Array in placements:
		sum += int(placement[1])
	return sum


## Adds each spot's placements together: key -> cents.
static func by_spot(placements: Array) -> Dictionary:
	var result := {}
	for placement: Array in placements:
		var key := str(placement[0])
		result[key] = int(result.get(key, 0)) + int(placement[1])
	return result


## Each spot's chips in the order they were placed, bottom of the stack first:
## key -> Array[int] of chip values.
static func stacks(placements: Array) -> Dictionary:
	var result := {}
	for placement: Array in placements:
		var key := str(placement[0])
		if not result.has(key):
			result[key] = [] as Array[int]
		(result[key] as Array[int]).append(int(placement[1]))
	return result


## Largest chips first, e.g. 5600 -> [5000, 500, 100].
static func chips_for(cents: int) -> Array[int]:
	var result: Array[int] = []
	var remaining := cents
	for index: int in range(DENOMINATIONS.size() - 1, -1, -1):
		while remaining >= DENOMINATIONS[index]:
			result.append(DENOMINATIONS[index])
			remaining -= DENOMINATIONS[index]
	return result


## Player-facing description, e.g. "Split 17 / 20 — pays 17 to 1".
static func describe(key: String) -> String:
	if not is_valid(key):
		return ""
	var names := {
		"low": "1 to 18",
		"high": "19 to 36",
		"even": "Even",
		"odd": "Odd",
		"red": "Red",
		"black": "Black",
		"dozen1": "1st 12",
		"dozen2": "2nd 12",
		"dozen3": "3rd 12",
		"column1": "Column 1, 4 … 34",
		"column2": "Column 2, 5 … 35",
		"column3": "Column 3, 6 … 36",
	}
	var label := str(names.get(key, ""))
	if label.is_empty():
		var pockets := PackedStringArray()
		for number: int in numbers(key):
			pockets.append(RouletteWheel.label_for(number))
		var kinds := {1: "Straight", 2: "Split", 3: "Street", 4: "Corner", 5: "Top line", 6: "Line"}
		label = "%s %s" % [kinds.get(pockets.size(), "Bet"), " / ".join(pockets)]
	return "%s — wins %s, pays %d to 1" % [label, odds_text(key), payout_to_one(key)]


## The spot under texture pixel `pixel`, or "" for none.
static func spot_at(pixel: Vector2) -> String:
	var x := pixel.x
	var y := pixel.y
	if y >= EVEN_MONEY_TOP and y < DOZEN_TOP and x >= OUTSIDE_LEFT and x < OUTSIDE_RIGHT:
		var index := int((x - OUTSIDE_LEFT) / ((OUTSIDE_RIGHT - OUTSIDE_LEFT) / 6.0))
		return EVEN_MONEY[mini(index, 5)]
	if y >= DOZEN_TOP and y < GRID_TOP - LINE_REACH and x >= OUTSIDE_LEFT and x < OUTSIDE_RIGHT:
		# The dozen dividers are painted at the 4th and 8th column lines, not thirds.
		if x < _column_x(4):
			return "dozen1"
		return "dozen2" if x < _column_x(8) else "dozen3"
	if y < GRID_TOP - LINE_REACH or y >= GRID_BOTTOM:
		return ""
	if x >= GRID_RIGHT and x < COLUMN_BET_RIGHT:
		if y < GRID_TOP:
			return ""
		return "column%d" % (clampi(int((y - GRID_TOP) / ROW_HEIGHT), 0, 2) + 1)
	if x < ZERO_LEFT or x >= GRID_RIGHT:
		return ""
	var best := ""
	var best_distance := INF
	for key: String in spots():
		var spot: Dictionary = spots()[key]
		if spot["kind"] != "inside":
			continue
		var at: Vector2 = spot["anchor"]
		var weight := 1.0 if (spot["numbers"] as Array).size() == 1 else LINE_WEIGHT
		var distance := at.distance_to(pixel) * weight
		if distance < best_distance:
			best_distance = distance
			best = key
	return best


## Table-local position of texture pixel `pixel` on the felt.
static func pixel_to_local(pixel: Vector2) -> Vector3:
	var uv := pixel / TEXTURE_SIZE
	return Vector3(
		lerpf(LAYOUT_MIN.x, LAYOUT_MAX.x, uv.x), LAYOUT_Y, lerpf(LAYOUT_MIN.y, LAYOUT_MAX.y, uv.y)
	)


## Texture pixel under table-local position `local` (x/z; y is ignored).
static func local_to_pixel(local: Vector3) -> Vector2:
	var uv := Vector2(
		inverse_lerp(LAYOUT_MIN.x, LAYOUT_MAX.x, local.x),
		inverse_lerp(LAYOUT_MIN.y, LAYOUT_MAX.y, local.z)
	)
	return uv * TEXTURE_SIZE


static func anchor(key: String) -> Vector2:
	var spot: Dictionary = spots().get(key, {})
	return spot.get("anchor", Vector2.ZERO)


static func _column_x(column: int) -> float:
	return GRID_LEFT + column * (GRID_RIGHT - GRID_LEFT) / 12.0


static func _row_y(row: float) -> float:
	return GRID_TOP + row * ROW_HEIGHT


static func _number(column: int, row: int) -> int:
	return column * 3 + row + 1


static func _add(
	result: Dictionary, covered: Array[int], at: Vector2, kind: String = "inside"
) -> void:
	var sorted := covered.duplicate()
	sorted.sort()
	var parts := PackedStringArray()
	for number: int in sorted:
		parts.append(str(number))
	var key := "-".join(parts)
	result[key] = {"numbers": sorted, "anchor": at, "kind": kind}


static func _add_named(result: Dictionary, key: String, covered: Array[int], at: Vector2) -> void:
	result[key] = {"numbers": covered, "anchor": at, "kind": "outside"}


static func _build() -> Dictionary:
	var result := {}
	var zero := RouletteWheel.DOUBLE_ZERO
	var zero_x := (ZERO_LEFT + GRID_LEFT) * 0.5
	_add(result, [0], Vector2(zero_x, (GRID_TOP + ZERO_SPLIT_Y) * 0.5))
	_add(result, [zero], Vector2(zero_x, (ZERO_SPLIT_Y + GRID_BOTTOM) * 0.5))
	_add(result, [0, zero], Vector2(zero_x, ZERO_SPLIT_Y))
	_add(result, [0, 1], Vector2(GRID_LEFT, _row_y(0.5)))
	_add(result, [0, 2], Vector2(GRID_LEFT, _row_y(1.25)))
	_add(result, [zero, 2], Vector2(GRID_LEFT, _row_y(1.75)))
	_add(result, [zero, 3], Vector2(GRID_LEFT, _row_y(2.5)))
	_add(result, [0, 1, 2], Vector2(GRID_LEFT, _row_y(1)))
	_add(result, [zero, 2, 3], Vector2(GRID_LEFT, _row_y(2)))
	_add(result, [0, zero, 1, 2, 3], Vector2(GRID_LEFT, GRID_TOP))
	for column: int in 12:
		var middle := (_column_x(column) + _column_x(column + 1)) * 0.5
		var street: Array[int] = [_number(column, 0), _number(column, 1), _number(column, 2)]
		_add(result, street, Vector2(middle, GRID_TOP))
		for row: int in 3:
			_add(result, [_number(column, row)], Vector2(middle, _row_y(row + 0.5)))
			if row > 0:
				_add(
					result,
					[_number(column, row - 1), _number(column, row)],
					Vector2(middle, _row_y(row))
				)
			if column > 0:
				_add(
					result,
					[_number(column - 1, row), _number(column, row)],
					Vector2(_column_x(column), _row_y(row + 0.5))
				)
				if row > 0:
					_add(
						result,
						[
							_number(column - 1, row - 1),
							_number(column - 1, row),
							_number(column, row - 1),
							_number(column, row)
						],
						Vector2(_column_x(column), _row_y(row))
					)
		if column > 0:
			var line: Array[int] = []
			for row: int in 3:
				line.append(_number(column - 1, row))
				line.append(_number(column, row))
			_add(result, line, Vector2(_column_x(column), GRID_TOP))
	var outside_width := (OUTSIDE_RIGHT - OUTSIDE_LEFT) / 6.0
	var groups := {
		"low": range(1, 19),
		"high": range(19, 37),
		"even": range(2, 37, 2),
		"odd": range(1, 37, 2),
		"red": RouletteWheel.RED_NUMBERS,
		"black":
		range(1, 37).filter(func(n: int) -> bool: return RouletteWheel.color_for(n) == "black"),
	}
	for index: int in EVEN_MONEY.size():
		var covered: Array[int] = []
		covered.assign(groups[EVEN_MONEY[index]])
		var at := Vector2(
			OUTSIDE_LEFT + (index + 0.5) * outside_width, (EVEN_MONEY_TOP + DOZEN_TOP) * 0.5
		)
		_add_named(result, EVEN_MONEY[index], covered, at)
	var dozen_edges: Array[float] = [OUTSIDE_LEFT, _column_x(4), _column_x(8), OUTSIDE_RIGHT]
	for dozen: int in 3:
		var covered: Array[int] = []
		covered.assign(range(dozen * 12 + 1, dozen * 12 + 13))
		var at := Vector2(
			(dozen_edges[dozen] + dozen_edges[dozen + 1]) * 0.5, (DOZEN_TOP + GRID_TOP) * 0.5
		)
		_add_named(result, "dozen%d" % (dozen + 1), covered, at)
	for row: int in 3:
		var covered: Array[int] = []
		covered.assign(range(row + 1, 37, 3))
		_add_named(
			result,
			"column%d" % (row + 1),
			covered,
			Vector2((GRID_RIGHT + COLUMN_BET_RIGHT) * 0.5, _row_y(row + 0.5))
		)
	return result
