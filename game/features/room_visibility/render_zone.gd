class_name RenderZone
extends Node3D
## Always-loaded gameplay scene with a private camera render layer.
## Collision, RPCs and simulation are never disabled by render selection.

@export_range(19, 20) var render_layer := 19
@export var render_bounds := AABB(Vector3(-20, -1, -15), Vector3(40, 35, 45))


func _enter_tree() -> void:
	add_to_group(&"render_zones")


func contains(point: Vector3) -> bool:
	return render_bounds.has_point(to_local(point))


func render_mask() -> int:
	return 1 << (render_layer - 1)
