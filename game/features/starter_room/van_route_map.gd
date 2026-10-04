extends Node3D
## Separate map panel leaves the cab handle free for door interaction.

@onready var van: OperationsVan = get_parent()


func interaction_text() -> String:
	return van.interaction_text()


func can_use(player: Player) -> bool:
	return van.can_use(player)


func use() -> void:
	van.use()
