class_name TrumpQuips
extends RefCounted
## Remodeling promises Trump makes when bribed. Every combination of opener, casino
## area and plan is a distinct quip, 10 × 10 × 10 = 1,000 in total.

const OPENERS: Array[String] = [
	"Believe me,",
	"Nobody builds like me.",
	"Many people are saying it:",
	"Tremendous news,",
	"Great deal, the best deal.",
	"Folks, listen,",
	"Very generous of you.",
	"Between us,",
	"Frankly,",
	"Big league,",
]
const AREAS: Array[String] = [
	"the slot floor",
	"the elevator",
	"the roulette tables",
	"the lobby",
	"the bar",
	"the promenade",
	"the parlors",
	"the vault",
	"the restrooms",
	"the kebab shop",
]
const PLANS: Array[String] = [
	"in solid gold",
	"twice as tall",
	"with a much bigger chandelier",
	"with marble from the best quarries",
	"with my name on it, huge letters",
	"with a ballroom, a beautiful ballroom",
	"in gold leaf, top to bottom",
	"with gold escalators",
	"with windows nobody's ever seen before",
	"with a wall, and the slums will pay for it",
]
const COUNT := 1000

## The quip for index 0..COUNT-1; other indexes wrap around.
@warning_ignore("integer_division")
static func quip(index: int) -> String:
	var i := posmod(index, COUNT)
	return "%s I'm remodeling %s %s!" % [OPENERS[i / 100], AREAS[(i / 10) % 10], PLANS[i % 10]]


static func pick(rng: RandomNumberGenerator) -> String:
	return quip(rng.randi_range(0, COUNT - 1))
