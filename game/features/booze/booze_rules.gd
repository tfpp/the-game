class_name BoozeRules
extends RefCounted
## Pure rules for casino drinks, drunk presentation and blackouts. No scene access.

enum Phase { NONE, COLLAPSE, OUT, WAKE }

## The catalog drinks that stock casino tables. Bottles last three sips.
const DRINKS: Array[String] = ["whiskey", "red_wine", "martini", "whiskey_rocks", "cosmopolitan"]
## Relative odds for DRINKS: cocktails are more common than whole bottles.
const DRINK_WEIGHTS: Array[float] = [1.0, 1.0, 1.6, 1.6, 1.6]

## Drink spots in world space (the feature root sits at the origin). Each rests on a
## real counter or tabletop; `test_booze_layout.gd` pins every height and clearance.
const SPOTS: Array[Vector3] = [
	# Salon bar counter. Its painted top (-0.12) sits above its collider (-0.27);
	# drinks stand on the visible wood, between the bar's own glasses and bottles.
	Vector3(-5.15, -0.12, -9.58),
	Vector3(-6.15, -0.12, -9.6),
	Vector3(-7.75, -0.12, -9.58),
	# The three salon card tables (felt -0.308), at the east guest's elbow.
	Vector3(-4.1, -0.308, -5.96),
	Vector3(-4.1, -0.308, -0.96),
	Vector3(-4.1, -0.308, 3.64),
	# Walnut promenade cocktail tables (top 1.045), beside their number cards.
	Vector3(-20.24, 1.045, 15.7),
	Vector3(-19.755, 1.045, -14.82),
	Vector3(20.245, 1.045, -7.82),
	Vector3(19.755, 1.045, 14.18),
	# Mariachi balcony bar counter (painted top 6.13, collider 5.98).
	Vector3(-29.38, 6.13, -0.2),
	Vector3(-29.38, 6.13, 2.2),
]

## A drink spot refills with a new random drink this long after it was taken.
const RESTOCK_MIN_S := 60.0
const RESTOCK_MAX_S := 150.0

## Intoxication (whole drinks, owned by BarCompanion) at which a drinker blacks out.
const BLACKOUT_DRINKS := 8.0
## Effects reach full strength one drink before the blackout.
const FULL_EFFECT_DRINKS := 7.0
## Below this effect level steps stay straight; above it, players stumble sideways.
const VEER_LEVEL := 0.15
const STUMBLE_LEVEL := 0.45

const COLLAPSE_S := 3.0
const OUT_S := 2.5
const WAKE_S := 6.0
const FALL_S := 0.9
const STAND_S := 1.5
## Give up on the metro after this long and wake where the player fell.
const DELIVERY_TIMEOUT_S := 30.0

## Metro island lanes beside each track, matching MetroRules.platform_recovery().
const PLATFORM_LANES: Array[float] = [3.3, 12.7]
const PLATFORM_FLOOR := 1.2
const PLATFORM_HALF_LENGTH := 48.0
## Height of a lying body's back above the floor, as a share of standing height.
const LIFT_SHARE := 0.07
const STANDARD_HEIGHT := 1.8288


static func is_drink(id: String) -> bool:
	return ItemCatalog.consumable_kind(id) in DRINKS


static func pick_drink(roll: float) -> String:
	var total := 0.0
	for weight: float in DRINK_WEIGHTS:
		total += weight
	var target := clampf(roll, 0.0, 0.9999) * total
	for index: int in DRINKS.size():
		target -= DRINK_WEIGHTS[index]
		if target < 0.0:
			return DRINKS[index]
	return DRINKS[DRINKS.size() - 1]


static func restock_delay(roll: float) -> float:
	return lerpf(RESTOCK_MIN_S, RESTOCK_MAX_S, clampf(roll, 0.0, 1.0))


static func blacks_out(drinks: float) -> bool:
	return drinks >= BLACKOUT_DRINKS - 0.001


## 0 sober … 1 one drink short of a blackout.
static func intensity(drinks: float) -> float:
	return clampf(drinks / FULL_EFFECT_DRINKS, 0.0, 1.0)


static func mood(drinks: float) -> String:
	if drinks >= 6.0:
		return "hammered"
	if drinks >= 3.0:
		return "drunk"
	if drinks > 0.0:
		return "tipsy"
	return "sober"


## Slow camera roll in radians: a few degrees when tipsy, about ten when hammered.
static func camera_roll(time: float, level: float) -> float:
	return deg_to_rad(10.0) * level * (sin(time * 0.83) * 0.7 + sin(time * 1.91 + 1.3) * 0.3)


