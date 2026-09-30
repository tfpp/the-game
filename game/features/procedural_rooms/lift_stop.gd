extends Node3D
## Prototype lift: validated transport between visible cab stops, using Player teleport.

const Kit := preload("res://features/procedural_rooms/example_kit.gd")
const Showcase := preload("res://features/procedural_rooms/showcase.gd")
const MATERIAL := preload("res://features/procedural_rooms/materials/elevator.tres")
@export var floor_index := 4
@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"world_lift_stops")
	Kit.box(self, "ControlPanel", Vector3(0.7, 1, 0.12), Vector3(0.95, 1.4, 0), MATERIAL)
	Showcase.placard(self, "ELEVATOR\n[E] TO B%d" % (5 - destination_index()), Vector3(0, 2.5, 0))
	entity.register_use(_can_use, _travel, 1.0)


func destination_index() -> int:
	return 0 if floor_index == 4 else floor_index + 1


func _can_use(player: Player) -> bool:
	return entity.in_range(player)


func _travel(player: Player) -> bool:
	for stop: Node3D in get_tree().get_nodes_in_group(&"world_lift_stops"):
		if stop.get("floor_index") == destination_index():
			player.server_teleport.rpc_id(
				player.get_multiplayer_authority(), stop.global_position + Vector3.UP, PI
			)
			return true
	return false


func use() -> void:
	entity.request_use()
