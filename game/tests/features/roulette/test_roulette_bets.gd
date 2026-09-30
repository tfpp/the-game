extends GutTest


func test_every_spot_hit_tests_to_itself_at_its_anchor() -> void:
	for key: String in RouletteBets.spots():
		assert_eq(RouletteBets.spot_at(RouletteBets.anchor(key)), key, "anchor of %s" % key)


func test_layout_has_every_american_bet() -> void:
	var counts := {}
	for key: String in RouletteBets.spots():
		var size := RouletteBets.numbers(key).size()
		counts[size] = int(counts.get(size, 0)) + 1
	assert_eq(counts[1], 38, "straight up on 0, 00 and 1-36")
	# 57 grid splits plus 0-1, 0-2, 00-2, 00-3 and 0-00.
	assert_eq(counts[2], 62)
	# 12 streets plus the 0-1-2 and 00-2-3 trios.
	assert_eq(counts[3], 14)
	assert_eq(counts[4], 22, "corners")
	assert_false(counts.has(5), "no five-number top line")
	assert_eq(counts[6], 11, "six lines")
	assert_eq(counts[12], 6, "dozens and columns")
	assert_eq(counts[18], 6, "even-money bets")


func test_payouts_follow_american_odds() -> void:
	assert_eq(RouletteBets.payout_to_one("17"), 35)
	assert_eq(RouletteBets.payout_to_one("37"), 35, "double zero")
	assert_eq(RouletteBets.payout_to_one("17-20"), 17)
	assert_eq(RouletteBets.payout_to_one("16-17-18"), 11)
	assert_eq(RouletteBets.payout_to_one("16-17-19-20"), 8)
	assert_eq(RouletteBets.payout_to_one("13-14-15-16-17-18"), 5)
	assert_eq(RouletteBets.payout_to_one("dozen2"), 2)
	assert_eq(RouletteBets.payout_to_one("column3"), 2)
	assert_eq(RouletteBets.payout_to_one("red"), 1)
	assert_eq(RouletteBets.payout_to_one("nonsense"), 0)


func test_every_bet_follows_n_over_38_with_the_same_house_edge() -> void:
	for key: String in RouletteBets.spots():
		var count := RouletteBets.numbers(key).size()
		assert_eq((RouletteBets.payout_to_one(key) + 1) * count, 36, "%s pays 36/n - 1" % key)
		assert_almost_eq(RouletteBets.probability(key), count / 38.0, 0.000001)
		assert_almost_eq(RouletteBets.expected_return(key), -2.0 / 38.0, 0.000001, key)


func test_odds_match_the_published_american_table() -> void:
	assert_eq(RouletteBets.odds_text("17"), "2.63% (37 : 1)")
	assert_eq(RouletteBets.odds_text("17-20"), "5.26% (18 : 1)")
	assert_eq(RouletteBets.odds_text("16-17-18"), "7.89% (11.6 : 1)")
	assert_eq(RouletteBets.odds_text("16-17-19-20"), "10.52% (8.5 : 1)")
	assert_eq(RouletteBets.odds_text("13-14-15-16-17-18"), "15.78% (5.3 : 1)")
	assert_eq(RouletteBets.odds_text("column1"), "31.57% (2.1 : 1)")
	assert_eq(RouletteBets.odds_text("dozen2"), "31.57% (2.1 : 1)")
	assert_eq(RouletteBets.odds_text("red"), "47.36% (1.1 : 1)")
	assert_eq(RouletteBets.odds_text("odd"), "47.36% (1.1 : 1)")
	assert_eq(RouletteBets.odds_text("high"), "47.36% (1.1 : 1)")


func test_colour_plus_opposite_numbers_matches_the_worked_example() -> void:
	# n = 2 straight-ups on red numbers, c = 3 units on black, S = $1.
	var placements := [["1", 100], ["3", 100], ["black", 300]]
	var black := RouletteBets.settle(placements, 2)
	assert_eq(black["payout"] - black["wager"], 100, "colour wins: (c - n) S")
	var red := RouletteBets.settle(placements, 1)
	assert_eq(red["payout"] - red["wager"], 3100, "number wins: (36 - n - c) S")
	var zero := RouletteBets.settle(placements, 0)
	assert_eq(zero["payout"] - zero["wager"], -500, "nothing wins: (c + n) S")


