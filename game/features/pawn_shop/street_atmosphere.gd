extends Node3D
## Camera-local sky and spatial city ambience, removed with the streamed shop.

const SKY_SHADER := preload("res://features/pawn_shop/storm_sky.gdshader")
const CLIPS: Array[AudioStreamWAV] = [
	preload("res://assets/pawn_shop/audio/road_ambience_0.wav"),
	preload("res://assets/pawn_shop/audio/road_ambience_1.wav"),
	preload("res://assets/pawn_shop/audio/road_ambience_2.wav"),
	preload("res://assets/pawn_shop/audio/road_ambience_3.wav"),
	preload("res://assets/pawn_shop/audio/road_ambience_4.wav"),
]
const BOUNDS := AABB(Vector3(-60, -3, 18), Vector3(110, 35, 60))

var traffic: AudioStreamPlayer3D
var _camera: Camera3D
var _previous: Environment
var _sky_environment: Environment
var _rng := RandomNumberGenerator.new()
var _clip_index := -1
var _rain: CPUParticles3D
var _lightning: OmniLight3D
var _sky_material: ShaderMaterial
var _flash_delay := 7.0
var _flash_remaining := 0.0


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER:
		set_process(false)
		return
	_rng.randomize()
	traffic = _voice("Traffic", -13.0)
	traffic.position = Vector3(-9, 2, 39)
	traffic.finished.connect(_play_next)
	_build_weather()


func _build_weather() -> void:
	_rain = CPUParticles3D.new()
	_rain.name = "StreetRain"
	_rain.position = Vector3(-9, 12, 40)
	_rain.amount = 650
	_rain.lifetime = 0.8
	_rain.preprocess = 0.8
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(28, 0.1, 8.5)
	_rain.direction = Vector3(0.08, -1, 0)
	_rain.spread = 2.0
	_rain.initial_velocity_min = 17.0
	_rain.initial_velocity_max = 21.0
	_rain.gravity = Vector3(0, -9.8, 0)
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.65)
	var rain_material := StandardMaterial3D.new()
	rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_material.albedo_color = Color(0.64, 0.77, 0.9, 0.5)
	rain_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = rain_material
	_rain.mesh = streak
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visibility_aabb = AABB(Vector3(-30, -17, -10), Vector3(60, 19, 20))
	_rain.emitting = false
	add_child(_rain)
	_lightning = OmniLight3D.new()
	_lightning.name = "Lightning"
	_lightning.position = Vector3(-9, 10, 40)
	_lightning.light_color = Color(0.7, 0.82, 1.0)
	_lightning.omni_range = 55.0
	_lightning.light_energy = 0.0
	add_child(_lightning)


func _voice(voice_name: String, volume: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = voice_name
	voice.bus = GameAudio.BUS
	voice.volume_db = volume
	voice.unit_size = 14.0
	voice.max_distance = 75.0
	add_child(voice)
	return voice


func _process(delta: float) -> void:
	update_camera(get_viewport().get_camera_3d())
	if _camera == null:
		return
	_flash_delay -= delta
	if _flash_delay <= 0.0:
		_flash_remaining = 0.25
		_flash_delay = _rng.randf_range(9.0, 19.0)
	_flash_remaining = maxf(0.0, _flash_remaining - delta)
	var intensity := _flash_remaining / 0.25
	_lightning.light_energy = intensity * 7.0
	_sky_material.set_shader_parameter("lightning", intensity * 0.7)
	var skyline := get_node("Cityscape") as MeshInstance3D
	var painted := skyline.mesh.surface_get_material(0) as StandardMaterial3D
	painted.albedo_color = Color.WHITE * (1.0 + intensity * 0.7)


func _play_next() -> void:
	if _camera == null:
		return
	_clip_index = (_clip_index + _rng.randi_range(1, CLIPS.size() - 1)) % CLIPS.size()
	traffic.stream = CLIPS[_clip_index]
	traffic.play()


func update_camera(camera: Camera3D) -> void:
	var inside := is_instance_valid(camera) and BOUNDS.has_point(to_local(camera.global_position))
	if camera != _camera or not inside:
		_restore()
	if not inside or _camera != null or traffic == null:
		return
	_camera = camera
	_previous = camera.environment
	var source := _previous if _previous != null else camera.get_world_3d().environment
	_sky_environment = source.duplicate() as Environment if source != null else Environment.new()
	_sky_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	_sky_material = material
	sky.sky_material = material
	_sky_environment.sky = sky
	camera.environment = _sky_environment
	_rain.emitting = true
	_rain.visible = true
	_play_next()


func _restore() -> void:
	if is_instance_valid(_camera) and _camera.environment == _sky_environment:
		_camera.environment = _previous
	_camera = null
	_previous = null
	_sky_environment = null
	if is_instance_valid(_rain):
		_rain.emitting = false
		_rain.visible = false
	if is_instance_valid(_lightning):
		_lightning.light_energy = 0.0
	_flash_remaining = 0.0
	if is_instance_valid(traffic):
		traffic.stop()


func _exit_tree() -> void:
	_restore()
