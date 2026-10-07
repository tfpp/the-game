class_name MetroZone
extends StreamedRoom
## Persistent anchor; presentation belongs to streamed Content, not the network tree.

## Scenery lights further than this from a ride's train centre are switched off,
## after fading over the last LIGHT_FADE metres so none pops on beside the cars.
const LIGHT_REACH := 72.0
const LIGHT_FADE := 12.0
const PASSING := preload("res://features/metro/passing_surface.gdshader")
@export var station_index := -1
@export var ride_index := -1
var seating: MetroSeating
var reverse_seating: MetroSeating
var reverse_train: Node3D
var train: Node3D
## Ride compartments: the platforms and tunnel passing outside the windows.
var scenery: Node3D
var _reverse_doors: AnimationPlayer
var _reverse_collision: Node3D
var _reverse_collision_doors: AnimationPlayer
var _reverse_boards: Array[Label3D] = []
var _door_batches: Array[MultiMeshInstance3D] = []
var _style_cycle := -1
var _doors: AnimationPlayer
var _caption: Label3D
var _boards: Array[Label3D] = []
var _hum: AudioStreamPlayer3D
var _scenery_lights: Array[Light3D] = []
var _light_energy: Array[float] = []
var _signals: Array[Node3D] = []
var _departure_boards: Array[Label3D] = []
var _arrival_boards: Array[Label3D] = []
var _scrolling: Array[ShaderMaterial] = []
var _last_warning := -1
var _last_phase := -1
var _collision: Node3D
var _collision_doors: AnimationPlayer
var _aperture := -1.0
var _shake_camera: Camera3D
var _shake_offset := Vector2.ZERO


func _ready() -> void:
	content_changed.connect(_content_changed)
	var seats := load("res://features/metro/metro_seating.tscn") as PackedScene
	seating = seats.instantiate() as MetroSeating
	add_child(seating)
	if station_index >= 0:
		reverse_seating = seats.instantiate() as MetroSeating
		reverse_seating.name = "ReverseSeating"
		reverse_seating.position = MetroRules.track_offset(1)
		add_child(reverse_seating)
	set_process(false)


func service() -> MetroService:
	return get_parent() as MetroService


func _content_changed(loaded: bool) -> void:
	_clear_shake()
	set_process(loaded)
	_style_cycle = -1
	_last_phase = -1
	_last_warning = -1
	train = null
	reverse_train = null
	_reverse_doors = null
	_reverse_collision = null
	_reverse_collision_doors = null
	_reverse_boards.clear()
	_door_batches.clear()
	_doors = null
	_caption = null
	_boards.clear()
	_hum = null
	scenery = null
	_scenery_lights.clear()
	_light_energy.clear()
	_signals.clear()
	_departure_boards.clear()
	_arrival_boards.clear()
	_scrolling.clear()
	_collision = null
	_collision_doors = null
	_aperture = -1
	if not loaded:
		return
	train = _content.get_node("Train") as Node3D
	reverse_train = _content.get_node_or_null("ReverseTrain") as Node3D
	for assembly: Node3D in [train, reverse_train]:
		if assembly != null:
			for batch: Node in assembly.find_children(
				"DoorBatch*", "MultiMeshInstance3D", true, false
			):
				_door_batches.append(batch as MultiMeshInstance3D)
	if reverse_train != null:
		_reverse_doors = reverse_train.get_node("Doors") as AnimationPlayer
		var reverse_residents := MetroResidents.new()
		reverse_residents.name = "ReverseResidents"
		reverse_residents.zone = self
		reverse_residents.track_index = 1
		_content.add_child(reverse_residents)
	scenery = _content.get_node_or_null("Scenery") as Node3D
	if scenery != null:
		_collect_scenery()
	var residents := MetroResidents.new()
	residents.name = "ShelteringResidents"
	residents.zone = self
	_content.add_child(residents)
	_doors = train.get_node("Doors") as AnimationPlayer
	_caption = _content.get_node_or_null("Board") as Label3D
	for node: Node in _content.find_children("Board*", "Label3D", false, false):
		if node.name.begins_with("BoardReverse"):
			_reverse_boards.append(node as Label3D)
		else:
			_boards.append(node as Label3D)
	_hum = _content.get_node_or_null("RailSound") as AudioStreamPlayer3D
	_collision = _content.get_node("TrainCollision") as Node3D
	_reverse_collision = _content.get_node_or_null("ReverseTrainCollision") as Node3D
	if multiplayer.is_server():
		if _reverse_collision != null:
			_reverse_collision.queue_free()
			_reverse_collision = null
		# Dedicated authority already owns these same structural colliders.
		for grid: Node in _content.find_children("*", "GridMap", true, false):
			(grid as GridMap).collision_layer = 0
		for body: Node in _content.find_children("*", "CollisionObject3D", true, false):
			(body as CollisionObject3D).collision_layer = 0
		_collision.queue_free()
		_collision = null
	else:
		_collision_doors = _collision.get_node("Doors") as AnimationPlayer
		if _reverse_collision != null:
			_reverse_collision_doors = _reverse_collision.get_node("Doors") as AnimationPlayer
	if _hum != null:
		_hum.stream = ProceduralAudio.hum_loop(65, 4401)
		_hum.bus = GameAudio.BUS
		_hum.volume_db = -21
	update_view()


