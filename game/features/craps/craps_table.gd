class_name CrapsTable
extends StaticBody3D
## Free shared pass-line rounds. Only the server chooses dice and advances the point.

const USE_RANGE := 3.5
const ROLL_DURATION := 2.0

@export var state: Dictionary = initial_state()

var _rng := RandomNumberGenerator.new()
var _dice := Vector2i.ONE
var _elapsed := 0.0


func _ready() -> void:
	add_to_group(&"interactables")
	Network.mode_changed.connect(_on_mode_changed)


static func initial_state() -> Dictionary:
	return {
		"roll": 0, "rolling": false, "point": 0, "dice": Vector2i.ONE, "outcome": "", "operator": ""
	}


## A zero point is the come-out roll; otherwise only the point or seven resolves it.
static func resolve_roll(point: int, total: int) -> Dictionary:
	if point == 0:
		if total == 7 or total == 11:
			return {"point": 0, "outcome": "win"}
		if total in [2, 3, 12]:
			return {"point": 0, "outcome": "lose"}
		return {"point": total, "outcome": "point"}
	if total == point:
		return {"point": 0, "outcome": "win"}
	if total == 7:
		return {"point": 0, "outcome": "lose"}
	return {"point": point, "outcome": "continue"}


func interaction_text() -> String:
	if state["rolling"]:
		return "Craps — dice rolling…"
	if int(state["point"]) > 0:
		return "Craps — roll for point %d (free play)" % int(state["point"])
	return "Craps — roll come-out (free play)"


func interaction_point() -> Vector3:
	return to_global(Vector3(0, 0.95, 0))


func can_use(player: Player) -> bool:
	var eye := (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5)
	)
	var offset := interaction_point() - eye
	if offset.length() > USE_RANGE or offset.length() < 0.05:
		return false
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	if look.dot(offset.normalized()) < 0.6:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, interaction_point(), 1, [player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") == self


func use() -> void:
	request_roll.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_roll() -> void:
	if not multiplayer.is_server() or state["rolling"]:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer := sender if sender != 0 else multiplayer.get_unique_id()
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer:
			if can_use(player):
				_begin_roll(player.display_name)
			return


func _begin_roll(display_name: String) -> void:
	if not multiplayer.is_server() or state["rolling"]:
		return
	_dice = Vector2i(_rng.randi_range(1, 6), _rng.randi_range(1, 6))
	_elapsed = 0.0
	var next := state.duplicate(true)
	next["roll"] = int(state["roll"]) + 1
	next["rolling"] = true
	next["operator"] = display_name if not display_name.is_empty() else "Player"
	state = next


func _process(delta: float) -> void:
	_advance(delta)


func _advance(delta: float) -> void:
	if not multiplayer.is_server() or not state["rolling"]:
		return
	_elapsed += delta
	if _elapsed < ROLL_DURATION:
		return
	var next := state.duplicate(true)
	var result := resolve_roll(int(state["point"]), _dice.x + _dice.y)
	next["rolling"] = false
	next["dice"] = _dice
	next["point"] = result["point"]
	next["outcome"] = result["outcome"]
	state = next


func _on_mode_changed(_mode: Network.Mode) -> void:
	state = initial_state()
	_elapsed = 0.0
	_dice = Vector2i.ONE
