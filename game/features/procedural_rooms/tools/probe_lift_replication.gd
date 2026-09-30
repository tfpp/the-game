extends Node3D
## Real transport probe: a late peer joins an already-moving cab and observes docking.

const Layout := preload("res://features/procedural_rooms/world_layout.gd")
var _lift: ProceduralMovingLift
var _client := false
var _elapsed := 0.0
var _saw_movement := false


func _ready() -> void:
	process_physics_priority = 100
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2)
	var peer := WebSocketMultiplayerPeer.new()
	_client = args[0] == "client"
	var error := (
		peer.create_client("ws://127.0.0.1:" + args[1])
		if _client
		else peer.create_server(int(args[1]), "127.0.0.1")
	)
	assert(error == OK)
	multiplayer.multiplayer_peer = peer
	_lift = Layout.build(self).get_node("Lift") as ProceduralMovingLift
	if not _client:
		assert(_lift.request_floor(0))
	else:
		assert(not _lift.request_floor(0), "Client cannot mutate elevator state")


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _client and _lift._received_snapshot:
		if (
			_lift.net_phase == ProceduralMovingLift.Phase.MOVING
			and _lift.net_height > 0
			and _lift.net_height < 16
		):
			_saw_movement = true
			assert(_lift.net_height > 0 and _lift.net_height < 16)
			assert(_lift.cab_door._amount == 0)
			for gate: ProceduralSlidingDoor in _lift.gates:
				assert(gate._amount == 0)
		if (
			_saw_movement
			and _lift.net_phase == ProceduralMovingLift.Phase.DOCKED
			and _lift.net_aperture == 1
		):
			assert(_lift.net_floor == 0)
			assert(absf(_lift.cab.position.y) < .08)
			assert(_lift.gates[0]._amount == 1 and _lift.gates[4]._amount == 0)
			print("LIFT_LATE_JOIN PASS: moving cab, guarded shaft, aligned arrival")
			get_tree().quit()
	if _elapsed > 13:
		get_tree().quit(1 if _client else 0)