func test_outside_bets_cover_the_right_pockets() -> void:
	assert_eq(RouletteBets.numbers("red"), RouletteWheel.RED_NUMBERS)
	assert_eq(RouletteBets.numbers("black").size(), 18)
	assert_false(RouletteBets.numbers("black").has(1))
	assert_false(RouletteBets.numbers("even").has(0), "zero is not even")
	assert_false(RouletteBets.numbers("low").has(RouletteWheel.DOUBLE_ZERO))
	assert_eq(RouletteBets.numbers("column1").slice(0, 3), [1, 4, 7])
	assert_eq(RouletteBets.numbers("dozen3")[0], 25)


func test_settle_totals_stake_and_winnings() -> void:
	var placements := [["17", 100], ["red", 500], ["black", 500], ["17", 500]]
	# 17 is black: straight 600 * 36, black 500 * 2.
	assert_eq(RouletteBets.settle(placements, 17), {"wager": 1600, "payout": 22600})
	assert_eq(RouletteBets.settle(placements, 0), {"wager": 1600, "payout": 0})
	assert_eq(RouletteBets.by_spot(placements), {"17": 600, "red": 500, "black": 500})


func test_amounts_break_into_the_largest_chips() -> void:
	assert_eq(RouletteBets.chips_for(5600), [5000, 500, 100])
	assert_eq(RouletteBets.chips_for(2600000), [2500000, 100000])
	assert_eq(RouletteBets.chips_for(0), [])


func test_clicks_pick_numbers_lines_and_outside_bets() -> void:
	# The fifth column (13-15) spans x 92.3-109.7; 14 is its middle row (y 73-94).
	assert_eq(RouletteBets.spot_at(Vector2(101, 82)), "14")
	assert_eq(RouletteBets.spot_at(Vector2(92.5, 82)), "11-14", "on the column line")
	assert_eq(RouletteBets.spot_at(Vector2(101, 73.5)), "13-14", "on the row line")
	assert_eq(RouletteBets.spot_at(Vector2(92.5, 73.2)), "10-11-13-14", "on the corner")
	assert_eq(RouletteBets.spot_at(Vector2(101, 51)), "13-14-15", "street on the top edge")
	assert_eq(RouletteBets.spot_at(Vector2(12, 60)), "0")
	assert_eq(RouletteBets.spot_at(Vector2(12, 105)), "37")
	assert_eq(RouletteBets.spot_at(Vector2(240, 62)), "column1")
	assert_eq(RouletteBets.spot_at(Vector2(60, 42)), "dozen1")
	assert_eq(RouletteBets.spot_at(Vector2(100, 22)), "red")
	assert_eq(RouletteBets.spot_at(Vector2(2, 2)), "", "the rail is not a bet")


func test_pixels_round_trip_through_table_space() -> void:
	var pixel := Vector2(118, 82)
	var local := RouletteBets.pixel_to_local(pixel)
	assert_almost_eq(local.y, RouletteBets.LAYOUT_Y, 0.0001)
	assert_almost_eq(RouletteBets.local_to_pixel(local), pixel, Vector2.ONE * 0.001)
	assert_almost_eq(RouletteBets.pixel_to_local(Vector2.ZERO).x, -0.3, 0.0001)


func test_descriptions_name_the_bet_and_its_odds() -> void:
	assert_eq(RouletteBets.describe("17-20"), "Split 17 / 20 — wins 5.26% (18 : 1), pays 17 to 1")
	assert_eq(RouletteBets.describe("0-37"), "Split 0 / 00 — wins 5.26% (18 : 1), pays 17 to 1")
	assert_eq(RouletteBets.describe("red"), "Red — wins 47.36% (1.1 : 1), pays 1 to 1")
	assert_eq(RouletteBets.describe(""), "")
