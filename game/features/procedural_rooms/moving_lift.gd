class_name ProceduralMovingLift
extends Node3D
## One physical cab travels in a continuous shaft. CharacterBody platform motion carries riders.

enum Phase { DOCKED, CLOSING, MOVING, OPENING }

const SPEED := 2.0
const SLIDE_SECONDS := .65
const Kit := preload("res://features/procedural_rooms/example_kit.gd")
const Shell := preload("res://features/procedural_rooms/shell_mesh.gd")
const DOOR := preload("res://features/procedural_rooms/sliding_door.tscn")
const CAB_MODEL := preload("res://features/procedural_rooms/elevator_cab_model.tscn")
const BUTTON := preload("res://features/procedural_rooms/lift_stop.tscn")
const Showcase := preload("res://features/procedural_rooms/showcase.gd")
const AUDIO := preload("res://features/procedural_rooms/lift_audio.gd")
const PANEL := preload("res://features/procedural_rooms/elevator_panel.tscn")

@export var net_height := 16.0
@export var net_floor := 4
@export var net_target := 4
@export var net_phase: Phase = Phase.DOCKED
@export var net_aperture := 1.0
@export var casino_connection := false
## Optional stop schedule; empty arrays preserve the original garage layout.
@export var stop_heights := PackedFloat32Array()
@export var stop_labels: Array[String] = []
@export var initial_floor := -1
@export var control_panel: PackedScene
var cab: AnimatableBody3D
var indicator: Label3D
var cab_door: ProceduralSlidingDoor
var gates: Array[ProceduralSlidingDoor] = []
var audio: ProceduralLiftAudio
var _received_snapshot := false
@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	process_physics_priority = -100
	if casino_connection:
		net_floor = 5
		net_target = 5
		net_height = floor_height(5)
	if initial_floor >= 0:
		net_floor = initial_floor
		net_target = initial_floor
		net_height = stop_height(initial_floor)
	_build_cab()
	audio = AUDIO.new()
	audio.position.y = 2
	cab.add_child(audio)
	audio.initialize(net_phase)
	entity.session_reset.connect(_reset)
	entity._sync.synchronized.connect(_snapshot)


func _build_cab() -> void:
	cab = AnimatableBody3D.new()
	cab.name = "Cab"
	cab.sync_to_physics = false
	add_child(cab)
	cab.position = Vector3(0, net_height, -9.5)
	var shell := Node3D.new()
	shell.name = "Interior"
	shell.position.z = -1.5
	cab.add_child(shell)
	Kit._plane(shell, 3, 2.78, 0, "floor", Vector3.UP)
	Kit._plane(shell, 3, 2.78, 3, "roof", Vector3.DOWN)
	Kit._side(shell, -1.5, Vector2.ZERO, Vector2(2.78, 0), 3, "grey")
	Kit._side(shell, 1.5, Vector2.ZERO, Vector2(2.78, 0), 3, "grey")
	Kit._end_wall(shell, Vector3.ZERO, PI, -1.5, 1.5, 0, 3)
	Shell.rebuild(cab)
	shell.remove_meta("shell_faces")  # Never bake the moving cab into the static world shell.
	var body := cab.get_node("Structure/ShellCollision") as StaticBody3D
	body.get_child(0).reparent(cab)
	body.free()
	(cab.get_node("Structure") as Node3D).visible = false
	var model := CAB_MODEL.instantiate() as Node3D
	cab.add_child(model)
	cab_door = DOOR.instantiate() as ProceduralSlidingDoor
	cab_door.name = "CabDoor"
	cab_door.managed_by_lift = true
	cab_door.position = model.get_node("DoorSocket").position
	cab.add_child(cab_door)
	var panel := (control_panel if control_panel != null else PANEL).instantiate() as Node3D
	panel.position = Vector3(1.45, 1.62, -.65)
	cab.add_child(panel)
	for floor_index: int in stop_heights.size() if not stop_heights.is_empty() else 6:
		var button := BUTTON.instantiate() as Node3D
		button.name = "Floor%d" % floor_index
		button.set("floor_index", floor_index)
		button.set("ride_button", true)
		button.set("lift_path", NodePath("../.."))
		button.position = control_position(floor_index)
		if not stop_heights.is_empty():
			button.set("aim_half_width", .09)
		cab.add_child(button)
		if not stop_heights.is_empty():
			var label := Label3D.new()
			label.text = stop_label(floor_index)
			label.position = Vector3(-.005, 0, -.06)
			label.rotation.y = -PI / 2
			label.font_size = 24
			label.pixel_size = .002
			button.add_child(label)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.7, 0)
	lamp.omni_range = 5
	lamp.light_color = Color(1, .82, .58)
	cab.add_child(lamp)
	var instruction := Showcase.placard(cab, "SELECT FLOOR ON RIGHT", Vector3(0, 2.3, -1.38))
	instruction.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	instruction.font_size = 20
	indicator = Showcase.placard(cab, "B1", model.get_node("DisplaySocket").position)
	indicator.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	indicator.font_size = 40


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_advance(delta)
		cab.position.y = net_height
	elif _received_snapshot:
		cab.position.y = move_toward(cab.position.y, net_height, (SPEED + 1.0) * delta)
	_update_doors()
	audio.update(net_phase, delta)
	indicator.text = (
		("%s → %s" % [stop_label(net_floor), stop_label(net_target)])
		if net_phase == Phase.MOVING
		else stop_label(net_floor)
	)


