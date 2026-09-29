extends CPUParticles3D
## Local-only rain streaks. The server has no need to simulate weather particles.

const ACTIVE_RANGE_M := 55.0

var _check_elapsed := 0.0


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER or DisplayServer.get_name() == "headless":
		emitting = false
		return
	amount = 450
	lifetime = 1.2
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(23, 0.2, 23)
	direction = Vector3.DOWN
	spread = 2.0
	gravity = Vector3(0, -9.8, 0)
	initial_velocity_min = 17.0
	initial_velocity_max = 22.0
	var streak := QuadMesh.new()
	streak.size = Vector2(0.018, 0.42)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.58, 0.68, 0.78, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	streak.material = material
	mesh = streak
	emitting = false


func _process(delta: float) -> void:
	_check_elapsed += delta
	if _check_elapsed < 0.25:
		return
	_check_elapsed = 0.0
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	emitting = (
		player != null and player.global_position.distance_to(global_position) < ACTIVE_RANGE_M
	)
