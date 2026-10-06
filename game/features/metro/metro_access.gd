class_name MetroAccess
extends Node3D
## Authored room-owned registration. No inference from display names or world coordinates.

@export var zone_id := ""
@export var label := ""
@export_range(0, 3) var station := 0
@export var slot := 0
@export_enum("public", "developer", "vip") var access_policy := "public"
@export var vip_path: NodePath
var source: MetroElevator
var destination: MetroElevator


func _enter_tree() -> void:
	add_to_group(&"metro_access")


func _ready() -> void:
	_register.call_deferred()


func _register() -> void:
	var metro := MetroService.for_node(self)
	if metro != null:
		metro.register_access(self)


func allowed(player: Player) -> bool:
	if player == null:
		return false
	if access_policy == "developer":
		return DevGate.cheats_enabled(get_tree())
	if access_policy == "vip":
		var club := get_node_or_null(vip_path) as VipLounge
		return (
			discovered(player.get_multiplayer_authority())
			and club.eligible(player.get_multiplayer_authority())
		)
	return true


func discovered(peer: int) -> bool:
	if access_policy != "vip":
		return true
	var club := get_node_or_null(vip_path) as VipLounge
	return club != null and bool(club.profile(peer).get("discovered", false))


func enter_destination(player: Player, entity: NetworkedInteraction) -> bool:
	if not allowed(player):
		return false
	if access_policy == "vip":
		return (get_node(vip_path) as VipLounge).enter(player, entity)
	return true


func leave_destination(player: Player) -> void:
	if access_policy == "vip":
		(get_node(vip_path) as VipLounge).leave(player.get_multiplayer_authority())
