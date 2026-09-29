extends Node3D
## A single booth seat. Use sits down or stands up; the court's server validates.

const USE_RANGE := 1.8

var court: FoodCourt
var index := 0


func _ready() -> void:
	add_to_group(&"interactables")


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
	return "Sit in the booth"


func use() -> void:
	if court.net_seats[index] == multiplayer.get_unique_id():
		court.request_stand()
	else:
		court.request_sit(index)
