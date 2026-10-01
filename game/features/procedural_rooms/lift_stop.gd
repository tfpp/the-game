extends Node3D
## Validated landing calls and in-cab floor buttons for one physical elevator.

const Showcase := preload("res://features/procedural_rooms/showcase.gd")
const BUTTON_MODEL := preload("res://features/procedural_rooms/elevator_button_model.tscn")
@export var floor_index := 4
@export var ride_button := false
@export var aim_half_width := .25
@export var lift_path := NodePath("../../Lift")
var light: MeshInstance3D
@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"world_lift_controls")
	if not ride_button:
		add_to_group(&"world_lift_stops")
	add_to_group(&"interactables")
	if ride_button:
		light = MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(.0375, .039)
		light.mesh = mesh
		light.position = Vector3(-.002, 0, .131)
		light.rotation.y = -PI / 2
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		light.material_override = material
		add_child(light)
		entity.interaction_offset = Vector3.ZERO
	else:
		var model := BUTTON_MODEL.instantiate() as MeshInstance3D
		model.rotation.y = -PI / 2
		model.position.z = -.27
		add_child(model)
		var label := Showcase.placard(self, _floor_label(), Vector3(0, 1.6, -.07))
		label.font_size = 20
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.rotation.y = PI
	entity.interaction_range = 2.2 if ride_button else 2.5
	entity.register_use(_can_use, _travel, .4)


func lift() -> ProceduralMovingLift:
	return get_node_or_null(lift_path) as ProceduralMovingLift


func _can_use(player: Player) -> bool:
	var owner := lift()
	return (
		owner != null
		and floor_index < owner.gates.size()
		and entity.in_range(player)
		and owner.net_phase == ProceduralMovingLift.Phase.DOCKED
		and (ride_button or owner.net_floor != floor_index)
		and (not ride_button or owner.contains(player))
		and not owner.doorway_occupied()
	)


func _travel(_player: Player) -> bool:
	if ride_button and lift().net_floor == floor_index:
		return true
	return lift().request_floor(floor_index)


func use() -> void:
	entity.request_use()


func can_use(player: Player) -> bool:
	return _can_use(player) and (not ride_button or aimed_at(player))


func aimed_at(player: Player) -> bool:
	var eye := (
		player.global_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * .5)
	)
	var ray := Basis.from_euler(Vector3(player.pitch, player.yaw, 0)) * Vector3.FORWARD
	var origin := to_local(eye)
	var direction := global_basis.inverse() * ray
	if direction.x <= .001:
		return false
	var distance := -origin.x / direction.x
	var hit := origin + direction * distance
	return distance > 0 and absf(hit.y) <= .055 and absf(hit.z) <= aim_half_width


func _process(_delta: float) -> void:
	if light == null or lift() == null:
		return
	var material := light.material_override as StandardMaterial3D
	material.albedo_color = (
		Color("93d078")
		if lift().net_floor == floor_index
		else (Color("f7ba52") if lift().net_target == floor_index else Color("736a49"))
	)


func interaction_text() -> String:
	if ride_button and lift().net_floor == floor_index:
		return "Already at %s" % _floor_label()
	return ("Ride to %s" if ride_button else "Call elevator to %s") % _floor_label()


func _floor_label() -> String:
	var owner := lift()
	return (
		owner.stop_label(floor_index)
		if owner != null
		else ProceduralMovingLift.floor_label(floor_index)
	)