func _snapshot() -> void:
	if not _received_snapshot:
		cab.position.y = net_height
		_received_snapshot = true
		audio.initialize(net_phase)
	_update_doors()


func request_floor(index: int) -> bool:
	if not multiplayer.is_server() or net_phase != Phase.DOCKED or index not in range(gates.size()):
		return false
	if index == net_floor or doorway_occupied():
		return false
	net_target = index
	net_phase = Phase.CLOSING
	return true


func _advance(delta: float) -> void:
	match net_phase:
		Phase.CLOSING:
			if doorway_occupied():
				net_target = net_floor
				net_phase = Phase.OPENING
			else:
				net_aperture = move_toward(net_aperture, 0, delta / SLIDE_SECONDS)
				if net_aperture == 0:
					net_phase = Phase.MOVING
		Phase.MOVING:
			net_height = move_toward(net_height, stop_height(net_target), SPEED * delta)
			if net_height == stop_height(net_target):
				net_floor = net_target
				net_phase = Phase.OPENING
		Phase.OPENING:
			net_aperture = move_toward(net_aperture, 1, delta / SLIDE_SECONDS)
			if net_aperture == 1:
				net_phase = Phase.DOCKED


func contains(player: Player) -> bool:
	var point := cab.to_local(player.net_position)
	return absf(point.x) < 1.4 and absf(point.z) < 1.3 and point.y > 0 and point.y < 2.8


func doorway_occupied() -> bool:
	return cab_door.occupied() or (gates.size() > net_floor and gates[net_floor].occupied())


func _update_doors() -> void:
	var aligned := (
		absf(cab.position.y - stop_height(net_floor)) < .025 and net_phase != Phase.MOVING
	)
	var aperture := net_aperture if aligned else 0.0
	cab_door.drive(aperture)
	for index: int in gates.size():
		gates[index].drive(aperture if index == net_floor else 0)


func _reset(_mode: Network.Mode) -> void:
	net_floor = 5 if casino_connection else 4
	if initial_floor >= 0:
		net_floor = initial_floor
	net_height = stop_height(net_floor)
	net_target = net_floor
	net_phase = Phase.DOCKED
	net_aperture = 1
	cab.position.y = net_height
	_update_doors()
	audio.initialize(net_phase)


func stop_height(index: int) -> float:
	return float(stop_heights[index]) if not stop_heights.is_empty() else floor_height(index)


func stop_label(index: int) -> String:
	return stop_labels[index] if index < stop_labels.size() else floor_label(index)


func control_position(index: int) -> Vector3:
	if stop_heights.is_empty():
		return Vector3(1.412, button_height(index), -.65)
	return Vector3(1.412, 1.94 - (index % 5) * .16, -.77 + (index / 5) * .25)


static func floor_height(index: int) -> float:
	return 22.0 if index == 5 else index * 4.0


static func floor_label(index: int) -> String:
	return "C / CASINO" if index == 5 else "B%d" % (5 - index)


static func button_height(index: int) -> float:
	return 2.12 - (34 + (5 - index) * 15) / 128.0
