class_name NetworkedInteraction
extends NetworkedEntity
## Player interaction policy layered on the generic entity component.

const DEFAULT_RANGE := 2.5

@export var interaction_range := DEFAULT_RANGE
@export var interaction_offset := Vector3.ZERO

var _can_use: Callable
var _use: Callable


## Feature callbacks receive the server-resolved Player, never a client-supplied ID.
func register_use(can_use: Callable, apply: Callable, cooldown_seconds: float = 0.0) -> bool:
	if not can_use.is_valid() or not apply.is_valid() or _can_use.is_valid():
		return false
	if not register_action(&"use", _validate_use, _apply_use, cooldown_seconds):
		return false
	_can_use = can_use
	_use = apply
	return true


func request_use() -> void:
	request_action(&"use")


func in_range(player: Player) -> bool:
	var spatial := target() as Node3D
	if not is_instance_valid(player) or spatial == null:
		return false
	var origin := spatial.to_global(interaction_offset)
	return origin.distance_squared_to(player.net_position) <= interaction_range * interaction_range


func player_for_peer(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer:
			return player
	return null


func _validate_use(peer: int, payload: Dictionary) -> bool:
	if not payload.is_empty():
		return false
	var player := player_for_peer(peer)
	return in_range(player) and _can_use.is_valid() and bool(_can_use.call(player))


func _apply_use(peer: int, _payload: Dictionary) -> bool:
	return _use.is_valid() and bool(_use.call(player_for_peer(peer)))
