extends Node
## "/suicide" chat command: respawns the requester on demand.
##
## Rather than picking a new spawn point, this drops the requester below the world's
## kill plane (`Game.KILL_Y`), so the server's existing "fell out of the world" watcher
## (see core/game/game.gd) respawns them the exact same way as an accidental fall.
##
## Listens on `COMMAND_GROUP`, the group chat_box.gd calls into for any slash command
## a player types (see features/chat_box/chat_box.gd's `COMMAND_GROUP`).

## Must match chat_box.gd's `COMMAND_GROUP`.
const COMMAND_GROUP := &"chat_commands"

## Accepted spellings; "sucide" was the exact wording of the feature request.
const COMMANDS: Array[String] = ["suicide", "sucide"]


func _ready() -> void:
	add_to_group(COMMAND_GROUP)


func handle_chat_command(peer_id: int, command: String) -> void:
	if not multiplayer.is_server() or not is_suicide_command(command):
		return
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		if player.get_multiplayer_authority() == peer_id:
			player.server_teleport.rpc_id(peer_id, kill_position(player.net_position))
			return


static func is_suicide_command(command: String) -> bool:
	return COMMANDS.has(command)


## `current` with its height dropped below the kill plane, keeping the horizontal
## position so the respawn watcher picks it up on the very next physics tick.
static func kill_position(current: Vector3) -> Vector3:
	return Vector3(current.x, Game.KILL_Y - 1.0, current.z)
