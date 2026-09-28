extends AudioStreamPlayer3D
## A leak or puddle that periodically plinks. Each instance gets its own seed
## from `drip_seed` so the garage's several drips don't all tick in unison.

const ProceduralAudio := preload("res://features/parking_garage/procedural_audio.gd")

@export var drip_seed: int = 0
@export var min_interval_s: float = 1.5
@export var max_interval_s: float = 5.0

var _rng := RandomNumberGenerator.new()
var _next_drip := 0.0


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER:
		set_process(false)
		return
	_rng.seed = drip_seed
	max_distance = 10.0
	unit_size = 2.0
	_schedule_next()


func _process(delta: float) -> void:
	_next_drip -= delta
	if _next_drip <= 0.0:
		stream = ProceduralAudio.drip_blip(_rng.randi())
		volume_db = -6.0
		pitch_scale = _rng.randf_range(0.85, 1.2)
		play()
		_schedule_next()


func _schedule_next() -> void:
	_next_drip = _rng.randf_range(min_interval_s, max_interval_s)
