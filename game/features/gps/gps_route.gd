class_name GpsRoute
extends RefCounted
## Pure routing helpers: which door to take next, a walkable path on the radar's
## wall slice, and turn-by-turn wording. No scene access, so it's easy to test.

## Cell size and half-width (metres) of the local pathfinding grid.
const CELL := 0.5
const HALF := 25.0
const ARRIVE_DISTANCE := 3.0


## Index of the smallest region containing `point`, or -1 for the open world.
static func region_of(regions: Array[AABB], point: Vector3) -> int:
	var best := -1
	var best_volume := INF
	for index: int in regions.size():
		if regions[index].has_point(point) and regions[index].get_volume() < best_volume:
			best = index
			best_volume = regions[index].get_volume()
	return best


## The next place to walk to on the way from `start` to `goal`. `links` are doors:
## `{"from": Vector3, "to": Vector3, "label": String}`. Returns
## `{"position": Vector3, "door": String}`; `door` is empty when `goal` is in the
## same region or no chain of doors reaches it.
static func next_hop(
	regions: Array[AABB], links: Array[Dictionary], start: Vector3, goal: Vector3
) -> Dictionary:
	var source := region_of(regions, start)
	var target := region_of(regions, goal)
	var direct := {"position": goal, "door": ""}
	if source == target:
		return direct
	# Breadth-first over regions, remembering the first door of each route.
	var first_door := {source: {}}
	var queue: Array[int] = [source]
	while not queue.is_empty():
		var region: int = queue.pop_front()
		for link: Dictionary in links:
			if region_of(regions, link["from"]) != region:
				continue
			var next := region_of(regions, link["to"])
			if first_door.has(next):
				continue
			first_door[next] = link if region == source else first_door[region]
			if next == target:
				var door: Dictionary = first_door[next]
				return {"position": door["from"], "door": door["label"]}
			queue.append(next)
	return direct


## A walkable polyline from `start` towards `goal` that avoids `walls` (pairs of
## points, as `RadarGeometry.walls`). If `goal` is outside the grid or walled off,
## the path ends at the reachable cell closest to it and then heads straight there.
static func grid_path(
	walls: PackedVector2Array, start: Vector2, goal: Vector2
) -> PackedVector2Array:
	var size := int(HALF * 2.0 / CELL)
	var origin := start - Vector2(HALF, HALF)
	var blocked := PackedByteArray()
	blocked.resize(size * size)
	for index: int in range(0, walls.size() - 1, 2):
		var a := walls[index]
		var b := walls[index + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / (CELL * 0.5)))
		for step: int in steps + 1:
			var cell := _cell(a.lerp(b, float(step) / steps), origin, size)
			if cell >= 0:
				blocked[cell] = 1
	var start_cell := _cell(start, origin, size)
	blocked[start_cell] = 0
	var parent := PackedInt32Array()
	parent.resize(size * size)
	parent.fill(-1)
	parent[start_cell] = start_cell
	var queue := PackedInt32Array([start_cell])
	var head := 0
	var best := start_cell
	var best_distance := _center(start_cell, origin, size).distance_to(goal)
	var goal_cell := _cell(goal, origin, size)
	while head < queue.size() and best != goal_cell:
		var cell := queue[head]
		head += 1
		var x := cell % size
		var y := cell / size
		for offset: Vector2i in [
			Vector2i(1, 0),
			Vector2i(-1, 0),
			Vector2i(0, 1),
			Vector2i(0, -1),
			Vector2i(1, 1),
			Vector2i(1, -1),
			Vector2i(-1, 1),
			Vector2i(-1, -1),
		]:
			var nx := x + offset.x
			var ny := y + offset.y
			if nx < 0 or ny < 0 or nx >= size or ny >= size:
				continue
			var next := ny * size + nx
			if parent[next] != -1 or blocked[next] == 1:
				continue
			# No squeezing diagonally between two wall cells.
			if blocked[y * size + nx] == 1 or blocked[ny * size + x] == 1:
				continue
			parent[next] = cell
			queue.append(next)
			var distance := _center(next, origin, size).distance_to(goal)
			if distance < best_distance - 0.01:
				best = next
				best_distance = distance
	var cells := PackedVector2Array()
	var cursor := best
	while cursor != start_cell:
		cells.append(_center(cursor, origin, size))
		cursor = parent[cursor]
	cells.append(start)
	cells.reverse()
	var path := _smooth(cells, blocked, origin, size)
	if path[path.size() - 1].distance_to(goal) > CELL:
		path.append(goal)
	return path


## Drops corners that can be skipped without crossing a blocked cell (string pulling).
static func _smooth(
	points: PackedVector2Array, blocked: PackedByteArray, origin: Vector2, size: int
) -> PackedVector2Array:
	if points.size() <= 2:
		return points
	var result := PackedVector2Array([points[0]])
	var anchor := 0
	for index: int in range(2, points.size()):
		if not _clear(points[anchor], points[index], blocked, origin, size):
			anchor = index - 1
			result.append(points[anchor])
	result.append(points[points.size() - 1])
	return result


static func _clear(
	a: Vector2, b: Vector2, blocked: PackedByteArray, origin: Vector2, size: int
) -> bool:
	var steps := maxi(1, ceili(a.distance_to(b) / (CELL * 0.5)))
	for step: int in steps + 1:
		var cell := _cell(a.lerp(b, float(step) / steps), origin, size)
		if cell >= 0 and blocked[cell] == 1:
			return false
	return true


## Path length in metres.
static func length(path: PackedVector2Array) -> float:
	var total := 0.0
	for index: int in range(1, path.size()):
		total += path[index - 1].distance_to(path[index])
	return total


## "left", "right" or "straight" for turning from direction `a` onto `b`, both on
## the ground plane as (x, z). Seen from above with north (-Z) up.
static func turn(a: Vector2, b: Vector2) -> String:
	var angle := rad_to_deg(a.angle_to(b))
	if absf(angle) < 30.0:
		return "straight"
	return "right" if angle > 0.0 else "left"


## One line of turn-by-turn guidance for `path` (starting at the player).
## `door` names the door at the end of this leg, if any.
static func instruction(path: PackedVector2Array, door: String, place: String) -> String:
	if path.size() < 2:
		return "Arrived at %s" % place
	var first := path[0].distance_to(path[1])
	if path.size() == 2:
		if door != "":
			return "%s in %s" % [door, meters(first)]
		if first <= ARRIVE_DISTANCE:
			return "Arrived at %s" % place
		return "Continue to %s, %s" % [place, meters(first)]
	var direction := turn(path[1] - path[0], path[2] - path[1])
	if direction == "straight":
		return "Continue straight for %s" % meters(first)
	return "Turn %s in %s" % [direction, meters(first)]


## Close enough to `goal` on the same storey to call it arrived.
static func arrived(position: Vector3, goal: Vector3) -> bool:
	var flat := Vector2(position.x - goal.x, position.z - goal.z).length()
	return flat <= ARRIVE_DISTANCE and absf(position.y - goal.y) < 2.5


static func meters(distance: float) -> String:
	return "%d m" % maxi(1, roundi(distance))


static func _cell(point: Vector2, origin: Vector2, size: int) -> int:
	var local := ((point - origin) / CELL).floor()
	if local.x < 0 or local.y < 0 or local.x >= size or local.y >= size:
		return -1
	return int(local.y) * size + int(local.x)


static func _center(cell: int, origin: Vector2, size: int) -> Vector2:
	return origin + (Vector2(cell % size, cell / size) + Vector2(0.5, 0.5)) * CELL
