class_name ProceduralPopulationRule
extends Resource
## Room-local spawn zones and permitted sets. Structural geometry never moves.

@export var allowed_sets: Array[String] = ["garage", "storage", "utility"]
@export var weights := PackedFloat32Array([5, 2, 1])
@export_range(0.0, 1.0) var density := 0.85
@export var allowed_yaws := PackedFloat32Array([0, PI])
@export var placement_bounds := AABB(Vector3(-19, 0, 8), Vector3(38, 3.5, 26))
@export var slots: Array[Vector3] = [
	Vector3(-15, 0, 14),
	Vector3(-15, 0, 22),
	Vector3(-15, 0, 30),
	Vector3(15, 0, 14),
	Vector3(15, 0, 22),
	Vector3(15, 0, 30)
]
@export var forbidden_volumes: Array[AABB] = [
	AABB(Vector3(-11, -0.1, 0), Vector3(22, 4, 42)),
	AABB(Vector3(-21, -0.1, 0), Vector3(42, 4, 8)),
	AABB(Vector3(-21, -0.1, 34), Vector3(42, 4, 8)),
	AABB(Vector3(-21, -0.1, 0), Vector3(2, 4, 42)),
	AABB(Vector3(19, -0.1, 0), Vector3(2, 4, 42))
]

## Optional catalogue. Empty retains the existing garage set contract.
@export var set_definitions: Array[ProceduralSetDefinition] = []
@export var room_tag := ""
