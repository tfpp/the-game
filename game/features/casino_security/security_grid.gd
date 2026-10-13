class_name SecurityGrid
extends RefCounted
## Where a guard can walk in the main hall, probed once from the real collision
## (casino GridMap, slot machines, tables, booths...) on the server, and the
## routes between two points over it. Cells are CELL metres square. Each holds the
## floor height under its centre and whether a guard-sized cylinder fits on it.
## Building is incremental (`build_step`) so it never stalls a web frame.

const CELL := 0.5
## Guard body probe: radius and the height kept clear above the floor.
const RADIUS := 0.3
const CLEAR_HEIGHT := 1.5
## Probe a cylinder this far above the floor, so ramps and thresholds don't count.
const STEP := 0.3
## Neighbouring cells further apart in height than this are not connected.
const MAX_STEP := 0.3
## Downward rays start here, under the mariachi balcony, and stop below the pit.
const RAY_TOP := 2.6
const RAY_BOTTOM := -2.2
## Neighbour steps: four sides, then four diagonals.
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]
## Slightly greedy A* (straight routes, far fewer cells searched).
const HEURISTIC := 1.2

var origin := Vector2.ZERO
var width := 0
var depth := 0
## Floor height per cell (NAN when nothing walkable-flat was found).
var heights := PackedFloat32Array()
var walkable := PackedByteArray()
## Per cell, a bit per DIRECTIONS entry it connects to (built after probing).
var _links := PackedByteArray()
var _offsets := PackedInt32Array()
var _next := 0


## Covers `area` (a world AABB; only x/z matter) with cells.
func _init(area: AABB) -> void:
	origin = Vector2(area.position.x, area.position.z)
	width = maxi(1, ceili(area.size.x / CELL))
	depth = maxi(1, ceili(area.size.z / CELL))
	heights.resize(width * depth)
	walkable.resize(width * depth)
	_links.resize(width * depth)
	for d: Vector2i in DIRECTIONS:
		_offsets.append(d.y * width + d.x)


func is_ready() -> bool:
	return _next >= width * depth * 2


func cell_count() -> int:
	return width * depth


## Probes up to `budget` more cells, then links them up in a second pass of the
## same budget. `exclude` holds RIDs to ignore (players).
func build_step(space: PhysicsDirectSpaceState3D, budget: int, exclude: Array[RID]) -> void:
	var cylinder := CylinderShape3D.new()
	cylinder.radius = RADIUS
	cylinder.height = CLEAR_HEIGHT - STEP
	var shape := PhysicsShapeQueryParameters3D.new()
	shape.shape = cylinder
	shape.collision_mask = 1
	shape.exclude = exclude
	var count := width * depth
	var start := _next
	var stop := mini(_next + budget, count)
	while _next < stop:
		var index := _next
		_next += 1
		var at := center(index)
		var ray := PhysicsRayQueryParameters3D.create(
			Vector3(at.x, RAY_TOP, at.y), Vector3(at.x, RAY_BOTTOM, at.y), 1, exclude
		)
		var hit := space.intersect_ray(ray)
		heights[index] = NAN
		walkable[index] = 0
		if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
			continue
		var floor_y := (hit["position"] as Vector3).y
		heights[index] = floor_y
		shape.transform = Transform3D(
			Basis.IDENTITY, Vector3(at.x, floor_y + STEP + (CLEAR_HEIGHT - STEP) * 0.5, at.y)
		)
		walkable[index] = 1 if space.intersect_shape(shape, 1).is_empty() else 0
	stop = mini(_next + budget - (_next - start), count * 2)
	while _next < stop:
		_links[_next - count] = _link(_next - count)
		_next += 1


## Builds every remaining cell at once (tests and tools).
func build_all(space: PhysicsDirectSpaceState3D, exclude: Array[RID] = []) -> void:
	build_step(space, width * depth * 2, exclude)


