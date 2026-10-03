class_name CasinoRules
extends RefCounted


static func blackjack_payout(hand: Array, dealer: Array, stake: int) -> int:
	var mine := CasinoCards.blackjack(hand)
	var house := CasinoCards.blackjack(dealer)
	var natural := hand.size() == 2 and mine == 21
	var dealer_natural := dealer.size() == 2 and house == 21
	if mine > 21 or (dealer_natural and not natural):
		return 0
	if natural:
		return stake if dealer_natural else stake * 5 / 2
	if house > 21 or mine > house:
		return stake * 2
	return stake if mine == house else 0


static func baccarat_deal(deck: Array[int]) -> Dictionary:
	var player: Array[int] = [deck.pop_back(), deck.pop_back()]
	var banker: Array[int] = [deck.pop_back(), deck.pop_back()]
	var p := CasinoCards.baccarat(player)
	var b := CasinoCards.baccarat(banker)
	if p < 8 and b < 8:
		var third := -1
		if p <= 5:
			player.append(deck.pop_back())
			third = CasinoCards.baccarat([player[-1]])
		var draw := (
			b <= 5
			if third < 0
			else (
				b <= 2
				or (b == 3 and third != 8)
				or (b == 4 and third >= 2 and third <= 7)
				or (b == 5 and third >= 4 and third <= 7)
				or (b == 6 and third >= 6 and third <= 7)
			)
		)
		if draw:
			banker.append(deck.pop_back())
	return {"player": player, "banker": banker}


static func baccarat_payout(choice: String, player: Array, banker: Array, stake: int) -> int:
	var p := CasinoCards.baccarat(player)
	var b := CasinoCards.baccarat(banker)
	if p == b:
		return stake * 9 if choice == "tie" else stake
	if choice == "player" and p > b:
		return stake * 2
	if choice == "banker" and b > p:
		return stake * 195 / 100
	return 0


## Pass line only: +1 win, -1 loss, 0 continue. Point is established by the caller.
static func craps_outcome(total: int, point: int) -> int:
	if point == 0:
		if total == 7 or total == 11:
			return 1
		if total == 2 or total == 3 or total == 12:
			return -1
	else:
		if total == point:
			return 1
		if total == 7:
			return -1
	return 0
