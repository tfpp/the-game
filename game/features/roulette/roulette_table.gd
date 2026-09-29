class_name RouletteTable
extends StaticBody3D
## Clients request a spin; only the server validates, chooses, advances and settles it.
## One atomic replicated snapshot includes the spinning ball and the final result.
## Unlike the slot machine, the table can be used from either long side.

const USE_RANGE := 3.5
const SPIN_DURATION_S := 3.0
const FRAME_S := 0.1

@export var state: Dictionary = initial_state()

var _wheel := RouletteWheel.new()
var _result := 0
var _elapsed := 0.0
var _frame_elapsed := 0.0


func _ready() -> void:
	add_to_group(&"interactables")
	Network.mode_changed.connect(_on_mode_changed)


static func initial_state() -> Dictionary:
	return {"spin": 0, "spinning": false, "ball": 0, "number": 0, "color": "", "operator": ""}


func interaction_text() -> String:
	return "Roulette table — spinning…" if state["spinning"] else "Spin the roulette wheel"


func interaction_point() -> Vector3:
	return to_global(Vector3(0, 0.9, 0))


func can_use(player: Player) -> bool:
	var eye := (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5)
	)
	var center := interaction_point()
	var offset := center - eye
	if offset.length() > USE_RANGE or offset.length() < 0.05:
		return false
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	if look.dot(offset.normalized()) < 0.6:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, center, 1, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == self


func use() -> void:
	request_spin.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_spin() -> void:
	if not multiplayer.is_server() or state["spinning"]:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	_begin_spin(peer_id, player.display_name)


func _begin_spin(peer_id: int, display_name: String) -> void:
	_result = _wheel.next_result()
	_elapsed = 0.0
	_frame_elapsed = 0.0
	state = {
		"spin": int(state["spin"]) + 1,
		"spinning": true,
		"ball": 0,
		"number": 0,
		"color": "",
		"operator": display_name if display_name else "Player %d" % peer_id
	}


func _process(delta: float) -> void:
	if multiplayer.is_server() and state["spinning"]:
		_advance(delta)


func _advance(delta: float) -> void:
	if not state["spinning"]:
		return
	_elapsed += delta
	_frame_elapsed += delta
	if _frame_elapsed < FRAME_S:
		return
	_frame_elapsed = 0.0
	var next := state.duplicate(true)
	if _elapsed >= SPIN_DURATION_S:
		next["spinning"] = false
		next["ball"] = _result
		next["number"] = _result
		next["color"] = RouletteWheel.color_for(_result)
	else:
		next["ball"] = int(_elapsed / FRAME_S) % RouletteWheel.POCKET_COUNT
	state = next


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null


func _on_mode_changed(_mode: Network.Mode) -> void:
	# Do not carry local/offline results into a newly joined server, or vice versa.
	state = initial_state()
	_wheel = RouletteWheel.new()
	_result = 0
