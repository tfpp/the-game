class_name SmecklePickup
extends StaticBody3D
## A coin that grants the collecting player a random handful of Smeckles, then
## disappears until a cooldown elapses. Only the server decides the reward and
## reopens the pickup; `available` is the one replicated flag, so every peer shows
## or hides the same coin and clients can't collect twice by racing the cooldown.

const PICKUP_RANGE := 2.0
const COOLDOWN_S := 20.0
const REWARD_MIN := 3
const REWARD_MAX := 12
const SPIN_RATE := 1.5

@export var available := true

@onready var _visual: Node3D = $Visual
@onready var _timer: Timer = $Timer


func _ready() -> void:
	add_to_group(&"interactables")
	_timer.wait_time = COOLDOWN_S
	_timer.one_shot = true
	_timer.timeout.connect(_on_cooldown_finished)


func _process(delta: float) -> void:
	_visual.visible = available
	if available:
		_visual.rotate_y(delta * SPIN_RATE)


func interaction_text() -> String:
	return "Pick up Smeckles"


func can_use(player: Player) -> bool:
	if not available:
		return false
	return global_position.distance_to(player.net_position) <= PICKUP_RANGE


func use() -> void:
	request_collect.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_collect() -> void:
	if not multiplayer.is_server() or not available:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	available = false
	_timer.start()
	var smeckles := get_parent() as Smeckles
	if smeckles != null:
		smeckles.grant(peer_id, randi_range(REWARD_MIN, REWARD_MAX))


func _on_cooldown_finished() -> void:
	available = true


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null
