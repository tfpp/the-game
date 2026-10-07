class_name MetroRules
extends RefCounted
## Two directions, each with four services one stop apart around the loop.

const NAMES: Array[String] = ["CROWN", "MARKET", "WORKS", "RESIDENCES"]
const SERVICES := 8
const TRACK_SPACING := 16.0
const OPEN := 1.2
const DWELL := 12.0
const CLOSE := 1.2
const TRAVEL := 18.0
const PERIOD := OPEN + DWELL + CLOSE + TRAVEL
const DEPART := OPEN + DWELL + CLOSE
const STATION_BOUNDS := AABB(Vector3(-6, -1, -92), Vector3(30, 9, 184))
const RIDE_BOUNDS := AABB(Vector3(-4, -1, -60), Vector3(8, 7, 120))
## How far riders can see the platforms and tunnel passing their windows.
const RIDE_VIEW := AABB(Vector3(-10, -1, -100), Vector3(34, 9, 200))
const PITCH := 22.86
# Native R44 assembly bounds, rail level to roof (README/model manifest).
const TRAIN_HALF_WIDTH := 1.575
const TRAIN_HALF_LENGTH := 57.15
const TRAIN_HEIGHT := 3.66
## Station walls close both tunnel mouths at |z| = 91.
const TUNNEL_END := 91.0
## Track between neighbouring stations. A departing train is past the far tunnel
## wall before the next one, the same distance behind it, comes into view.
const SPACING := 300.0
## Every trip accelerates for RAMP seconds, cruises, then brakes for RAMP seconds.
const RAMP := 7.5
## Acceleration builds up and eases off over EASE seconds at each end of a ramp,
## so trains never jolt into motion or slam to a stop.
const EASE := 1.0
const TOP_SPEED := SPACING / (TRAVEL - RAMP)
const ACCELERATION := TOP_SPEED / (RAMP - EASE)


static func station_position(index: int) -> Vector3:
	return Vector3(index * 600, 0, -8000)


static func ride_position(service: int) -> Vector3:
	return Vector3(service * 600, 0, -10000)


static func station(service: int, cycle: int) -> int:
	return posmod(service + cycle * direction(service), 4)


static func direction(service: int) -> int:
	return 1 if service < 4 else -1


static func track(service: int) -> int:
	return 0 if service < 4 else 1


static func track_offset(track_index: int) -> Vector3:
	return Vector3(TRACK_SPACING * track_index, 0, 0)


static func aperture(time: float) -> float:
	if time < OPEN:
		return clampf(time / OPEN, 0, 1)
	if time < OPEN + DWELL:
		return 1.0
	if time < DEPART:
		return 1.0 - (time - OPEN - DWELL) / CLOSE
	return 0.0


## Metres a train has covered `travel` seconds after leaving a platform.
static func distance(travel: float) -> float:
	var t := clampf(travel, 0.0, TRAVEL)
	if t > TRAVEL - RAMP:
		return SPACING - _ramp_distance(TRAVEL - t)
	return _ramp_distance(minf(t, RAMP)) + TOP_SPEED * maxf(t - RAMP, 0.0)


## Metres per second `travel` seconds after leaving a platform.
static func speed(travel: float) -> float:
	var t := clampf(travel, 0.0, TRAVEL)
	if t > TRAVEL - RAMP:
		return _ramp_speed(TRAVEL - t)
	return _ramp_speed(minf(t, RAMP))


# The ramp's second half mirrors its first, so speed passes half of TOP_SPEED
# at RAMP / 2 and acceleration fades out before cruising.
static func _ramp_distance(t: float) -> float:
	if t > RAMP * 0.5:
		return TOP_SPEED * (t - RAMP * 0.5) + _rise_distance(RAMP - t)
	return _rise_distance(t)


static func _ramp_speed(t: float) -> float:
	if t > RAMP * 0.5:
		return TOP_SPEED - _rise_speed(RAMP - t)
	return _rise_speed(t)


static func _rise_distance(t: float) -> float:
	if t < EASE:
		return ACCELERATION * t * t * t / (6.0 * EASE)
	return ACCELERATION * (t * t * 0.5 - EASE * t * 0.5 + EASE * EASE / 6.0)


