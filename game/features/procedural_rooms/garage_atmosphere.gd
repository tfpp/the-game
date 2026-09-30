extends Node3D
## Local presentation for the live basement garage: a dark, foggy environment and hidden
## sun while the camera is inside, plus rain falling through the central atrium.
## Nothing here is shared state; every client derives it from its own camera.

const SYNTH := preload("res://features/parking_garage/procedural_audio.gd")
## Garage-local bounds of the decks, landings, sewer and pump room (below the casino cab).
const BOUNDS := AABB(Vector3(-34, -1, -13), Vector3(68, 22, 90))
## The open atrium between the deck strips, from the bottom slab to above B1.
const ATRIUM := AABB(Vector3(-10, 0, 12), Vector3(20, 20, 18))
const AMBIENT_COLOR := Color(0.42, 0.5, 0.6)
const AMBIENT_ENERGY := 0.1
const FOG_COLOR := Color(0.02, 0.025, 0.035)
const FOG_DENSITY := 0.035
static var _rain_stream: AudioStreamWAV

var rain: CPUParticles3D
var rain_voices: Array[AudioStreamPlayer3D] = []
var _camera: Camera3D
var _previous: Environment
var _dark: Environment
var _hidden_suns: Array[DirectionalLight3D] = []


func _ready() -> void:
	rain = _build_rain()
	add_child(rain)
	var pool := MeshInstance3D.new()
	pool.name = "RainPool"
	var plane := PlaneMesh.new()
	plane.size = Vector2(ATRIUM.size.x, ATRIUM.size.z)
	pool.mesh = plane
	pool.position = ATRIUM.get_center() * Vector3(1, 0, 1) + Vector3(0, -0.09, 0)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.05, 0.07, 0.08)
	water.roughness = 0.08
	water.metallic = 0.6
	pool.material_override = water
	add_child(pool)
	if Network.mode == Network.Mode.SERVER:
		return
	if _rain_stream == null:
		_rain_stream = SYNTH.rain_and_wind_loop(3107)
	for floor_index: int in 5:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Rain%d" % floor_index
		voice.stream = _rain_stream
		voice.bus = GameAudio.BUS
		voice.volume_db = -12
		voice.unit_size = 4
		voice.max_distance = 22
		voice.position = Vector3(0, floor_index * 4.0 + 1.5, ATRIUM.get_center().z)
		add_child(voice)
		rain_voices.append(voice)


static func contains(local_position: Vector3) -> bool:
	return BOUNDS.has_point(local_position)


func _build_rain() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = "Rain"
	particles.position = Vector3(0, ATRIUM.end.y, ATRIUM.get_center().z)
	particles.amount = 450
	particles.lifetime = 1.3
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(ATRIUM.size.x / 2 - 0.3, 0.1, ATRIUM.size.z / 2 - 0.3)
	particles.direction = Vector3.DOWN
	particles.spread = 3
	particles.initial_velocity_min = 7
	particles.initial_velocity_max = 9
	particles.gravity = Vector3(0, -18, 0)
	# Keep drops aligned with the camera so they stay visible from inside the atrium too.
	particles.local_coords = false
	var drop := QuadMesh.new()
	drop.size = Vector2(0.025, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.72, 0.82, 0.9, 0.35)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = true
	drop.material = material
	particles.mesh = drop
	particles.visibility_aabb = AABB(
		Vector3(-ATRIUM.size.x / 2, -ATRIUM.size.y - 1, -ATRIUM.size.z / 2),
		Vector3(ATRIUM.size.x, ATRIUM.size.y + 2, ATRIUM.size.z)
	)
	particles.emitting = false
	particles.visible = false
	return particles


func _process(_delta: float) -> void:
	update_camera(get_viewport().get_camera_3d())


func update_camera(camera: Camera3D) -> void:
	var inside := is_instance_valid(camera) and contains(to_local(camera.global_position))
	if rain.emitting != inside:
		rain.emitting = inside
		rain.visible = inside
		for voice: AudioStreamPlayer3D in rain_voices:
			if inside:
				voice.play()
			else:
				voice.stop()
	if camera != _camera or not inside:
		_restore()
	if not inside or _camera != null:
		return
	_camera = camera
	_previous = camera.environment
	var source := _previous if _previous != null else camera.get_world_3d().environment
	_dark = source.duplicate() as Environment if source != null else Environment.new()
	_dark.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_dark.ambient_light_color = AMBIENT_COLOR
	_dark.ambient_light_energy = AMBIENT_ENERGY
	_dark.ambient_light_sky_contribution = 0.0
	_dark.fog_enabled = true
	_dark.fog_light_color = FOG_COLOR
	_dark.fog_light_energy = 1.0
	_dark.fog_density = FOG_DENSITY
	_dark.fog_sky_affect = 0.0
	camera.environment = _dark
	# The unshadowed sun would otherwise light every deck floor through the concrete.
	for node: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		if sun.visible:
			sun.visible = false
			_hidden_suns.append(sun)


func _restore() -> void:
	if is_instance_valid(_camera) and _camera.environment == _dark:
		_camera.environment = _previous
	for sun: DirectionalLight3D in _hidden_suns:
		if is_instance_valid(sun):
			sun.visible = true
	_hidden_suns.clear()
	_camera = null
	_previous = null
	_dark = null


func _exit_tree() -> void:
	_restore()
