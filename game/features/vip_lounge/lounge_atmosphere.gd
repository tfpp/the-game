extends Node3D
## Local fog-free view; preserve shared lighting and restore other rooms' atmosphere.

var _camera: Camera3D
var _previous: Environment
var _clear: Environment


func _process(_delta: float) -> void:
	update_camera(get_viewport().get_camera_3d())


func update_camera(camera: Camera3D) -> void:
	var inside := is_instance_valid(camera) and VipLounge.BOUNDS.has_point(camera.global_position)
	if camera != _camera or not inside:
		_restore()
	if not inside or _camera != null:
		return
	_camera = camera
	_previous = camera.environment
	var source := _previous if _previous != null else camera.get_world_3d().environment
	_clear = source.duplicate() as Environment if source != null else Environment.new()
	_clear.fog_enabled = false
	_clear.volumetric_fog_enabled = false
	camera.environment = _clear


func _restore() -> void:
	if is_instance_valid(_camera) and _camera.environment == _clear:
		_camera.environment = _previous
	_camera = null
	_previous = null
	_clear = null


func _exit_tree() -> void:
	_restore()
