extends GutTest


func test_deck_and_ace_scoring() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1964
	var deck := CasinoCards.deck(rng)
	assert_eq(deck.size(), 52)
	for i: int in 52:
		assert_eq(deck.count(i), 1)
	assert_eq(CasinoCards.blackjack([12, 25, 7]), 21)
	assert_eq(CasinoCards.blackjack([12, 11]), 21)
	assert_eq(CasinoCards.baccarat([12, 7, 10]), 0)


func test_blackjack_naturals_pushes_busts_and_soft_17() -> void:
	assert_eq(CasinoRules.blackjack_payout([12, 11], [8, 6], 100), 250)
	assert_eq(CasinoRules.blackjack_payout([12, 11], [25, 24], 100), 100)
	assert_eq(CasinoRules.blackjack_payout([8, 7, 3], [8, 6], 100), 0)
	assert_eq(CasinoRules.blackjack_payout([8, 6], [7, 7], 100), 100)
	assert_eq(CasinoCards.blackjack([12, 4]), 17)


func test_baccarat_commission_tie_and_push() -> void:
	assert_eq(CasinoRules.baccarat_payout("banker", [2, 0], [3, 1], 100), 195)
	assert_eq(CasinoRules.baccarat_payout("player", [2, 0], [2, 0], 100), 100)
	assert_eq(CasinoRules.baccarat_payout("tie", [2, 0], [2, 0], 100), 900)
	assert_eq(CasinoRules.baccarat_payout("tie", [2, 0], [3, 1], 100), 0)


func test_baccarat_third_card_table_and_naturals() -> void:
	# Pop order: player 2+2, banker 2+3, third 4. Banker five draws on four.
	var deck: Array[int] = [6, 2, 1, 0, 0, 0]
	var deal := CasinoRules.baccarat_deal(deck)
	assert_eq(deal["player"].size(), 3)
	assert_eq(deal["banker"].size(), 3)
	var natural: Array[int] = [0, 0, 2, 2]
	deal = CasinoRules.baccarat_deal(natural)
	assert_eq(deal["player"].size(), 2)
	assert_eq(deal["banker"].size(), 2)


func test_craps_comeout_and_point() -> void:
	assert_eq(CasinoRules.craps_outcome(7, 0), 1)
	assert_eq(CasinoRules.craps_outcome(11, 0), 1)
	for total: int in [2, 3, 12]:
		assert_eq(CasinoRules.craps_outcome(total, 0), -1)
	assert_eq(CasinoRules.craps_outcome(6, 0), 0)
	assert_eq(CasinoRules.craps_outcome(6, 6), 1)
	assert_eq(CasinoRules.craps_outcome(7, 6), -1)
	assert_eq(CasinoRules.craps_outcome(11, 6), 0)


func test_poker_kickers_wheel_and_seven_card_selection() -> void:
	var royal := CasinoCards.five([8, 9, 10, 11, 12])
	assert_eq(CasinoCards.category(royal), 8)
	assert_eq(CasinoCards.video_payout([8, 9, 10, 11, 12]), 36)
	var wheel := CasinoCards.five([12, 0, 1, 2, 3])
	assert_eq(CasinoCards.category(wheel), 8)
	assert_lt(wheel, royal)
	assert_eq(CasinoCards.best([8, 9, 10, 11, 12, 13, 26]), royal)
	var full_house := CasinoCards.five([12, 25, 38, 11, 24])
	assert_eq(CasinoCards.category(full_house), 6)
	assert_gt(full_house, CasinoCards.five([0, 2, 4, 6, 9]))
	assert_gt(CasinoCards.five([12, 25, 11, 7, 3]), CasinoCards.five([12, 25, 10, 7, 3]))
	assert_eq(CasinoCards.video_payout([9, 22, 1, 5, 7]), 1)
	assert_eq(CasinoCards.video_payout([8, 21, 1, 5, 7]), 0)
