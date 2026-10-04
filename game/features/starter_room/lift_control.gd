extends Node3D

@onready var lift: WorkshopLift = get_parent()


func interaction_text() -> String:
	return lift.interaction_text()


func can_use(player: Player) -> bool:
	return lift.can_use(player)


func use() -> void:
	lift.use()
