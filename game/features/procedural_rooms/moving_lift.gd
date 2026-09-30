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
var cab: AnimatableBody3D
var indicator: Label3D
var cab_door: ProceduralSlidingDoor
var gates: Array[ProceduralSlidingDoor] = []
var audio: ProceduralLiftAudio
var _received_snapshot := false
@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	process_physics_priority = -100
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
	var panel := PANEL.instantiate() as Node3D
	panel.position = Vector3(1.45, 1.62, -.65)
	cab.add_child(panel)
	for floor_index: int in 5:
		var button := BUTTON.instantiate() as Node3D
		button.name = "Floor%d" % floor_index
		button.set("floor_index", floor_index)
		button.set("ride_button", true)
		button.set("lift_path", NodePath("../.."))
		button.position = Vector3(1.412, 2.12 - (39 + (4 - floor_index) * 17) / 128.0, -.65)
		cab.add_child(button)
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
		("B%d → B%d" % [5 - roundi(cab.position.y / 4.0), 5 - net_target])
		if net_phase == Phase.MOVING
		else "B%d" % (5 - net_floor)
	)


func _snapshot() -> void:
	if not _received_snapshot:
		cab.position.y = net_height
		_received_snapshot = true
		audio.initialize(net_phase)
	_update_doors()


func request_floor(index: int) -> bool:
	if not multiplayer.is_server() or net_phase != Phase.DOCKED or index not in range(5):
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
			net_height = move_toward(net_height, net_target * 4.0, SPEED * delta)
			if net_height == net_target * 4.0:
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
	var aligned := absf(cab.position.y - net_floor * 4.0) < .025 and net_phase != Phase.MOVING
	var aperture := net_aperture if aligned else 0.0
	cab_door.drive(aperture)
	for index: int in gates.size():
		gates[index].drive(aperture if index == net_floor else 0)


func _reset(_mode: Network.Mode) -> void:
	net_height = 16
	net_floor = 4
	net_target = 4
	net_phase = Phase.DOCKED
	net_aperture = 1
	cab.position.y = net_height
	_update_doors()
	audio.initialize(net_phase)
