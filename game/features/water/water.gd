extends Node3D
## A decorative pond. Its water is a `MeshInstance3D` with no collision shape, so
## wading in is purely visual: players keep standing on the solid curb-height ground
## underneath and can never fall through or drown.

const WaterWave := preload("res://features/water/water_wave.gd")
const AMPLITUDE_M := 0.02
const PERIOD_S := 2.5

var _base_y := 0.0
var _elapsed := 0.0

@onready var _surface: MeshInstance3D = $Surface


func _ready() -> void:
	_base_y = _surface.position.y


func _process(delta: float) -> void:
	_elapsed += delta
	var pos := _surface.position
	pos.y = WaterWave.surface_y(_base_y, _elapsed, AMPLITUDE_M, PERIOD_S)
	_surface.position = pos
