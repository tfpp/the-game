class_name SlotCelebration
extends Node3D
## Bounded, reusable local win effects. No nodes, meshes, materials or tweens
## are created at payout or burst time; idle pools do not process.

const COIN_SLOT := Vector3(0, 0.5, 0.62)
const FIREWORK_HEIGHT := 4.5
const MAX_ROCKETS := 7
const VIEW_RANGE := 35.0
const COLORS: Array[Color] = [
	Color("ffd34d"), Color("ff4f6d"), Color("4fd8ff"), Color("8cff5a"), Color("d77bff")
]

static var _coin_mesh: CylinderMesh
static var _shell_meshes: Array[SphereMesh] = []
static var _spark_meshes: Array[QuadMesh] = []
static var _fade: Gradient
static var _warmed := false

var _coins: CPUParticles3D
var _shells: Array[MeshInstance3D] = []
var _bursts: Array[CPUParticles3D] = []
var _targets: Array[Vector3] = []
var _launched := 0
var _elapsed := 0.0


func _ready() -> void:
	set_process(false)
	# Dedicated servers have no reason to allocate cosmetic particle pools.
	if Network.mode == Network.Mode.SERVER or Network.has_flag("server"):
		return
	_build_resources()
	_coins = CPUParticles3D.new()
	_coins.name = "Coins"
	_coins.emitting = false
	_coins.visible = false
	_coins.mesh = _coin_mesh
	_coins.position = COIN_SLOT
	_coins.lifetime = 1.6
	_coins.one_shot = true
	_coins.local_coords = false
	_coins.direction = Vector3(0, 0.6, 1)
	_coins.spread = 25.0
	_coins.initial_velocity_min = 1.5
	_coins.initial_velocity_max = 3.0
	_coins.gravity = Vector3(0, -9.8, 0)
	_coins.angular_velocity_min = -540.0
	_coins.angular_velocity_max = 540.0
	_coins.particle_flag_rotate_y = true
	_coins.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_coins.emission_box_extents = Vector3(0.12, 0.02, 0.02)
	_coins.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_coins)
	for index: int in MAX_ROCKETS:
		var shell := MeshInstance3D.new()
		shell.name = "Shell%d" % index
		shell.mesh = _shell_meshes[index % COLORS.size()]
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shell.visible = false
		add_child(shell)
		_shells.append(shell)
		var sparks := CPUParticles3D.new()
		sparks.name = "Burst%d" % index
		sparks.emitting = false
		sparks.visible = false
		sparks.mesh = _spark_meshes[index % COLORS.size()]
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.direction = Vector3.UP
		sparks.spread = 180.0
		sparks.gravity = Vector3(0, -2.0, 0)
		sparks.color_ramp = _fade
		sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sparks)
		_bursts.append(sparks)
	set_process(DisplayServer.get_name() != "headless" and not _warmed)


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
	if _coins == null or payout_cents <= 0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_to(global_position) > VIEW_RANGE:
		return
	clear()
	_coins.visible = true
	_coins.amount = coin_count(payout_cents)
	_coins.restart()
	var rockets := rocket_count(payout_cents)
	for index: int in rockets:
		var angle := TAU * float(index) / float(rockets) + randf() * 0.5
		var spread := 0.0 if rockets == 1 else 1.0 + intensity(payout_cents) * 2.5
		var offset := Vector3(cos(angle) * spread, randf_range(-0.4, 0.8), sin(angle) * spread)
		_targets.append(Vector3(0, FIREWORK_HEIGHT, 0.3) + offset)
		var sparks := _bursts[index]
		sparks.amount = sparks_per_rocket(payout_cents)
		sparks.lifetime = 1.2 + intensity(payout_cents) * 0.6
		sparks.scale_amount_min = 1.0 + intensity(payout_cents) * 1.5
		sparks.scale_amount_max = sparks.scale_amount_min
		var speed := burst_speed(payout_cents)
		sparks.initial_velocity_min = speed * 0.8
		sparks.initial_velocity_max = speed
		sparks.damping_min = speed * 0.6
		sparks.damping_max = speed * 0.8
	_process(0.0)
	set_process(true)


func _process(delta: float) -> void:
	if _targets.is_empty():
		if _warmed:
			set_process(false)
			return
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			_warm_up(camera)
			set_process(false)
		return
	_elapsed += delta
	for index: int in _targets.size():
		var age := _elapsed - index * 0.3
		var shell := _shells[index]
		shell.visible = age >= 0.0 and age < 0.6
		if shell.visible:
			var progress := clampf(age / 0.6, 0.0, 1.0)
			shell.position = Vector3(0, 2.6, 0.3).lerp(
				_targets[index], 1.0 - pow(1.0 - progress, 2)
			)
		if age >= 0.6 and index >= _launched:
			var sparks := _bursts[index]
			sparks.position = _targets[index]
			sparks.visible = true
			sparks.restart()
			_launched = index + 1
	if _elapsed > 4.5:
		clear()


func clear() -> void:
	set_process(_coins != null and DisplayServer.get_name() != "headless" and not _warmed)
	_elapsed = 0.0
	_launched = 0
	_targets.clear()
	if _coins != null:
		_coins.emitting = false
		_coins.visible = false
	for shell: MeshInstance3D in _shells:
		shell.visible = false
	for sparks: CPUParticles3D in _bursts:
		sparks.emitting = false
		sparks.visible = false


static func _build_resources() -> void:
	if _coin_mesh != null:
		return
	_coin_mesh = CylinderMesh.new()
	_coin_mesh.top_radius = 0.045
	_coin_mesh.bottom_radius = 0.045
	_coin_mesh.height = 0.012
	_coin_mesh.radial_segments = 10
	_coin_mesh.rings = 0
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("f2c14e")
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_coin_mesh.material = gold
	_fade = Gradient.new()
	_fade.set_color(0, Color.WHITE)
	_fade.set_color(1, Color(1, 1, 1, 0))
	for color: Color in COLORS:
		var ball := SphereMesh.new()
		ball.radius = 0.06
		ball.height = 0.12
		ball.radial_segments = 6
		ball.rings = 3
		ball.material = _glow(color)
		_shell_meshes.append(ball)
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.12, 0.12)
		var material := _glow(color)
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.vertex_color_use_as_albedo = true
		mesh.material = material
		_spark_meshes.append(mesh)


## Follow GunFx's startup warm-up pattern, but draw actual CPU-particle variants
## as well as shells, so the web renderer compiles them before the first payout.
static func _warm_up(camera: Camera3D) -> void:
	_warmed = true
	var holder := Node3D.new()
	holder.name = "SlotFxWarmUp"
	camera.add_child(holder)
	holder.position = Vector3(0, 0, -0.5)
	var meshes: Array[Mesh] = [_coin_mesh]
	meshes.append_array(_spark_meshes)
	for mesh: Mesh in meshes:
		var particles := CPUParticles3D.new()
		particles.emitting = false
		particles.mesh = mesh
		particles.amount = 1
		particles.lifetime = 0.1
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.gravity = Vector3.ZERO
		particles.scale_amount_min = 0.001
		particles.scale_amount_max = 0.001
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(particles)
		particles.restart()
	for mesh: SphereMesh in _shell_meshes:
		var shell := MeshInstance3D.new()
		shell.mesh = mesh
		shell.scale = Vector3.ONE * 0.001
		shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(shell)
	var tree := camera.get_tree()
	for _frame: int in 3:
		await tree.process_frame
	if is_instance_valid(holder):
		holder.queue_free()


static func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	return material