func center(index: int) -> Vector2:
	@warning_ignore("integer_division")
	var row := index / width
	return origin + Vector2((index % width + 0.5) * CELL, (row + 0.5) * CELL)


## Cell index under a world point, or -1 outside the grid.
func index_at(point: Vector3) -> int:
	var x := floori((point.x - origin.x) / CELL)
	var z := floori((point.z - origin.y) / CELL)
	if x < 0 or z < 0 or x >= width or z >= depth:
		return -1
	return z * width + x


func is_walkable(point: Vector3) -> bool:
	var index := index_at(point)
	return index >= 0 and walkable[index] == 1


## Floor height under `point`, or `fallback` off the walkable grid.
func floor_at(point: Vector3, fallback: float) -> float:
	var index := index_at(point)
	if index < 0 or walkable[index] == 0:
		return fallback
	return heights[index]


## Nearest walkable cell to `point` within `radius` metres whose floor is within
## `below` metres under and `above` metres over the point's height; -1 if none.
func nearest(point: Vector3, radius: float, below: float = 0.6, above: float = 0.6) -> int:
	var best := -1
	var best_distance := INF
	var reach := ceili(radius / CELL)
	var home := index_at(point)
	@warning_ignore("integer_division")
	var hz := home / width if home >= 0 else floori((point.z - origin.y) / CELL)
	var hx := home % width if home >= 0 else floori((point.x - origin.x) / CELL)
	for dz: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var x := hx + dx
			var z := hz + dz
			if x < 0 or z < 0 or x >= width or z >= depth:
				continue
			var index := z * width + x
			if walkable[index] == 0:
				continue
			var rise := heights[index] - point.y
			if rise < -below or rise > above:
				continue
			var distance := center(index).distance_to(Vector2(point.x, point.z))
			if distance <= radius and distance < best_distance:
				best = index
				best_distance = distance
	return best


## A walkable route from `from` to within `goal_radius` of `to`, as world points on
## the floor (smoothed to straight, clear legs). `to_below` lets the route end on
## floor under a target standing on furniture. Empty when there is no route.
func route(
	from: Vector3, to: Vector3, goal_radius: float = 0.75, to_below: float = 0.6
) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var start := nearest(from, 1.5, 1.0, 1.0)
	if start < 0:
		return points
	var goals: Dictionary[int, bool] = {}
	var reach := ceili(goal_radius / CELL)
	var target := Vector2(to.x, to.z)
	for dz: int in range(-reach, reach + 1):
		for dx: int in range(-reach, reach + 1):
			var probe := to + Vector3(dx * CELL, 0, dz * CELL)
			var index := index_at(probe)
			if index < 0 or walkable[index] == 0 or goals.has(index):
				continue
			var rise := heights[index] - to.y
			if center(index).distance_to(target) > goal_radius or rise > 0.6 or rise < -to_below:
				continue
			goals[index] = true
	if goals.is_empty():
		return points
	var cells := _search(start, goals, target)
	if cells.is_empty():
		return points
	for index: int in _smooth(cells):
		var at := center(index)
		points.append(Vector3(at.x, heights[index], at.y))
	return points


## A* over the 8-connected walkable cells, stopping at the first goal reached.
func _search(start: int, goals: Dictionary[int, bool], target: Vector2) -> PackedInt32Array:
	var count := width * depth
	var cost := PackedFloat32Array()
	cost.resize(count)
	cost.fill(INF)
	var came := PackedInt32Array()
	came.resize(count)
	var closed := PackedByteArray()
	closed.resize(count)
	cost[start] = 0.0
	came[start] = -1
	var heap := MinHeap.new()
	heap.push(center(start).distance_to(target), start)
	var found := -1
	while not heap.is_empty():
		var current := heap.pop()
		if closed[current] == 1:
			continue
		closed[current] = 1
		if goals.has(current):
			found = current
			break
		var links := _links[current]
		for direction: int in 8:
			if links & (1 << direction) == 0:
				continue
			var next := current + _offsets[direction]
			if closed[next] == 1:
				continue
			var total := cost[current] + (CELL if direction < 4 else CELL * 1.4142135)
			if total < cost[next]:
				cost[next] = total
				came[next] = current
				heap.push(total + HEURISTIC * center(next).distance_to(target), next)
	var path := PackedInt32Array()
	while found >= 0:
		path.append(found)
		found = came[found]
	path.reverse()
	return path


