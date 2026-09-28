class_name FrogNavigation
extends RefCounted
## Local hop steering against the live physics world. No baked map is required:
## probe supported landings, then sweep the frog's whole volume along the arc.

const TURN_ANGLES: Array[float] = [0.0, 0.52, -0.52, 1.05, -1.05, 1.57, -1.57, 2.1, -2.1, PI]
const ARC_STEPS := 12
const FLOOR_NORMAL_MIN := 0.75

var radius := 0.46
var body_shape := SphereShape3D.new()
var exclude: Array[RID] = []


func configure(size: float, excluded: RID) -> void:
	radius = 0.46 * size
	body_shape.radius = radius
	exclude = [excluded]


func find_hop(
	space: PhysicsDirectSpaceState3D,
	from: Vector3,
	direction: Vector3,
	distance: float,
	height: float,
	threat: Vector3 = Vector3.INF
) -> Dictionary:
	for turn: float in TURN_ANGLES:
		var heading := direction.rotated(Vector3.UP, turn)
		for fraction: float in [1.0, 0.6]:
			var target := from + heading * distance * fraction
			var ground := supported_ground(space, target)
			if ground.is_empty():
				continue
			target = ground["position"]
			# Sideways escapes are allowed when the direct route meets a wall.
			if (
				threat.is_finite()
				and target.distance_squared_to(threat) < from.distance_squared_to(threat)
			):
				continue
			if arc_is_clear(space, from, target, height):
				return {"target": target}
	return {}


func supported_ground(space: PhysicsDirectSpaceState3D, point: Vector3) -> Dictionary:
	var center := _ground_ray(space, point)
	if center.is_empty() or center["normal"].y < FLOOR_NORMAL_MIN:
		return {}
	var landing: Vector3 = center["position"]
	# Do not land with half the body hanging over a ledge or a narrow prop.
	for direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var edge := _ground_ray(space, landing + direction * radius * 0.8)
		if edge.is_empty() or edge["normal"].y < FLOOR_NORMAL_MIN:
			return {}
		var edge_position: Vector3 = edge["position"]
		if absf(edge_position.y - landing.y) > radius * 0.8:
			return {}
	return center


func arc_is_clear(
	space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, height: float
) -> bool:
	var previous := from
	for step: int in range(1, ARC_STEPS + 1):
		var next := FrogHop.arc_position(from, to, float(step) / ARC_STEPS, height)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body_shape
		query.collision_mask = 1
		query.exclude = exclude
		query.margin = 0.01
		query.transform.origin = previous + Vector3.UP * (radius + 0.04)
		if not space.intersect_shape(query, 1).is_empty():
			return false
		query.motion = next - previous
		if space.cast_motion(query)[0] < 1.0:
			return false
		previous = next
	return true


func _ground_ray(space: PhysicsDirectSpaceState3D, point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 0.65, point + Vector3.DOWN * 1.0, 1, exclude
	)
	var hit := space.intersect_ray(query)
	# Players and other moving bodies are obstacles, never stepping stones.
	if not hit.is_empty() and hit["collider"] is PhysicsBody3D:
		if hit["collider"] is AnimatableBody3D or not hit["collider"] is StaticBody3D:
			return {}
	return hit
