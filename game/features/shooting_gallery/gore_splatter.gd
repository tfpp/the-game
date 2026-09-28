class_name GoreSplatter
extends Node3D
## Extra blood flourish stacked on top of the shared flash/shockwave/limb debris
## every killable in the game already gets from
## features/animal_effects/mesh_explosion.gd — humanoid targets are the one thing
## in the game players are explicitly meant to gib, so they get a second, bloodier
## effect on top of that shared one. Purely cosmetic: each peer renders its own
## burst, nothing here is networked.

const GLOB_COUNT := 22
const DURATION_S := 0.9
const BLOOD_COLOR := Color(0.55, 0.02, 0.02)


static func spawn(source: Node3D, body: Node3D) -> GoreSplatter:
	var effect := GoreSplatter.new()
	effect.top_level = true
	effect.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	source.add_child(effect)
	effect.global_position = body.get_global_transform_interpolated().origin + Vector3.UP * 1.2
	effect._spawn_spray()
	var cleanup := effect.create_tween()
	cleanup.tween_interval(DURATION_S)
	cleanup.tween_callback(effect.queue_free)
	return effect


func _spawn_spray() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = BLOOD_COLOR
	material.roughness = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	for _i: int in GLOB_COUNT:
		var glob := MeshInstance3D.new()
		glob.mesh = mesh
		glob.material_override = material
		glob.scale = Vector3.ONE * randf_range(0.35, 1.3)
		add_child(glob)
		_launch(glob)


func _launch(glob: MeshInstance3D) -> void:
	var direction := (
		Vector3(randf_range(-1.0, 1.0), randf_range(0.1, 1.0), randf_range(-1.0, 1.0)).normalized()
	)
	var target := (
		glob.position + direction * randf_range(0.8, 3.5) + Vector3.DOWN * randf_range(0.5, 2.0)
	)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(glob, "position", target, DURATION_S).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	tween.tween_property(glob, "scale", Vector3.ZERO, DURATION_S).set_delay(DURATION_S * 0.3)
	tween.chain().tween_callback(glob.queue_free)
