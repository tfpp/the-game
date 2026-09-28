extends Node3D
## The garage's weather bed (rain hiss under a slow wind swell) plus occasional
## distant structural groans. Runs on every peer except the dedicated server,
## the same guard `GameAudio` uses (features/game_audio/game_audio.gd), since a
## headless server has no audio device worth feeding.

const ProceduralAudio := preload("res://features/parking_garage/procedural_audio.gd")

@export var ambience_seed: int = 1

var _rng := RandomNumberGenerator.new()
var _next_creak := 0.0

@onready var _bed: AudioStreamPlayer = $Bed
@onready var _creaks: AudioStreamPlayer3D = $Creaks


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER:
		set_process(false)
		return
	_rng.seed = ambience_seed
	_bed.stream = ProceduralAudio.rain_and_wind_loop(ambience_seed)
	_bed.volume_db = -16.0
	_bed.play()
	_schedule_creak()


func _process(delta: float) -> void:
	_next_creak -= delta
	if _next_creak <= 0.0:
		_creaks.stream = ProceduralAudio.structural_creak(_rng.randi())
		_creaks.volume_db = -10.0
		_creaks.play()
		_schedule_creak()


func _schedule_creak() -> void:
	_next_creak = _rng.randf_range(25.0, 70.0)
