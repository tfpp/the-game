extends AnimatableBody3D
## A small ferry that cruises back and forth between two docks in the room, carrying
## whoever is standing on deck.
##
## Server-authoritative: the server advances the route timeline (`NycFerryPath`) and
## writes the resulting position; `sync_to_physics` (default on for AnimatableBody3D)
## propagates that motion to any CharacterBody3D standing on it, on every peer, since
## each peer runs the same physics world. Non-server peers just play back the
## replicated `net_position` instead of computing it themselves.

const ROUTE_LENGTH_M := 30.0
const SPEED_MPS := 3.0
const DOCK_WAIT_S := 3.0

## Replicated state (server -> everyone). See the synchronizer config in feature.tscn.
@export var net_position := Vector3.ZERO

var _dock_a := Vector3.ZERO
var _dock_b := Vector3.ZERO
var _elapsed := 0.0


func _ready() -> void:
	_dock_a = global_position
	_dock_b = _dock_a + Vector3(0.0, 0.0, ROUTE_LENGTH_M)
	net_position = _dock_a


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_elapsed += delta
		var distance := NycFerryPath.distance_along_route(
			_elapsed, ROUTE_LENGTH_M, SPEED_MPS, DOCK_WAIT_S
		)
		global_position = _dock_a.lerp(_dock_b, distance / ROUTE_LENGTH_M)
		net_position = global_position
	else:
		global_position = net_position