## Which of the 8 neighbours (DIRECTIONS order) a cell connects to: walkable, a
## small step apart, and, diagonally, not cutting a blocked corner.
func _link(index: int) -> int:
	var x := index % width
	@warning_ignore("integer_division")
	var z := index / width
	var mask := 0
	if walkable[index] == 0:
		return mask
	for direction: int in 8:
		var d := DIRECTIONS[direction]
		if not _joined(x, z, x + d.x, z + d.y):
			continue
		if direction >= 4 and (not _joined(x, z, x + d.x, z) or not _joined(x, z, x, z + d.y)):
			continue
		mask |= 1 << direction
	return mask


func _joined(x: int, z: int, nx: int, nz: int) -> bool:
	if nx < 0 or nz < 0 or nx >= width or nz >= depth:
		return false
	var a := z * width + x
	var b := nz * width + nx
	return walkable[b] == 1 and absf(heights[a] - heights[b]) <= MAX_STEP


## Drops cells while the straight leg between kept cells stays walkable.
func _smooth(cells: PackedInt32Array) -> PackedInt32Array:
	var kept := PackedInt32Array([cells[0]])
	var anchor := 0
	var index := 1
	while index < cells.size():
		var reach := index
		while reach + 1 < cells.size() and clear_leg(cells[anchor], cells[reach + 1]):
			reach += 1
		kept.append(cells[reach])
		anchor = reach
		index = reach + 1
	return kept


## True when walking straight between two cells crosses only joined cells.
func clear_leg(a: int, b: int) -> bool:
	var from := center(a)
	var to := center(b)
	var steps := maxi(1, ceili(from.distance_to(to) / (CELL * 0.25)))
	var last := a
	for step: int in range(1, steps + 1):
		var at := from.lerp(to, float(step) / steps)
		var index := index_at(Vector3(at.x, 0, at.y))
		if index == last:
			continue
		if index < 0 or walkable[index] == 0:
			return false
		var lx := last % width
		var ix := index % width
		@warning_ignore("integer_division")
		var lz := last / width
		@warning_ignore("integer_division")
		var iz := index / width
		if absi(lx - ix) > 1 or absi(lz - iz) > 1 or not _joined(lx, lz, ix, iz):
			return false
		if lx != ix and lz != iz and (not _joined(lx, lz, ix, lz) or not _joined(lx, lz, lx, iz)):
			return false
		last = index
	return true


## Binary min-heap of cell indices keyed by priority.
class MinHeap:
	var _keys := PackedFloat32Array()
	var _values := PackedInt32Array()

	func is_empty() -> bool:
		return _values.is_empty()

	func push(key: float, value: int) -> void:
		_keys.append(key)
		_values.append(value)
		var child := _values.size() - 1
		while child > 0:
			@warning_ignore("integer_division")
			var parent := (child - 1) / 2
			if _keys[parent] <= _keys[child]:
				break
			_swap(parent, child)
			child = parent

	func pop() -> int:
		var top := _values[0]
		var last := _values.size() - 1
		_swap(0, last)
		_keys.resize(last)
		_values.resize(last)
		var parent := 0
		while true:
			var smallest := parent
			for child: int in [parent * 2 + 1, parent * 2 + 2]:
				if child < last and _keys[child] < _keys[smallest]:
					smallest = child
			if smallest == parent:
				break
			_swap(parent, smallest)
			parent = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var key := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = key
		var value := _values[a]
		_values[a] = _values[b]
		_values[b] = value
