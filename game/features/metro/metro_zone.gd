class_name MetroZone
extends StreamedRoom
## Persistent anchor; presentation belongs to streamed Content, not the network tree.

@export var station_index := -1
@export var ride_index := -1
var train: Node3D
var _doors: AnimationPlayer
var _caption: Label3D
var _boards: Array[Label3D] = []
var _hum: AudioStreamPlayer3D
var _light_bars: Node3D
var _last_warning := -1
var _last_phase := -1
var _collision: Node3D
var _collision_doors: AnimationPlayer
var _aperture := -1.0
var _shake_camera: Camera3D
var _shake_offset := Vector2.ZERO


func _ready() -> void:
	content_changed.connect(_content_changed)


func service() -> MetroService:
	return get_parent() as MetroService


func _content_changed(loaded: bool) -> void:
	_clear_shake()
	_last_phase = -1
	_last_warning = -1
	train = null
	_doors = null
	_caption = null
	_boards.clear()
	_hum = null
	_light_bars = null
	_collision = null
	_collision_doors = null
	_aperture = -1
	if not loaded:
		return
	train = _content.get_node("Train") as Node3D
	_doors = train.get_node("Doors") as AnimationPlayer
	_caption = _content.get_node_or_null("Board") as Label3D
	for node: Node in _content.find_children("Board*", "Label3D", false, false):
		_boards.append(node as Label3D)
	_hum = _content.get_node_or_null("RailSound") as AudioStreamPlayer3D
	_light_bars = _content.get_node_or_null("TunnelBars") as Node3D
	_collision = _content.get_node("TrainCollision") as Node3D
	if multiplayer.is_server():
		_collision.queue_free()
		_collision = null
	else:
		_collision_doors = _collision.get_node("Doors") as AnimationPlayer
	if _hum != null:
		_hum.stream = ProceduralAudio.hum_loop(65, 4401)
		_hum.bus = GameAudio.BUS
		_hum.volume_db = -21
	update_view()


func _process(_delta: float) -> void:
	_clear_shake()
	if is_loaded():
		update_view()
		if ride_index >= 0:
			_shake()


func update_view() -> void:
	if not is_instance_valid(train) or service() == null:
		return
	var metro := service()
	var t := metro.display_time()
	var traveling := t >= MetroRules.DEPART
	var opening := MetroRules.aperture(t)
	if ride_index >= 0:
		opening = 0
		train.position.z = 0
		if _light_bars != null:
			_light_bars.position.z = fposmod(t * 20, 8)
	else:
		train.position.z = MetroRules.train_z(t)
		train.visible = t < MetroRules.DEPART + 3 or t > MetroRules.DEPART + 7
	if _collision != null:
		var height := MetroRules.collision_y(t) if station_index >= 0 else 0.0
		if _collision.position.y != height:
			_collision.position.y = height
	if opening != _aperture:
		for animation: AnimationPlayer in [_doors, _collision_doors]:
			if animation != null:
				animation.play("open_right")
				animation.seek(opening * 1.2, true)
				animation.pause()
		_aperture = opening
	if _caption != null:
		if station_index >= 0:
			var remaining := maxi(0, ceili(MetroRules.OPEN + MetroRules.DWELL - t))
			_caption.text = (
				"%s\nLOOP → %s\n%s"
				% [
					MetroRules.NAMES[station_index],
					MetroRules.NAMES[(station_index + 1) % 4],
					(
						("DEPARTS IN %02d s" % remaining)
						if not traveling
						else ("NEXT TRAIN %02d s" % ceili(MetroRules.PERIOD - t))
					)
				]
			)
			if t >= MetroRules.OPEN + MetroRules.DWELL and not traveling:
				_caption.text = (
					"%s\nLOOP → %s\nDOORS CLOSING"
					% [MetroRules.NAMES[station_index], MetroRules.NAMES[(station_index + 1) % 4]]
				)
		else:
			var next := MetroRules.station(ride_index, metro.net_cycle + (1 if traveling else 0))
			_caption.text = (
				"%s · %s\nSTAND CLEAR OF THE DOORS"
				% ["NEXT STOP" if traveling else "ARRIVING", MetroRules.NAMES[next]]
			)
		for board: Label3D in _boards:
			if board != _caption and board.text != _caption.text:
				board.text = _caption.text
	if _hum != null:
		if traveling and not _hum.playing:
			_hum.play()
		elif not traveling and _hum.playing:
			_hum.stop()
	# Phase events do not replay when a room first loads halfway through a phase.
	var phase := 1 if t >= MetroRules.OPEN + MetroRules.DWELL - 2 else 0
	if phase == 1 and _last_phase == 0 and _last_warning != metro.net_cycle:
		GameAudio.play_ui(self, &"elevator_ding")
		_last_warning = metro.net_cycle
	_last_phase = phase


func _shake() -> void:
	var rider := service().player(multiplayer.get_unique_id())
	if rider == null or not contains(rider.global_position):
		return
	var camera := rider.get_node_or_null("Camera") as Camera3D
	if camera == null or not camera.current:
		return
	_shake_camera = camera
	var t := service().display_time()
	_shake_offset = Vector2(sin(t * 31) * 0.004, sin(t * 43) * 0.006)
	camera.h_offset += _shake_offset.x
	camera.v_offset += _shake_offset.y


func _clear_shake() -> void:
	if is_instance_valid(_shake_camera):
		_shake_camera.h_offset -= _shake_offset.x
		_shake_camera.v_offset -= _shake_offset.y
	_shake_camera = null
	_shake_offset = Vector2.ZERO


func _exit_tree() -> void:
	_clear_shake()
