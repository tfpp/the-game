class_name BlessingEffect
extends Node3D
## Short-lived local geometry driven by an authority-only event. No lights or shadows.

const LIFETIME := 2.0
var elapsed := 0.0
var _size := 1.0


func build(gambling: bool, size: float = 1.0) -> void:
	_size = size
	scale = Vector3.ONE * _size
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color("ffe28a") if gambling else Color("91ffcf")
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	# Two arcs sharing their tips form a true open crescent.
	for i: int in 24:
		var a := -PI * 0.5 + PI * i / 24.0
		var b := -PI * 0.5 + PI * (i + 1) / 24.0
		var outer_a := Vector3(-cos(a) * 0.5, sin(a) * 0.5, 0)
		var outer_b := Vector3(-cos(b) * 0.5, sin(b) * 0.5, 0)
		var inner_a := Vector3(-cos(a) * 0.18, sin(a) * 0.5, 0)
		var inner_b := Vector3(-cos(b) * 0.18, sin(b) * 0.5, 0)
		for vertex: Vector3 in [outer_a, outer_b, inner_a, inner_a, outer_b, inner_b]:
			mesh.surface_add_vertex(vertex)
	# Five-point star in the open side.
	var center := Vector3(0.14, 0.0, 0)
	for i: int in 10:
		var a := PI * 0.5 + TAU * i / 10.0
		var b := PI * 0.5 + TAU * (i + 1) / 10.0
		var ra := 0.23 if i % 2 == 0 else 0.10
		var rb := 0.10 if i % 2 == 0 else 0.23
		mesh.surface_add_vertex(center)
		mesh.surface_add_vertex(center + Vector3(cos(a), sin(a), 0) * ra)
		mesh.surface_add_vertex(center + Vector3(cos(b), sin(b), 0) * rb)
	mesh.surface_end()
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.visibility_range_end = 45.0
	add_child(view)
	if not gambling:
		var sparks := CPUParticles3D.new()
		sparks.amount = 24
		sparks.lifetime = 0.5
		sparks.local_coords = true
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.direction = Vector3.UP
		sparks.spread = 65.0
		sparks.initial_velocity_min = 0.2
		sparks.initial_velocity_max = 0.6
		sparks.gravity = Vector3.ZERO
		sparks.color = Color("91ffcf")
		var bead := SphereMesh.new()
		bead.radius = 0.035
		bead.height = 0.07
		bead.radial_segments = 4
		bead.rings = 2
		bead.material = material
		sparks.mesh = bead
		add_child(sparks)
		sparks.emitting = true


func _process(delta: float) -> void:
	elapsed += delta
	position.y += delta * 0.35
	scale = Vector3.ONE * _size * (1.0 + elapsed * 0.15)
	if elapsed >= LIFETIME:
		queue_free()
