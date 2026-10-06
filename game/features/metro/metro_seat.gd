extends Node3D
## Use shares the existing desktop, controller and touch interaction.
var court: MetroSeating
var index := 0


func _ready() -> void:
	add_to_group(&"interactables")


func can_use(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	if court.net_seats[index] == peer:
		return true
	return court._may_sit(peer, {"seat": index})


func interaction_text() -> String:
	return (
		"Stand up" if court.net_seats[index] == multiplayer.get_unique_id() else "Sit on the metro"
	)


func use() -> void:
	if court.is_seated(multiplayer.get_unique_id()):
		court.request_stand()
	else:
		court.request_sit(index)
