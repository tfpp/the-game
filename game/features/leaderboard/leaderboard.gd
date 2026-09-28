class_name Leaderboard
extends Node
## Server-authoritative jump counter, the one stat the Esc-menu leaderboard panel
## (leaderboard_panel.gd) needs that no existing feature already owns: money comes
## from features/money's `PlayerMoney.balances` and kills from features/combat's
## `Combat.kills`.
##
## `Player.jumped` (core/player/player.gd) only ever fires for the local peer's own
## player (puppets skip physics entirely), so each client reports its own jumps to
## the server with `request_record_jump`, the same any_peer-RPC-validated-by-the-
## server pattern `features/player_models` uses for body type requests.

## peer_id -> int, replicated (server -> everyone) like features/money's `balances`.
@export var jumps: Dictionary = {}

## The local player currently wired to `_on_local_jump`, so a respawn or late spawn
## doesn't leave us double-connected or listening to a freed node.
var _jump_listener: Player


func _ready() -> void:
	add_to_group(&"leaderboard")
	Network.mode_changed.connect(_reset)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if is_instance_valid(_jump_listener) and _jump_listener == player:
		return
	if is_instance_valid(_jump_listener) and _jump_listener.jumped.is_connected(_on_local_jump):
		_jump_listener.jumped.disconnect(_on_local_jump)
	_jump_listener = player
	if player != null:
		player.jumped.connect(_on_local_jump)


func jumps_for(peer_id: int) -> int:
	return int(jumps.get(peer_id, 0))


## Clients request their own jump be counted; the server validates the sender.
@rpc("any_peer", "call_local", "reliable")
func request_record_jump() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var next := jumps.duplicate()
	next[peer_id] = jumps_for(peer_id) + 1
	jumps = next


func _on_local_jump() -> void:
	request_record_jump.rpc_id(1)


func _reset(_mode: Network.Mode) -> void:
	jumps = {}
	_jump_listener = null
