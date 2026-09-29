class_name KebabShop
extends Node3D
## Orders transfer synchronously through the existing inventory, never a parallel stash.

const SERVE_SECONDS := 3.0

@export var net_phase := 0.0:
	set(value):
		net_phase = value
		_visual_phase = value
@export var net_serving := 0.0

var _visual_phase := 0.0

@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var view: Node3D = $ShopView


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _serve)
	entity.session_reset.connect(_reset_session)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		net_phase = fmod(net_phase + delta, TAU * 100.0)
		net_serving = maxf(0.0, net_serving - delta)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		_visual_phase += delta
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.global_position.distance_squared_to(global_position) < 2025.0:
		view.present(_visual_phase, net_serving)


func can_use(player: Player) -> bool:
	# Customers stay on the front side of the counter; its back is the kitchen.
	return entity.in_range(player) and to_local(player.net_position).z > 0.45 and net_serving <= 0.0


func interaction_text() -> String:
	var hand := Hand.for_peer(get_tree(), multiplayer.get_unique_id())
	if hand != null and not hand.inventory().can_collect("kebab"):
		return "Aylin — make room in your backpack for a kebab"
	return "Order a Turkish kebab from Aylin — FREE"


func use() -> void:
	entity.request_use()


func _serve(player: Player) -> bool:
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	if hand == null or not hand.inventory().collect("kebab"):
		return false
	net_serving = SERVE_SECONDS
	return true


func _reset_session(_mode: Network.Mode) -> void:
	net_phase = 0.0
	net_serving = 0.0
