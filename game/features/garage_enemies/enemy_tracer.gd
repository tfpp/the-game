class_name EnemyTracer
extends MeshInstance3D
## A brief unshaded streak from a gunman to where it fired. Misses aim a little
## past the target so players can see the shot go wide.

const LIFETIME_S := 0.1


static func create(from: Vector3, to: Vector3, hit: bool) -> EnemyTracer:
	var tracer := EnemyTracer.new()
	tracer.top_level = true
	var end := to + Vector3.UP * 0.2
	if not hit:
		end += (to - from).normalized().cross(Vector3.UP) * 0.8
	var length := maxf(from.distance_to(end), 0.01)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, length)
	tracer.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.4)
	tracer.material_override = material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var middle := (from + end) * 0.5
	tracer.transform = Transform3D(Basis.looking_at(end - from), middle)
	return tracer


func _ready() -> void:
	get_tree().create_timer(LIFETIME_S).timeout.connect(queue_free)
