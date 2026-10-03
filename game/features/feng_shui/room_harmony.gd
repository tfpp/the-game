class_name FengShuiRoom
extends RefCounted
## On-demand, deterministic room harmony. Inputs are snapshots in local X/Z metres.
## No clock, processing, RPC or player state. Optional authored-scene snapshots are lazy.

const Furniture := preload("res://features/feng_shui/furniture.gd")
const AuthoredScene := preload("res://features/feng_shui/authored_scene.gd")
const MAX_FOOTPRINTS := 512
const ELEMENT_COUNT := 5
const ENTRY_CLEARANCE := 1.0

var _floor := Rect2()
var _entrance := Vector2.ZERO
var _footprints: Array[Rect2] = []
var _elements := PackedFloat64Array()
var _configured := false
var _dirty := true
var _cached: Dictionary = {}
var _scene: PackedScene
var _scene_floor_height := 0.0


## Elements are wood, fire, earth, metal, water (nonnegative relative weights).
## Invalid replacements return false and preserve the previous layout/cache.
## Footprints may cross the room boundary; evaluation clips them to the floor.
func set_layout(
	floor_rect: Rect2, entrance: Vector2, footprints: Array[Rect2], elements: PackedFloat64Array
) -> bool:
	if (
		not _valid_rect(floor_rect)
		or not _valid_rect(
			Rect2(floor_rect.position + floor_rect.size * 0.4, floor_rect.size * 0.2)
		)
		or not entrance.is_finite()
	):
		return false
	# Rect2.has_point excludes maximum edges; entrances on any edge are legal.
	if entrance.clamp(floor_rect.position, floor_rect.end) != entrance:
		return false
	if footprints.size() > MAX_FOOTPRINTS or not _valid_elements(elements):
		return false
	for footprint: Rect2 in footprints:
		if not _valid_rect(footprint):
			return false
	_scene = null
	_floor = floor_rect
	_entrance = entrance
	_footprints = footprints.duplicate()
	_elements = elements.duplicate()
	_configured = true
	_dirty = true
	return true


## Snapshot an already generated room, without retaining scene nodes.
## Future furniture only needs metadata/feng_shui_element; geometry supplies its footprint.
func set_furnished_layout(
	floor_rect: Rect2, entrance: Vector2, root: Node3D, floor_height: float = 0.0
) -> bool:
	if root == null or not is_finite(floor_height):
		return false
	var snapshot := Furniture.snapshot(root, floor_rect, floor_height)
	if not snapshot["valid"]:
		return false
	var footprints: Array[Rect2] = []
	footprints.assign(snapshot["footprints"])
	return set_layout(floor_rect, entrance, footprints, snapshot["elements"])


## Static authored interiors, including unloaded StreamedRoom.room_scene.
## No geometry scan until the first evaluation; never enter the tree or run scripts.
## Runtime-generated furniture must instead use set_furnished_layout after generation.
func set_scene_layout(
	floor_rect: Rect2, entrance: Vector2, scene: PackedScene, floor_height: float = 0.0
) -> bool:
	if (
		scene == null
		or not is_finite(floor_height)
		or not scene.can_instantiate()
		or not set_layout(floor_rect, entrance, [], PackedFloat64Array([0, 0, 0, 0, 0]))
	):
		return false
	_scene = scene.duplicate() as PackedScene
	_scene_floor_height = floor_height
	return true


## Score 0..100 plus normalized 0..1 components. Unconfigured results are invalid.
## Return a copy so callers cannot change a subsequent query's result.
func evaluation() -> Dictionary:
	if not _configured:
		return {"valid": false, "score": 0.0, "components": {}}
	if _dirty:
		_cached = _compute_evaluation()
		_dirty = false
	return _cached.duplicate(true)


func score() -> float:
	return float(evaluation()["score"])


## Discard session/layout data. The next query stays invalid until set_layout().
func clear() -> void:
	_configured = false
	_scene = null
	_dirty = true
	_cached.clear()
	_footprints.clear()
	_elements.clear()


func _compute_evaluation() -> Dictionary:
	if _scene != null:
		var instance := AuthoredScene.geometry(_scene)
		var accepted := set_furnished_layout(
			_floor, _entrance, instance as Node3D, _scene_floor_height
		)
		instance.free()
		if not accepted:
			return {"valid": false, "score": 0.0, "components": {}}
	var occupied: Array[Rect2] = []
	var entry := 1.0
	for footprint: Rect2 in _footprints:
		var clipped := _floor.intersection(footprint)
		if not clipped.has_area():
			continue
		occupied.append(clipped)
		var nearest := _entrance.clamp(clipped.position, clipped.end)
		entry = minf(entry, _entrance.distance_to(nearest) / ENTRY_CLEARANCE)
	var centre := Rect2(_floor.position + _floor.size * 0.4, _floor.size * 0.2)
	var central_occupied: Array[Rect2] = []
	for footprint: Rect2 in occupied:
		var clipped := centre.intersection(footprint)
		if clipped.has_area():
			central_occupied.append(clipped)
	var components := {
		"entrance": clampf(entry, 0.0, 1.0),
		"centre": clampf(1.0 - _union_area(central_occupied) / centre.get_area(), 0.0, 1.0),
		"space": clampf(1.0 - _union_area(occupied) / _floor.get_area(), 0.0, 1.0),
		"elements": _element_balance(),
	}
	var result := 0.0
	for value: float in components.values():
		result += value * 25.0
	return {"valid": true, "score": clampf(result, 0.0, 100.0), "components": components}


func _element_balance() -> float:
	var total := 0.0
	for weight: float in _elements:
		total += weight
	# Unspecified elements are neutral, not a perfect five-element balance.
	if total == 0.0:
		return 0.5
	var deviation := 0.0
	for weight: float in _elements:
		deviation += absf(weight / total - 0.2)
	# Equal shares score 1; one dominant element scores 0 (maximum L1 distance 1.6).
	return clampf(1.0 - deviation / 1.6, 0.0, 1.0)


static func _valid_elements(elements: PackedFloat64Array) -> bool:
	if elements.size() != ELEMENT_COUNT:
		return false
	var total := 0.0
	for weight: float in elements:
		if not is_finite(weight) or weight < 0.0:
			return false
		total += weight
	return is_finite(total)


static func _valid_rect(rect: Rect2) -> bool:
	return (
		rect.position.is_finite()
		and rect.size.is_finite()
		and rect.end.is_finite()
		and rect.size.x > 0.0
		and rect.size.y > 0.0
		and rect.end.x > rect.position.x
		and rect.end.y > rect.position.y
		and is_finite(rect.get_area())
		and rect.get_area() > 0.0
	)


## Exact rectangle union, not a sum: overlapping furniture is never counted twice.
## Bounded O(n^2 log n), performed only once per queried layout revision.
static func _union_area(rects: Array[Rect2]) -> float:
	var edges: Array[float] = []
	for rect: Rect2 in rects:
		edges.append(rect.position.x)
		edges.append(rect.end.x)
	edges.sort()
	var area := 0.0
	for index: int in range(1, edges.size()):
		var left := edges[index - 1]
		var right := edges[index]
		if right <= left:
			continue
		var intervals: Array[Vector2] = []
		for rect: Rect2 in rects:
			if rect.position.x < right and rect.end.x > left:
				intervals.append(Vector2(rect.position.y, rect.end.y))
		intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var length := 0.0
		var end := -INF
		for interval: Vector2 in intervals:
			length += maxf(0.0, interval.y - maxf(end, interval.x))
			end = maxf(end, interval.y)
		area += (right - left) * length
	return area
