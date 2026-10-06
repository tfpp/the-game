class_name MetroElevator
extends ElevatorCab
## Reuses the cab's obstruction/capacity controls; MetroService owns loaded transfers.

var access: MetroAccess
var outbound := true
var metro: MetroService
var partner: MetroElevator
var _visual_range := 0.0


func _depart() -> void:
	net_state = State.CLOSED
	_state_elapsed = 0
	if _trip_pending and metro != null and not net_riding:
		metro.depart_elevator(self, _collect_occupants())
	_trip_pending = false


func _process(delta: float) -> void:
	super._process(delta)
	_visual_range -= delta
	if _visual_range > 0:
		return
	_visual_range = 0.25
	var local: Player
	for node: Node in get_tree().get_nodes_in_group(&"local_player"):
		if node.multiplayer == multiplayer:
			local = node as Player
			break
	var nearby := local != null and local.global_position.distance_to(global_position) < 75
	visible = nearby
	($Car/CabLight as OmniLight3D).visible = (
		nearby and local.global_position.distance_to(global_position) < 6
	)
	if nearby and access != null and not outbound:
		($Car/Sign as SignBoard).text = (
			access.label.to_upper() if access.discovered(multiplayer.get_unique_id()) else "PRIVATE"
		)
