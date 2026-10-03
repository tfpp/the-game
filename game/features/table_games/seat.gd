extends Node3D
## Seats are free to use; joining a wager still uses the table's play controls.
var court: CrownTableSeating
var index := 0


func _ready() -> void:
	add_to_group(&"interactables")


func can_use(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	return court.is_seated(peer) or court._may_sit(peer, {"seat": index})


func interaction_point() -> Vector3:
	return global_position + Vector3.UP * .65


func interaction_text() -> String:
	return (
		"Table controls / stand up"
		if court.is_seated(multiplayer.get_unique_id())
		else "Sit at %s · no wager" % court.table.game.replace("_", " ")
	)


func use() -> void:
	if not court.is_seated(multiplayer.get_unique_id()):
		court.request_sit(index)
	court.table.open_screen()