func _collect_scenery() -> void:
	for node: Node in scenery.find_children("*", "Light3D", true, false):
		_scenery_lights.append(node as Light3D)
		_light_energy.append((node as Light3D).light_energy)
	for node: Node in scenery.find_children("Signal*", "Node3D", true, false):
		_signals.append(node as Node3D)
	for node: Node in scenery.get_node("Departure").find_children("Board*", "Label3D", false):
		_departure_boards.append(node as Label3D)
	for node: Node in scenery.get_node("Arrival").find_children("Board*", "Label3D", false):
		_arrival_boards.append(node as Label3D)
	for node: Node in scenery.find_children("*", "GridMap", true, false):
		var library := (node as GridMap).mesh_library
		for item: int in library.get_item_list():
			var mesh := library.get_item_mesh(item)
			var material := mesh.surface_get_material(0) as ShaderMaterial if mesh != null else null
			if material != null and material.shader == PASSING and not material in _scrolling:
				_scrolling.append(material)


## The ride compartment never moves: its scenery travels the trip in reverse.
func _pass_scenery(metro: MetroService, t: float) -> void:
	# Riders still aboard after arriving face that platform until the next boarding.
	var boarding := t >= MetroRules.OPEN + MetroRules.DWELL
	var covered := 0.0 if boarding else MetroRules.SPACING
	if t >= MetroRules.DEPART:
		covered = MetroRules.distance(t - MetroRules.DEPART)
	scenery.position.z = covered * MetroRules.direction(ride_index)
	for material: ShaderMaterial in _scrolling:
		material.set_shader_parameter(&"scroll", scenery.position.z)
	for index: int in _scenery_lights.size():
		var light := _scenery_lights[index]
		var reach := absf(light.global_position.z - global_position.z)
		var fade := clampf((LIGHT_REACH - reach) / LIGHT_FADE, 0.0, 1.0)
		light.visible = fade > 0.0
		light.light_energy = _light_energy[index] * fade
	for head: Node3D in _signals:
		# A block signal drops to danger once the leading cab has passed it.
		var clear := (
			(head.global_position.z - global_position.z) * MetroRules.direction(ride_index)
			< -MetroRules.TRAIN_HALF_LENGTH
		)
		(head.get_node("Clear") as Node3D).visible = clear
		(head.get_node("Stop") as Node3D).visible = not clear
	var from := MetroRules.station(ride_index, metro.net_cycle)
	var to := MetroRules.station(ride_index, metro.net_cycle + (1 if boarding else 0))
	_platform_labels(_departure_boards, from, t)
	_platform_labels(_arrival_boards, to, t)
	var style_cycle := metro.net_cycle * 2 + int(boarding)
	if _style_cycle != style_cycle:
		_style_cycle = style_cycle
		station_style(scenery.get_node("Departure"), from)
		station_style(scenery.get_node("Arrival"), to)


