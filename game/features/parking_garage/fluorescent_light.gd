class_name FluorescentLight
extends Node3D
## One ceiling fixture in one of four states: a steady working tube, a fast
## flicker, a dim struggling tube, or a dead one. Purely cosmetic — every peer,
## including the server, resolves its own timing from `fixture_seed`, the same
## way the elevator's door animation runs locally on each peer (see
## `elevator_cab.gd`), so it never needs replicated state.

enum Mode { STEADY, FLICKER, STRUGGLE, DEAD }

const ProceduralAudio := preload("res://features/parking_garage/procedural_audio.gd")
const HUM_FREQUENCIES := [116.0, 120.0, 122.0]

@export var mode: Mode = Mode.STEADY
@export var base_energy: float = 2.4
@export var light_color: Color = Color(0.75, 0.85, 1.0)
@export var fixture_seed: int = 0

var _rng := RandomNumberGenerator.new()
var _next_event := 0.0
var _target_energy := 0.0

@onready var _light: OmniLight3D = $Light
@onready var _tube: MeshInstance3D = $Tube
@onready var _hum: AudioStreamPlayer3D = $Hum


func _ready() -> void:
	_rng.seed = fixture_seed
	_light.light_color = light_color
	var tube_material := (
		(_tube.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
	)
	_tube.material_override = tube_material
	if mode == Mode.DEAD:
		_light.visible = false
		_tube.visible = false
		set_process(false)
		return
	_light.light_energy = base_energy
	tube_material.emission_energy_multiplier = base_energy
	if mode == Mode.STEADY:
		set_process(false)
	elif mode == Mode.STRUGGLE:
		_target_energy = _rng.randf_range(0.1, 0.45) * base_energy
		_light.light_energy = _target_energy
		tube_material.emission_energy_multiplier = _target_energy
		_schedule_next()
	else:
		_target_energy = base_energy
		_schedule_next()
	if Network.mode != Network.Mode.SERVER:
		_hum.stream = ProceduralAudio.hum_loop(
			HUM_FREQUENCIES[fixture_seed % HUM_FREQUENCIES.size()], fixture_seed
		)
		_hum.volume_db = -22.0 if mode == Mode.STRUGGLE else -18.0
		_hum.play()


func _process(delta: float) -> void:
	_next_event -= delta
	var tube_material := _tube.material_override as StandardMaterial3D
	match mode:
		Mode.FLICKER:
			if _next_event <= 0.0:
				_target_energy = base_energy if _rng.randf() > 0.45 else 0.0
				_schedule_next()
			_light.light_energy = _target_energy
			tube_material.emission_energy_multiplier = _target_energy
		Mode.STRUGGLE:
			if _next_event <= 0.0:
				_target_energy = _rng.randf_range(0.1, 0.45) * base_energy
				_schedule_next()
			_light.light_energy = lerpf(_light.light_energy, _target_energy, delta * 3.0)
			tube_material.emission_energy_multiplier = _light.light_energy


func _schedule_next() -> void:
	match mode:
		Mode.FLICKER:
			_next_event = _rng.randf_range(0.04, 0.4)
		Mode.STRUGGLE:
			_next_event = _rng.randf_range(0.8, 2.6)
		_:
			_next_event = 999.0
