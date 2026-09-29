extends Node3D
## The garage's weather bed (rain hiss under a slow wind swell) plus occasional
## distant structural groans. Runs on every peer except the dedicated server,
## the same guard `GameAudio` uses (features/game_audio/game_audio.gd), since a
## headless server has no audio device worth feeding.

const ProceduralAudio := preload("res://features/parking_garage/procedural_audio.gd")

@export var ambience_seed: int = 1
@export var audible_radius := 50.0

var _rng := RandomNumberGenerator.new()
var _next_creak := 0.0

@onready var _bed: AudioStreamPlayer = $Bed
@onready var _creaks: AudioStreamPlayer3D = $Creaks


func _ready() -> void:
	if Network.mode == Network.Mode.SERVER or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_rng.seed = ambience_seed
	_schedule_creak()


func _process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	var nearby := (
		player != null and player.global_position.distance_to(global_position) <= audible_radius
	)
	if not nearby:
		if _bed.playing:
			_bed.stop()
		if _creaks.playing:
			_creaks.stop()
		return
	if _bed.stream == null:
		_bed.stream = ProceduralAudio.rain_and_wind_loop(ambience_seed)
		_bed.volume_db = -16.0
	if not _bed.playing:
		_bed.play()
	_next_creak -= delta
	if _next_creak <= 0.0:
		_creaks.stream = ProceduralAudio.structural_creak(_rng.randi())
		_creaks.volume_db = -10.0
		_creaks.play()
		_schedule_creak()


func _schedule_creak() -> void:
	_next_creak = _rng.randf_range(25.0, 70.0)
