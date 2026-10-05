extends Node3D
## Local outdoor storm, released with the streamed garage interior.

const CLIPS: Array[AudioStreamWAV] = [
	preload("res://assets/pawn_shop/audio/road_ambience_0.wav"),
	preload("res://assets/pawn_shop/audio/road_ambience_1.wav"),
	preload("res://assets/pawn_shop/audio/road_ambience_2.wav"),
	preload("res://assets/pawn_shop/audio/road_ambience_3.wav"),
	preload("res://assets/pawn_shop/audio/road_ambience_4.wav"),
]
const BOUNDS := AABB(Vector3(-13.2, -1, -14.2), Vector3(21.4, 9, 25.4))
var _road_rain: CPUParticles3D
var _rain: CPUParticles3D
var _lightning: OmniLight3D
var _ambience: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _delay := 7.0
var _flash := 0.0
var _active := false
var _clip := -1


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER:
		set_process(false)
		return
	_rng.randomize()
	_rain = CPUParticles3D.new()
	_rain.name = "AlleyRain"
	_rain.position = Vector3(-10.6, 6.8, 3.5)
	_rain.amount = 220
	_rain.lifetime = 0.4
	_rain.preprocess = 0.4
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(1.7, 0.05, 7.0)
	_rain.direction = Vector3(0, -1, 0)
	_rain.spread = 0.0
	_rain.initial_velocity_min = 17.0
	_rain.initial_velocity_max = 18.0
	_rain.gravity = Vector3(0, -9.8, 0)
	var streak := QuadMesh.new()
	streak.size = Vector2(0.018, 0.45)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.64, 0.77, 0.9, 0.5)
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	streak.material = material
	_rain.mesh = streak
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visibility_aabb = AABB(Vector3(-2, -7, -8), Vector3(4, 8, 16))
	_rain.emitting = false
	add_child(_rain)
	_road_rain = _rain.duplicate() as CPUParticles3D
	_road_rain.name = "RoadRain"
	_road_rain.position = Vector3(3, 6.8, -17.5)
	_road_rain.amount = 250
	_road_rain.emission_box_extents = Vector3(17, .05, 6)
	add_child(_road_rain)
	_lightning = OmniLight3D.new()
	_lightning.name = "AlleyLightning"
	_lightning.position = Vector3(-10.5, 5.8, 3.5)
	_lightning.light_color = Color(0.7, 0.82, 1)
	_lightning.omni_range = 11.0
	_lightning.light_energy = 0.0
	add_child(_lightning)
	_ambience = AudioStreamPlayer3D.new()
	_ambience.name = "AlleyStormAmbience"
	_ambience.position = Vector3(-10.5, 2, 3.5)
	_ambience.bus = GameAudio.BUS
	_ambience.volume_db = -16.0
	_ambience.unit_size = 5.0
	_ambience.max_distance = 24.0
	_ambience.finished.connect(_play_next)
	add_child(_ambience)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var inside := is_instance_valid(camera) and BOUNDS.has_point(to_local(camera.global_position))
	if inside != _active:
		_active = inside
		_rain.emitting = inside
		_rain.visible = inside
		_road_rain.visible = inside
		_road_rain.emitting = inside
		if inside:
			_play_next()
		else:
			_ambience.stop()
			_flash = 0.0
			_lightning.light_energy = 0.0
	if not _active:
		return
	_delay -= delta
	if _delay <= 0.0:
		_flash = 0.25
		_delay = _rng.randf_range(9.0, 19.0)
	_flash = maxf(0.0, _flash - delta)
	_lightning.light_energy = _flash / 0.25 * 7.0


func _play_next() -> void:
	if not _active:
		return
	_clip = (_clip + _rng.randi_range(1, CLIPS.size() - 1)) % CLIPS.size()
	_ambience.stream = CLIPS[_clip]
	_ambience.play()
