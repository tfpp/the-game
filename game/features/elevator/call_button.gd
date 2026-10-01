extends Node3D
## One visible control plate: a hall call when closed, a close button when open.

@onready var cab: ElevatorCab = get_parent().get_parent() as ElevatorCab
@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _apply_use, 0.25)


func interaction_text() -> String:
	return "Close elevator doors" if cab.net_state == ElevatorCab.State.OPEN else "Call elevator"


func interaction_point() -> Vector3:
	return global_position


func can_use(player: Player) -> bool:
	return (
		entity.in_range(player)
		and cab.net_state in [ElevatorCab.State.CLOSED, ElevatorCab.State.OPEN]
		and (cab.net_state != ElevatorCab.State.OPEN or not cab.doorway_occupied())
	)


func use() -> void:
	entity.request_use()


func _apply_use(_player: Player) -> bool:
	return cab.request_doors()