static func _label(boards: Array[Label3D], text: String) -> void:
	for board: Label3D in boards:
		if board.text != text:
			board.text = text


static func _platform_labels(boards: Array[Label3D], index: int, time: float) -> void:
	var forward := MetroRules.station_board(index, time)
	var reverse := MetroRules.station_board(index, time, 1)
	for board: Label3D in boards:
		var text := reverse if board.name.begins_with("BoardReverse") else forward
		if board.text != text:
			board.text = text


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
		if scenery != null:
			_pass_scenery(metro, t)
	else:
		train.position.z = MetroRules.train_z(t)
		train.visible = not MetroRules.train_hidden(train.position.z)
		if reverse_train != null:
			reverse_train.position.z = -train.position.z
			reverse_train.visible = train.visible
		if _style_cycle != station_index:
			_style_cycle = station_index
			station_style(_content, station_index)
		_label(_reverse_boards, MetroRules.station_board(station_index, t, 1))
	if _collision != null:
		var height := metro.collision_height(station_index)
		if _collision.position.y != height:
			_collision.position.y = height
	if _reverse_collision != null:
		var height := metro.collision_height(station_index, 1)
		if _reverse_collision.position.y != height:
			_reverse_collision.position.y = height
	if opening != _aperture:
		for animation: AnimationPlayer in [_doors, _collision_doors]:
			if animation != null:
				animation.play("open_right")
				animation.seek(opening * 1.2, true)
				animation.pause()
		for animation: AnimationPlayer in [_reverse_doors, _reverse_collision_doors]:
			if animation != null:
				animation.play("open_left")
				animation.seek(opening * 1.2, true)
				animation.pause()
		for batch: MultiMeshInstance3D in _door_batches:
			batch.call("sync_doors")
		_aperture = opening
	if _caption != null:
		if station_index >= 0:
			_label(_boards, MetroRules.station_board(station_index, t))
		else:
			var next := MetroRules.station(ride_index, metro.net_cycle + (1 if traveling else 0))
			var caption := (
				"%s · %s\nSTAND CLEAR OF THE DOORS"
				% ["NEXT STOP" if traveling else "ARRIVING", MetroRules.NAMES[next]]
			)
			if _caption.text != caption:
				_caption.text = caption
		for board: Label3D in _boards:
			if board != _caption and board.text != _caption.text:
				board.text = _caption.text
	if _hum != null:
		if traveling and not _hum.playing:
			_hum.play()
		elif not traveling and _hum.playing:
			_hum.stop()
		# The motors spin up and down with the train instead of starting at full hum.
		var pace := MetroRules.speed(t - MetroRules.DEPART) / MetroRules.TOP_SPEED
		_hum.pitch_scale = lerpf(0.6, 1.25, pace)
		_hum.volume_db = lerpf(-30.0, -19.0, sqrt(pace))
		if station_index >= 0:
			_hum.position.z = train.position.z
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
	# Rattle grows with speed, so a standing train is still and stops are gentle.
	var pace := MetroRules.speed(t - MetroRules.DEPART) / MetroRules.TOP_SPEED
	_shake_offset = Vector2(sin(t * 31) * 0.004, sin(t * 43) * 0.006) * pace
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


## All four identities share the same structural and collision kit.
static func station_style(content: Node, index: int) -> void:
	var identity := content.get_node_or_null("Identity")
	if identity == null:
		return
	for style: Node3D in identity.get_children():
		style.visible = style.name == "Station%d" % index
