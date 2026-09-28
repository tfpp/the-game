class_name MeshExplosion
extends Node3D
## Shared cosmetic flash, shockwave and tumbling model pieces. Each peer renders
## its own effect; only the animal's authoritative death event is networked.

const DEBRIS_DURATION_S := 1.1
const FLASH_DURATION_S := 0.3
const SHOCKWAVE_DURATION_S := 0.5


static func spawn(source: Node3D, body: Node3D) -> MeshExplosion:
	var effect := MeshExplosion.new()
	effect.top_level = true
	effect.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	source.add_child(effect)
	effect.global_position = source.get_global_transform_interpolated().origin
	GameAudio.play_at(source, &"explosion", effect.global_position)
	effect._spawn_flash()
	effect._spawn_shockwave()
	effect._spawn_debris(body)
	var cleanup := effect.create_tween()
	cleanup.tween_interval(DEBRIS_DURATION_S)
	cleanup.tween_callback(effect.queue_free)
	return effect


func _spawn_flash() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.2)
	light.light_energy = 6.0
	light.omni_range = 4.0
	light.position = Vector3(0.0, 0.2, 0.0)
	add_child(light)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, FLASH_DURATION_S)
	tween.tween_callback(light.queue_free)


func _spawn_shockwave() -> void:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.6
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.2, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.set_surface_override_material(0, mat)
	sphere.position = Vector3(0.0, 0.2, 0.0)
	add_child(sphere)
	var tween := create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(sphere, "scale", Vector3.ONE * 6.0, SHOCKWAVE_DURATION_S)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(mat, "albedo_color:a", 0.0, SHOCKWAVE_DURATION_S)
	tween.chain().tween_callback(sphere.queue_free)


## Reuse the model meshes and materials, including nested limbs and their scale.
func _spawn_debris(body: Node3D) -> void:
	for mesh: MeshInstance3D in _mesh_pieces(body):
		var piece := MeshInstance3D.new()
		piece.mesh = mesh.mesh
		piece.material_override = mesh.material_override
		for surface: int in mesh.get_surface_override_material_count():
			piece.set_surface_override_material(
				surface, mesh.get_surface_override_material(surface)
			)
		add_child(piece)
		piece.global_transform = mesh.get_global_transform_interpolated()
		_launch_piece(piece)


func _mesh_pieces(node: Node) -> Array[MeshInstance3D]:
	var pieces: Array[MeshInstance3D] = []
	for child: Node in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			pieces.append(mesh)
		pieces.append_array(_mesh_pieces(child))
	return pieces


func _launch_piece(piece: MeshInstance3D) -> void:
	var direction := (
		Vector3(randf_range(-1.0, 1.0), randf_range(0.5, 1.4), randf_range(-1.0, 1.0)).normalized()
	)
	var target := piece.position + direction * randf_range(1.2, 3.2)
	var spin := Vector3(
		randf_range(-720.0, 720.0), randf_range(-720.0, 720.0), randf_range(-720.0, 720.0)
	)
	var tween := create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(piece, "position", target, DEBRIS_DURATION_S)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_property(piece, "rotation_degrees", spin, DEBRIS_DURATION_S)
	tween.chain().tween_callback(piece.queue_free)
