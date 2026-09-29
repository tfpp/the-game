class_name SlotCelebration
extends Node3D
## Cosmetic win effects: fireworks above the cabinet and gold coins from the tray.
## Everything scales with the prize, is local to each peer and frees itself.

## Coins pour from the payout tray at the front of the cabinet (machine space).
const COIN_SLOT := Vector3(0, 0.5, 0.62)
const FIREWORK_HEIGHT := 4.5
const COLORS: Array[Color] = [
	Color("ffd34d"), Color("ff4f6d"), Color("4fd8ff"), Color("8cff5a"), Color("d77bff")
]

var _coin_mesh: CylinderMesh
var _spark_mesh: QuadMesh


## 0 for the smallest prize ($10) up to 1 for the largest ($30 billion).
static func intensity(payout_cents: int) -> float:
	if payout_cents <= 0:
		return 0.0
	return clampf((log(float(payout_cents)) / log(10.0) - 3.0) / 9.5, 0.0, 1.0)


static func rocket_count(payout_cents: int) -> int:
	return 1 + roundi(intensity(payout_cents) * 6.0)


static func sparks_per_rocket(payout_cents: int) -> int:
	return 24 + roundi(intensity(payout_cents) * 96.0)


static func burst_speed(payout_cents: int) -> float:
	return 3.0 + intensity(payout_cents) * 6.0


static func coin_count(payout_cents: int) -> int:
	return 10 + roundi(intensity(payout_cents) * 70.0)


func celebrate(payout_cents: int) -> void:
	_spawn_coins(payout_cents)
	var rockets := rocket_count(payout_cents)
	for index: int in rockets:
		var angle := TAU * float(index) / float(rockets) + randf() * 0.5
		var spread := 0.0 if rockets == 1 else 1.0 + intensity(payout_cents) * 2.5
		var offset := Vector3(cos(angle) * spread, randf_range(-0.4, 0.8), sin(angle) * spread)
		_launch(Vector3(0, FIREWORK_HEIGHT, 0.3) + offset, payout_cents, index * 0.3)


func clear() -> void:
	for child: Node in get_children():
		child.queue_free()


func _spawn_coins(payout_cents: int) -> void:
	if _coin_mesh == null:
		_coin_mesh = CylinderMesh.new()
		_coin_mesh.top_radius = 0.045
		_coin_mesh.bottom_radius = 0.045
		_coin_mesh.height = 0.012
		_coin_mesh.radial_segments = 10
		_coin_mesh.rings = 0
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color("f2c14e")
		gold.metallic = 0.8
		gold.roughness = 0.35
		gold.emission_enabled = true
		gold.emission = Color("7a5410")
		_coin_mesh.material = gold
	var coins := CPUParticles3D.new()
	coins.name = "Coins"
	coins.mesh = _coin_mesh
	coins.position = COIN_SLOT
	coins.amount = coin_count(payout_cents)
	coins.lifetime = 1.6
	coins.one_shot = true
	coins.explosiveness = 0.0
	coins.local_coords = false
	coins.direction = Vector3(0, 0.6, 1)
	coins.spread = 25.0
	coins.initial_velocity_min = 1.5
	coins.initial_velocity_max = 3.0
	coins.gravity = Vector3(0, -9.8, 0)
	coins.angular_velocity_min = -540.0
	coins.angular_velocity_max = 540.0
	coins.particle_flag_rotate_y = true
	coins.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	coins.emission_box_extents = Vector3(0.12, 0.02, 0.02)
	add_child(coins, true)
	coins.emitting = true
	coins.finished.connect(coins.queue_free)


func _launch(target: Vector3, payout_cents: int, delay: float) -> void:
	var color: Color = COLORS[randi() % COLORS.size()]
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	var ball := SphereMesh.new()
	ball.radius = 0.06
	ball.height = 0.12
	ball.radial_segments = 6
	ball.rings = 3
	ball.material = _glow(color)
	shell.mesh = ball
	shell.position = Vector3(0, 2.6, 0.3)
	shell.visible = false
	add_child(shell, true)
	var tween := shell.create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(shell.show)
	tween.tween_property(shell, "position", target, 0.6).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_burst.bind(target, color, payout_cents))
	tween.tween_callback(shell.queue_free)


func _burst(at: Vector3, color: Color, payout_cents: int) -> void:
	if _spark_mesh == null:
		_spark_mesh = QuadMesh.new()
		_spark_mesh.size = Vector2(0.12, 0.12)
	var sparks := CPUParticles3D.new()
	sparks.name = "Burst"
	var size := 1.0 + intensity(payout_cents) * 1.5
	var mesh := _spark_mesh.duplicate() as QuadMesh
	mesh.size *= size
	var material := _glow(color)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	sparks.mesh = mesh
	sparks.position = at
	sparks.amount = sparks_per_rocket(payout_cents)
	sparks.lifetime = 1.2 + intensity(payout_cents) * 0.6
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 180.0
	var speed := burst_speed(payout_cents)
	sparks.initial_velocity_min = speed * 0.8
	sparks.initial_velocity_max = speed
	sparks.damping_min = speed * 0.6
	sparks.damping_max = speed * 0.8
	sparks.gravity = Vector3(0, -2.0, 0)
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	sparks.color_ramp = fade
	add_child(sparks, true)
	sparks.emitting = true
	sparks.finished.connect(sparks.queue_free)


func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	return material
