extends Node3D
## Validated landing calls and in-cab floor buttons for one physical elevator.

const Showcase := preload("res://features/procedural_rooms/showcase.gd")
const BUTTON_MODEL := preload("res://features/procedural_rooms/elevator_button_model.tscn")
@export var floor_index := 4
@export var ride_button := false
@export var lift_path := NodePath("../../Lift")
@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"world_lift_controls")
	if not ride_button:
		add_to_group(&"world_lift_stops")
	add_to_group(&"interactables")
	var model := BUTTON_MODEL.instantiate() as MeshInstance3D
	if not ride_button:
		model.rotation.y = -PI / 2
		model.position.z = -.27
	add_child(model)
	var label := Showcase.placard(
		self,
		"B%d" % (5 - floor_index),
		Vector3(.18 if ride_button else 0, 1.6, 0 if ride_button else -.07)
	)
	label.font_size = 20
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation.y = -PI / 2 if ride_button else PI
	entity.interaction_range = 1.6 if ride_button else 2.5
	entity.register_use(_can_use, _travel, .4)


func lift() -> ProceduralMovingLift:
	return get_node_or_null(lift_path) as ProceduralMovingLift


func _can_use(player: Player) -> bool:
	var owner := lift()
	return (
		owner != null
		and entity.in_range(player)
		and owner.net_phase == ProceduralMovingLift.Phase.DOCKED
		and owner.net_floor != floor_index
		and (not ride_button or owner.contains(player))
		and not owner.doorway_occupied()
	)


func _travel(_player: Player) -> bool:
	return lift().request_floor(floor_index)


func use() -> void:
	entity.request_use()


func can_use(player: Player) -> bool:
	return _can_use(player)


func interaction_text() -> String:
	return ("Ride to B%d" if ride_button else "Call elevator to B%d") % (5 - floor_index)
