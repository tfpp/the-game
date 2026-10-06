extends "res://features/elevator/call_button.gd"
## Keep the existing authenticated use/range check and expose destination restrictions.


func can_use(player: Player) -> bool:
	var lift := cab as MetroElevator
	return super.can_use(player) and (lift.outbound or lift.access.allowed(player))


func interaction_text() -> String:
	var lift := cab as MetroElevator
	var player := lift.metro.player(multiplayer.get_unique_id())
	if not lift.outbound and not lift.access.allowed(player):
		return "Destination access required"
	return super.interaction_text()
