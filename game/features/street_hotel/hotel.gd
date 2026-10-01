extends Node3D
## Permanent authenticated controls; shared door state survives per-floor streaming.

const SPEC := preload("res://features/street_hotel/spec.gd")
const ELEVATOR := preload("res://features/street_hotel/elevator.gd")
const SWING := preload("res://features/room_doors/swing_door.tscn")
const PORTAL := preload("res://features/hotel_props/hotel_portal.gd")
const INTERACTION := preload("res://core/net/networked_interaction.gd")
var floors: Array[StreamedRoom] = []
var lift: ProceduralMovingLift
var _ride_floors: Array[StreamedRoom] = []
var _camera: Camera3D
var _previous: Environment
var _indoor: Environment
var _far := 0.0
var _source: Environment


func _ready() -> void:
	process_priority = 20
	var anchors := Node3D.new()
	anchors.name = "Floors"
	anchors.position = SPEC.INTERIOR_ORIGIN
	add_child(anchors)
	for index: int in SPEC.FLOORS:
		var room := StreamedRoom.new()
		room.name = "Floor%02d" % (index + 1)
		room.position.y = index * SPEC.STOREY
		room.room_scene = "res://features/street_hotel/floor_content.tscn"
		room.bounds = AABB(Vector3(-9.8, -.2, -.2), Vector3(19.6, 4, 72.4))
		room.set_meta("floor_index", index)
		anchors.add_child(room)
		floors.append(room)
		var arrival := Marker3D.new()
		arrival.name = "Arrival"
		arrival.position = Vector3(0, 1, 6)
		arrival.rotation.y = PI
		room.add_child(arrival)
	lift = ELEVATOR.build(anchors, floors)
	# Every destination exists before any RoomDoor resolves its marker.
	for index: int in SPEC.FLOORS:
		_controls(index)
		_destination(
			"Floor%02d" % (index + 1),
			floors[index].to_global(Vector3(0, .1, 6)),
			"Crown Hotel · Floor %d" % (index + 1),
			SPEC.THEMES[index]
		)
	var street := get_parent().get_node_or_null("street_district/Room") as StreamedRoom
	if street != null:
		var arrival := Marker3D.new()
		arrival.name = "HotelArrival"
		arrival.position = Vector3(-33.3, 1, 14)
		arrival.rotation.y = -PI / 2
		street.add_child(arrival)
		_portal(
			self,
			"StreetEntrance",
			Vector3(-34.94, 1.1, -2186),
			PI / 2,
			NodePath("../Floors/Floor01/Arrival"),
			"Enter Crown Hotel",
			Vector3(1.4, 2.2, .12)
		)
		_portal(
			floors[0],
			"StreetReturn",
			Vector3(0, 1.1, .15),
			0,
			NodePath("../../../../street_district/Room/HotelArrival"),
			"Return to the street",
			Vector3(1.4, 2.2, .12)
		)
		_destination(
			"Entrance",
			street.to_global(Vector3(-33.3, .1, 14)),
			"Crown Hotel Entrance",
			"West side of the street district. Use the reception door."
		)


func _controls(index: int) -> void:
	var room := floors[index]
	var doors := Node3D.new()
	doors.name = "GuestDoors"
	doors.visible = false
	room.add_child(doors)
	for bay: int in range(10):
		for side: int in [-1, 1]:
			var number := SPEC.room_number(index, bay * 2 + (1 if side > 0 else 0))
			var door := SWING.instantiate() as SwingDoor
			door.name = "Room%d" % number
			door.width = 1.2
			door.height = 2.4
			door.position = Vector3(side * 1.5, 0, 15 + bay * 6)
			door.rotation.y = -side * PI / 2
			door.door_label = "Guest room %d" % number
			doors.add_child(door)
			var plate := Label3D.new()
			plate.name = "Number"
			plate.text = str(number)
			plate.position = Vector3(0, 2.6, .08)
			plate.font_size = 40
			plate.pixel_size = .003
			plate.visibility_range_end = 14
			door.add_child(plate)


func _portal(
	parent: Node3D,
	id: String,
	at: Vector3,
	yaw: float,
	destination: NodePath,
	label: String,
	size: Vector3,
	sign_text: String = ""
) -> RoomDoor:
	var door := CSGBox3D.new()
	door.name = id
	door.set_script(PORTAL)
	door.size = size
	door.position = at
	door.rotation.y = yaw
	door.use_collision = true
	door.set("destination", destination)
	door.set("door_label", label)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("725b32")
	paint.roughness = 1
	door.material = paint
	var entity := NetworkedInteraction.new()
	entity.name = "NetworkedEntity"
	entity.set_script(INTERACTION)
	entity.interaction_range = 2.5
	door.add_child(entity)
	parent.add_child(door)
	var sign := Label3D.new()
	sign.text = sign_text if not sign_text.is_empty() else label.to_upper() + "\nE / USE"
	sign.position = Vector3(0, 0, -.065) if not sign_text.is_empty() else Vector3(0, 1.4, 0)
	sign.rotation.y = PI if not sign_text.is_empty() else 0
	sign.font_size = 24
	sign.pixel_size = .0035
	door.add_child(sign)
	return door as RoomDoor


func _destination(id: String, at: Vector3, label: String, hint: String) -> void:
	var marker := GpsDestination.new()
	marker.name = id
	marker.position = at
	marker.label = label
	marker.hint = hint
	add_child(marker)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	var riding := player != null and lift.contains(player)
	_stream_landing(player, riding)
	var inside := riding
	var camera := get_viewport().get_camera_3d()
	for room: StreamedRoom in floors:
		var active := camera != null and room.contains(camera.global_position)
		(room.get_node("GuestDoors") as Node3D).visible = room.is_loaded() and active
		(room.get_node("LiftCall") as Node3D).visible = active
		(room.get_node("LiftGate") as Node3D).visible = (
			active or (riding and absf(room.position.y - lift.cab.position.y) < SPEC.STOREY)
		)
		var content := room.get_node_or_null("Content") as Node3D
		if content != null:
			content.visible = active
		inside = inside or active
	if camera != _camera or not inside:
		_restore_camera()
	if not inside:
		return
	if _camera == null:
		_camera = camera
		_previous = camera.environment
		_far = camera.far
		_source = _previous if _previous != null else camera.get_world_3d().environment
		_indoor = _source.duplicate() as Environment if _source != null else Environment.new()
		_indoor.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_indoor.ambient_light_color = Color("ffe6bd")
		_indoor.ambient_light_energy = .8
		_indoor.ambient_light_sky_contribution = 0
		camera.environment = _indoor
	# The cheap street proxy needs a longer far plane than the narrow streamed floor.
	camera.far = 180
	if _source != null:
		_indoor.sky = _source.sky
		_indoor.background_energy_multiplier = _source.background_energy_multiplier


func _stream_landing(player: Player, riding: bool) -> void:
	if Network.mode == Network.Mode.SERVER:
		return
	for room: StreamedRoom in floors:
		var near_cab := riding and absf(room.position.y - lift.cab.position.y) < 2.0
		if near_cab:
			room.load_room(500)
			if not _ride_floors.has(room):
				_ride_floors.append(room)
		elif _ride_floors.has(room):
			_ride_floors.erase(room)
			if player == null or not room.contains(player.net_position):
				room.unload_room()


func _restore_camera() -> void:
	if is_instance_valid(_camera):
		if _camera.environment == _indoor:
			_camera.environment = _previous
		_camera.far = _far
	_camera = null
	_indoor = null
	_source = null


func _exit_tree() -> void:
	_restore_camera()
