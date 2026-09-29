class_name PatronMath
## Pure rules for the casino patrons: their walking routes, facing and pacing.
## Kept free of nodes so tests can check them directly.

## Floor height of the gaming floor (features/casino_hub/README.md).
const FLOOR_Y := -1.5
const WALK_SPEED := 1.3
const PAUSE_MIN_S := 1.2
const PAUSE_MAX_S := 3.5
## A patron waits instead of walking into a player closer than this ahead of it.
const PERSONAL_SPACE_M := 0.9
## ...but only this long, then squeezes past (players don't collide with patrons).
const MAX_WAIT_S := 2.0

## Zohran Mamdani (PatronModel.MAMDANI_LOOK) is essential: a gunshot knocks him out
## for this long instead of killing him.
const KNOCKOUT_S := 5.0
## Talking to him pays subway fare (PlayerMoney.COIN_CREDIT_CENTS) once per this
## many seconds per account.
const FARE_COOLDOWN_S := 3600.0

## Closed loops of world-space waypoints on the gaming floor's clear aisles
## (tests/features/casino_patrons/test_patron_routes.gd sweeps each leg). A
## two-point loop is a stroll back and forth.
const ROUTES: Array[Array] = [
	[
		Vector3(0.5, FLOOR_Y, -6),
		Vector3(5.5, FLOOR_Y, -6),
		Vector3(5.5, FLOOR_Y, 5.5),
		Vector3(0.5, FLOOR_Y, 5.5)
	],
	[Vector3(12, FLOOR_Y, -10.5), Vector3(12, FLOOR_Y, 10.5)],
	[
		Vector3(-12, FLOOR_Y, 7),
		Vector3(-5, FLOOR_Y, 7),
		Vector3(-5, FLOOR_Y, 10.5),
		Vector3(-12, FLOOR_Y, 10.5)
	],
	[Vector3(-12.5, FLOOR_Y, -11), Vector3(-5, FLOOR_Y, -11)],
	# Zohran Mamdani (PatronModel.MAMDANI_LOOK) strolls an aisle by the slots.
	[Vector3(8.5, FLOOR_Y, -11), Vector3(8.5, FLOOR_Y, 2)],
]


static func route(index: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	points.assign(ROUTES[index % ROUTES.size()])
	return points


static func next_waypoint(current: int, count: int) -> int:
	return (current + 1) % maxi(count, 1)


## Yaw that points a -Z-facing model along `direction`.
static func facing_yaw(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## True when a player at `other` stands within personal space in front of a
## patron at `from` walking along `heading`.
static func is_in_the_way(from: Vector3, heading: Vector3, other: Vector3) -> bool:
	var offset := Vector3(other.x - from.x, 0.0, other.z - from.z)
	if offset.length() > PERSONAL_SPACE_M:
		return false
	return offset.dot(Vector3(heading.x, 0.0, heading.z)) > 0.0


## Seconds until a player who last got fare at `last_s` can get it again at `now_s`
## (0 when ready). A negative `last_s` means never claimed.
static func fare_wait_s(last_s: float, now_s: float) -> float:
	if last_s < 0.0:
		return 0.0
	return maxf(last_s + FARE_COOLDOWN_S - now_s, 0.0)


## "59 min", "1 min"... for the cooldown reply; always rounds up.
static func wait_text(seconds: float) -> String:
	return "%d min" % maxi(ceili(seconds / 60.0), 1)
