class_name OperationsVanDoor
extends Node3D
## Always-present interaction; only the server changes the replicated leaf state.

const SWING_SECONDS := .45
@export var door_label := "Cab door"
@export var open_angle := PI / 2
@export var net_open := false
@export var handle_offset := Vector3.ZERO
@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var hinge: Node3D = $Hinge


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _toggle, SWING_SECONDS + .1)
	entity.session_reset.connect(_reset)
	entity.event_received.connect(_event)
	hinge.rotation.y = open_angle if net_open else 0.0
	_update_handle()


func _physics_process(delta: float) -> void:
	hinge.rotation.y = move_toward(
		hinge.rotation.y, open_angle if net_open else 0.0, absf(open_angle) * delta / SWING_SECONDS
	)

	_update_handle()


func _update_handle() -> void:
	entity.interaction_offset = to_local(hinge.to_global(handle_offset))


func interaction_text() -> String:
	return ("Close · " if net_open else "Open · ") + door_label


func can_use(player: Player) -> bool:
	return entity.in_range(player)


func use() -> void:
	entity.request_use()


func _toggle(_player: Player) -> bool:
	net_open = not net_open
	entity.send_event(&"sound", {"open": net_open})
	return true


func _event(event: StringName, payload: Dictionary) -> void:
	if event == &"sound":
		GameAudio.play_at(self, &"door_open" if payload["open"] else &"door_close", global_position)


func _reset(_mode: Network.Mode) -> void:
	net_open = false
