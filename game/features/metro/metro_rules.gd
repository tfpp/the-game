class_name MetroRules
extends RefCounted
## Timetable and coordinate rules. Four services, one stop apart on the same loop.

const NAMES: Array[String] = ["CROWN", "MARKET", "WORKS", "RESIDENCES"]
const OPEN := 1.2
const DWELL := 12.0
const CLOSE := 1.2
const TRAVEL := 10.0
const PERIOD := OPEN + DWELL + CLOSE + TRAVEL
const DEPART := OPEN + DWELL + CLOSE
const STATION_BOUNDS := AABB(Vector3(-6, -1, -92), Vector3(30, 9, 184))
const RIDE_BOUNDS := AABB(Vector3(-4, -1, -60), Vector3(8, 7, 120))
const PITCH := 22.86


static func station_position(index: int) -> Vector3:
	return Vector3(index * 600, 0, -8000)


static func ride_position(service: int) -> Vector3:
	return Vector3(service * 600, 0, -10000)


static func station(service: int, cycle: int) -> int:
	return posmod(service + cycle, 4)


static func aperture(time: float) -> float:
	if time < OPEN:
		return clampf(time / OPEN, 0, 1)
	if time < OPEN + DWELL:
		return 1.0
	if time < DEPART:
		return 1.0 - (time - OPEN - DWELL) / CLOSE
	return 0.0


static func train_z(time: float) -> float:
	if time <= DEPART:
		return 0.0
	var travel := time - DEPART
	if travel < 3:
		return -140.0 * pow(travel / 3.0, 2)
	if travel > 7:
		return 140.0 * pow((10.0 - travel) / 3.0, 2)
	return -200.0


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
	return (
		car_at(point) >= 0 and absf(point.x) <= 1.30 - radius and point.y >= 1.9 and point.y <= 3.0
	)


static func inside_item(point: Vector3) -> bool:
	return car_at(point) >= 0 and absf(point.x) < 1.30 and point.y > 1.15 and point.y < 3.3


static func platform_recovery(point: Vector3) -> Vector3:
	return Vector3(3.3, 2.15, clampf(point.z, -54, 54))
