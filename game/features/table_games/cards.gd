class_name CasinoCards
extends RefCounted
## Card IDs: suit * 13 + rank - 2. Decks and hidden hands live only on the server.


static func deck(rng: RandomNumberGenerator) -> Array[int]:
	var cards: Array[int] = []
	for card: int in 52:
		cards.append(card)
	for i: int in range(51, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := cards[i]
		cards[i] = cards[j]
		cards[j] = swap
	return cards


static func rank(card: int) -> int:
	return card % 13 + 2


static func label(card: int) -> String:
	return (
		"%s%s"
		% [
			str(rank(card)) if rank(card) < 11 else ["J", "Q", "K", "A"][rank(card) - 11],
			["♣", "♦", "♥", "♠"][card / 13]
		]
	)


static func labels(cards: Array) -> String:
	var names := PackedStringArray()
	for card: int in cards:
		names.append(label(card))
	return "  ".join(names)


static func blackjack(cards: Array) -> int:
	var total := 0
	var aces := 0
	for card: int in cards:
		var value := rank(card)
		total += mini(value, 10) if value != 14 else 11
		aces += 1 if value == 14 else 0
	while total > 21 and aces > 0:
		total -= 10
		aces -= 1
	return total


static func baccarat(cards: Array) -> int:
	var total := 0
	for card: int in cards:
		var value := rank(card)
		total += 1 if value == 14 else (value if value < 10 else 0)
	return total % 10


## Lexicographic hand score encoded base 15: category, then five tie breakers.
static func five(cards: Array) -> int:
	var counts: Dictionary = {}
	var ranks: Array[int] = []
	var flush := true
	for card: int in cards:
		var value := rank(card)
		counts[value] = int(counts.get(value, 0)) + 1
		ranks.append(value)
		flush = flush and card / 13 == int(cards[0]) / 13
	ranks.sort()
	ranks.reverse()
	var unique: Array = counts.keys()
	unique.sort()
	var straight := 0
	if unique.size() == 5:
		if int(unique[4]) - int(unique[0]) == 4:
			straight = int(unique[4])
		elif unique == [2, 3, 4, 5, 14]:
			straight = 5
	var groups: Array = counts.keys()
	groups.sort_custom(
		func(a: int, b: int) -> bool:
			return int(counts[a]) > int(counts[b]) or (counts[a] == counts[b] and a > b)
	)
	var hand_category := 0
	var kickers: Array = ranks
	if straight > 0 and flush:
		hand_category = 8
		kickers = [straight]
	elif int(counts[groups[0]]) == 4:
		hand_category = 7
		kickers = groups
	elif int(counts[groups[0]]) == 3 and groups.size() == 2:
		hand_category = 6
		kickers = groups
	elif flush:
		hand_category = 5
	elif straight > 0:
		hand_category = 4
		kickers = [straight]
	elif int(counts[groups[0]]) == 3:
		hand_category = 3
		kickers = groups
	elif int(counts[groups[0]]) == 2:
		hand_category = 2 if int(counts[groups[1]]) == 2 else 1
		kickers = groups
	var score := hand_category
	for i: int in 5:
		score = score * 15 + (int(kickers[i]) if i < kickers.size() else 0)
	return score


static func best(cards: Array) -> int:
	var score := 0
	for a: int in range(cards.size() - 4):
		for b: int in range(a + 1, cards.size() - 3):
			for c: int in range(b + 1, cards.size() - 2):
				for d: int in range(c + 1, cards.size() - 1):
					for e: int in range(d + 1, cards.size()):
						score = maxi(
							score, five([cards[a], cards[b], cards[c], cards[d], cards[e]])
						)
	return score


static func category(score: int) -> int:
	return score / 759375


static func hand_name(score: int) -> String:
	return [
		"High card",
		"Pair",
		"Two pair",
		"Three of a kind",
		"Straight",
		"Flush",
		"Full house",
		"Four of a kind",
		"Straight flush"
	][category(score)]


## Crown draw poker custom gross multipliers, displayed before play.
static func video_payout(cards: Array) -> int:
	var score := five(cards)
	var kind := category(score)
	if kind == 8:
		return 36 if score / 50625 % 15 == 14 else 25
	if kind == 1:
		return 1 if score / 50625 % 15 >= 11 else 0
	return [0, 0, 2, 3, 4, 6, 9, 25][kind]
