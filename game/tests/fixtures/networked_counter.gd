extends Node
## Generic non-spatial entity fixture: no player, door or inventory dependencies.

@export var value := 7
@export var last_peer := 0

@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	entity.register_action(&"add", _can_add, _add)


func _can_add(_peer: int, payload: Dictionary) -> bool:
	return payload.size() == 1 and payload.get("amount") is int and payload["amount"] in [1, 2, 3]


func _add(peer: int, payload: Dictionary) -> bool:
	value += int(payload["amount"])
	last_peer = peer
	return true