## Aim drift (yaw, pitch) in radians. Applied as a change in the real view angles,
## so the crosshair stays honest: shots follow what the drunk player sees.
static func aim_sway(time: float, level: float) -> Vector2:
	var amount := deg_to_rad(4.0) * level * level
	return (
		Vector2(
			sin(time * 0.61) * 0.65 + sin(time * 1.37 + 0.5) * 0.35,
			sin(time * 0.47 + 0.8) * 0.6 + sin(time * 1.13) * 0.4,
		)
		* amount
	)


## Radians per second that walking veers off course: a lazy weave left and right.
static func veer_rate(time: float, level: float) -> float:
	if level < VEER_LEVEL:
		return 0.0
	return 1.4 * level * (sin(time * 0.9) * 0.7 + sin(time * 2.3 + 0.4) * 0.3)


## Seconds until the next sideways stumble; heavier drinkers stumble more often.
static func stumble_interval(level: float, roll: float) -> float:
	return lerpf(2.0, 5.0, clampf(roll, 0.0, 1.0)) / maxf(level, 0.25)


## Sideways stumble speed in m/s.
static func stumble_speed(level: float) -> float:
	return 1.2 + 2.2 * level if level >= STUMBLE_LEVEL else 0.0


## Screen double vision and vignette strength.
static func screen_strength(level: float) -> float:
	return clampf(level, 0.0, 1.0) ** 1.2


## Local screen darkness (0 clear … 1 black) `elapsed` seconds into `phase`.
static func darkness(phase: int, elapsed: float) -> float:
	match phase:
		Phase.COLLAPSE:
			return smoothstep(0.3, COLLAPSE_S, elapsed)
		Phase.OUT:
			return 1.0
		Phase.WAKE:
			# Heavy eyelids: open slowly, then one long blink.
			var open := smoothstep(0.8, 3.2, elapsed)
			var blink := maxf(0.0, 1.0 - absf(elapsed - 2.0) / 0.25) * 0.8
			return clampf(1.0 - open + blink * open, 0.0, 1.0)
	return 0.0


## Whether a body should be (or be going) flat on the ground.
static func lying_target(phase: int, elapsed: float) -> float:
	match phase:
		Phase.COLLAPSE, Phase.OUT:
			return 1.0
		Phase.WAKE:
			return 1.0 if elapsed < WAKE_S - STAND_S else 0.0
	return 0.0


static func caption(phase: int, elapsed: float) -> String:
	if phase == Phase.OUT:
		return "You blacked out."
	if phase == Phase.WAKE and elapsed < WAKE_S - 1.0:
		return "Ugh... where are your clothes?"
	return ""


## Player/Body transform lying `weight` (0 standing … 1 flat) on its back, head toward
## the body's +Z. `hull` is the capsule height (feet at -hull/2), `height` the avatar's
## standing height. Rotates about the feet, then centres the body on the capsule.
static func lying_body(yaw: float, hull: float, height: float, weight: float) -> Transform3D:
	var w := clampf(weight, 0.0, 1.0)
	var feet := Vector3(0, -hull * 0.5, 0)
	var tilt := Basis(Vector3.RIGHT, PI * 0.5 * w)
	var shift := Vector3(0, height * LIFT_SHARE, -height * 0.5) * w
	var turn := Basis(Vector3.UP, yaw)
	return Transform3D(turn * tilt, turn * (feet + shift - tilt * feet))


## World camera transform for a first-person drinker lying flat at `origin`.
static func lying_eye(origin: Vector3, yaw: float, hull: float, height: float) -> Transform3D:
	var body := Transform3D(Basis.IDENTITY, origin) * lying_body(yaw, hull, height, 1.0)
	var scale := height / STANDARD_HEIGHT
	var eye := body * Vector3(0, -hull * 0.5 + height * 0.93, -0.07 * scale)
	var look := (
		Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(72)) * Basis(Vector3.BACK, 0.3)
	)
	return Transform3D(look, eye)


## Where a blacked-out player wakes, relative to metro station `station`'s origin:
## a lane along the island's track edge (`side` 0 or 1), `along` 0…1 down the
## platform, lying parallel to the tracks. Returns {station, local, yaw}.
static func wake_spot(station: int, side: int, along: float, hull: float) -> Dictionary:
	var lane := PLATFORM_LANES[clampi(side, 0, 1)]
	var z := lerpf(-PLATFORM_HALF_LENGTH, PLATFORM_HALF_LENGTH, clampf(along, 0.0, 1.0))
	return {
		"station": posmod(station, 4),
		"local": Vector3(lane, PLATFORM_FLOOR + hull * 0.5 + 0.02, z),
		"yaw": 0.0 if side == 0 else PI,
	}