static func _rise_speed(t: float) -> float:
	if t < EASE:
		return ACCELERATION * t * t / (2.0 * EASE)
	return ACCELERATION * (t - EASE * 0.5)


## Station-relative z of the train beside a platform. The departing train leaves
## along -Z; at mid-trip, out of sight, the view hands over to the next train,
## SPACING behind it on the loop, which stops at z = 0.
static func train_z(time: float) -> float:
	if time <= DEPART:
		return 0.0
	var covered := distance(time - DEPART)
	return -covered if time < DEPART + TRAVEL * 0.5 else SPACING - covered


## Whether a station train at `z` is entirely behind a tunnel end wall.
static func train_hidden(z: float) -> bool:
	return absf(z) >= TUNNEL_END + TRAIN_HALF_LENGTH


## Sweep the departing and arriving trains separately, never the hand-over.
## Point is capsule centre in station coordinates, not the player's rendered pose.
static func train_hits(
	point: Vector3, radius: float, height: float, previous: float, current: float
) -> bool:
	if current <= previous:
		return false
	if absf(point.x) > TRAIN_HALF_WIDTH + radius:
		return false
	if point.y + height * 0.5 < 0 or point.y - height * 0.5 > TRAIN_HEIGHT:
		return false
	var handover := DEPART + TRAVEL * 0.5
	# Keep endpoints as 64-bit floats like the timetable (Vector2 rounds to float32).
	for segment: Array in [[DEPART, handover, 0.0], [handover, PERIOD, SPACING]]:
		var start := maxf(previous, float(segment[0]))
		var end := minf(current, float(segment[1]))
		if end <= start:
			continue
		var from_z := float(segment[2]) - distance(start - DEPART)
		var to_z := float(segment[2]) - distance(end - DEPART)
		if (
			point.z >= minf(from_z, to_z) - TRAIN_HALF_LENGTH - radius
			and point.z <= maxf(from_z, to_z) + TRAIN_HALF_LENGTH + radius
		):
			return true
	return false


## Departure board text at station `index`, `time` seconds into the cycle.
static func station_board(index: int, time: float, track_index: int = 0) -> String:
	var status := "DEPARTS IN %02d s" % maxi(0, ceili(OPEN + DWELL - time))
	if time >= DEPART:
		status = "NEXT TRAIN %02d s" % ceili(PERIOD - time)
	elif time >= OPEN + DWELL:
		status = "DOORS CLOSING"
	var next := posmod(index + (1 if track_index == 0 else -1), 4)
	return (
		"%s\n%s → %s\n%s"
		% [NAMES[index], "UPTOWN" if track_index == 0 else "DOWNTOWN", NAMES[next], status]
	)


static func car_center(index: int) -> float:
	return (2 - index) * PITCH


static func collision_y(time: float) -> float:
	# Only presentation accelerates through tunnels. Parked collision changes once
	# per phase instead of moving hundreds of physics bodies each rendered frame.
	return -200.0 if time >= DEPART else 0.0


static func car_at(point: Vector3) -> int:
	for index: int in 5:
		if absf(point.z - car_center(index)) < 10.85:
			return index
	return -1


static func aboard(point: Vector3, radius: float = 0.4064) -> bool:
	# Capsule centres include crouching, jumping and standing beside the buckets.
	# The previous aisle-only box ejected legitimate passengers at the cutoff.
	return (
		car_at(point) >= 0
		and absf(point.x) <= TRAIN_HALF_WIDTH - radius - 0.03
		and point.y >= 1.5
		and point.y <= 3.45
	)


## Anywhere a parked train's passenger space or doorways could hold a capsule.
static func in_car(point: Vector3) -> bool:
	return car_at(point) >= 0 and absf(point.x) < 1.95 and point.y > 1.2 and point.y < 3.5


static func inside_item(point: Vector3) -> bool:
	return car_at(point) >= 0 and absf(point.x) < 1.30 and point.y > 1.15 and point.y < 3.3


static func platform_recovery(point: Vector3, track_index: int = 0) -> Vector3:
	return Vector3(3.3 if track_index == 0 else -3.3, 2.15, clampf(point.z, -54, 54))
