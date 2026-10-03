extends Node3D
## A single booth seat. Use sits down or stands up; the court's server validates.

const USE_RANGE := 1.8

## Casino anchors use an authored cushion point and a floor-relative exit.
@export var casino_seat := false
@export var exit_offset := Vector3.ZERO
@export var seat_label := "Sit in the booth"
## Decorative card-table guest yields the chair, then returns when it is free.
@export var guest_path: NodePath

var court: FoodCourt
var index := 0


func _ready() -> void:
	add_to_group(&"interactables")


func _process(_delta: float) -> void:
	if guest_path.is_empty() or court == null or index >= court.net_seats.size():
		return
	var guest := get_node_or_null(guest_path) as Node3D
	if guest != null:
		guest.visible = court.net_seats[index] == 0


func can_use(player: Player) -> bool:
	if court == null or index >= court.net_seats.size():
		return false
	var occupant := court.net_seats[index]
	if occupant != 0:
		return occupant == multiplayer.get_unique_id()
	if court.is_seated(multiplayer.get_unique_id()):
		return false
	return global_position.distance_to(player.global_position) <= USE_RANGE


func interaction_text() -> String:
	if court.net_seats[index] == multiplayer.get_unique_id():
		return "Stand up"
	return seat_label


func use() -> void:
	if court.net_seats[index] == multiplayer.get_unique_id():
		court.request_stand()
	else:
		court.request_sit(index)
