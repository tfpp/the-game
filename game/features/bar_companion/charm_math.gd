class_name CharmMath
extends RefCounted
## Pure rules for charisma, intoxication and Vivienne's price.

const DRINK_CENTS := 500
const BASE_PRICE_CENTS := 5000
## Each charisma point takes this share off her price, down to MIN_PRICE_SHARE.
const DISCOUNT_PER_POINT := 0.07
const MIN_PRICE_SHARE := 0.3
const MAX_CHARISMA := 10
## Drinks up to this many make you charming; each one past it costs charisma.
const TIPSY_DRINKS := 3
const OVERDRUNK_PENALTY := 2.0
const MAX_INTOXICATION := 10.0
## One drink wears off every this many seconds.
const SOBER_S := 90.0
const WIN_CHARISMA := 2.0
const MAX_WIN_CHARISMA := 6.0
## One point of win charisma fades every this many seconds.
const WIN_FADE_S := 60.0
const LUCK_S := 600.0
## Extra slot reel rolls while the lucky night lasts (same mechanism as Kaaba blessings).
const LUCK_REROLLS := 2


## Charisma from drinks: tipsy helps, but past TIPSY_DRINKS each drink hurts twice as much.
static func drink_charisma(intoxication: float) -> float:
	return (
		minf(intoxication, TIPSY_DRINKS)
		- OVERDRUNK_PENALTY * maxf(intoxication - TIPSY_DRINKS, 0.0)
	)


static func charisma(win_charisma: float, intoxication: float) -> int:
	var total := win_charisma + drink_charisma(intoxication)
	return clampi(floori(total + 0.0001), 0, MAX_CHARISMA)


static func price_cents(charisma_points: int) -> int:
	var share := maxf(1.0 - DISCOUNT_PER_POINT * charisma_points, MIN_PRICE_SHARE)
	return int(round(BASE_PRICE_CENTS * share))


static func decay(value: float, delta: float, seconds_per_point: float) -> float:
	return maxf(value - delta / seconds_per_point, 0.0)


static func mood(intoxication: float) -> String:
	if intoxication > TIPSY_DRINKS:
		return "too drunk"
	if intoxication > 0.0:
		return "tipsy"
	return "sober"
