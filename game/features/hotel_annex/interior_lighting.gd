extends Node3D
## Local presentation only: never mutate the shared outdoor environment.

const AMBIENT_ENERGY := 0.8
const AMBIENT_COLOR := Color(1.0, 0.94, 0.84)

var _camera: Camera3D
var _previous: Environment
var _source: Environment
var _indoor: Environment

@onready var _hotel: StreamedRoom = $Hotel
@onready var _atrium: StreamedRoom = $Atrium


func _process(_delta: float) -> void:
	update_camera(get_viewport().get_camera_3d())


func update_camera(camera: Camera3D) -> void:
	var inside := false
	if is_instance_valid(camera):
		var position := camera.global_position
		inside = _hotel.contains(position) or _atrium.contains(position)
	if camera != _camera or not inside:
		_restore()
	if not inside:
		return
	if _camera == null:
		_camera = camera
		_previous = camera.environment
		_source = _previous if _previous != null else camera.get_world_3d().environment
		_indoor = _source.duplicate() as Environment if _source != null else Environment.new()
		_indoor.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_indoor.ambient_light_color = AMBIENT_COLOR
		_indoor.ambient_light_energy = AMBIENT_ENERGY
		_indoor.ambient_light_sky_contribution = 0.0
		camera.environment = _indoor
	# DayNight retains ownership of the sky and its brightness; only ambient is fixed.
	if _source != null:
		_indoor.sky = _source.sky
		_indoor.background_energy_multiplier = _source.background_energy_multiplier


func _restore() -> void:
	if is_instance_valid(_camera) and _camera.environment == _indoor:
		_camera.environment = _previous
	_camera = null
	_previous = null
	_source = null
	_indoor = null


func _exit_tree() -> void:
	_restore()
