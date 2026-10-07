class_name AdventureMachine
extends StaticBody3D
## Shared static cabinet; connection-scoped stories stay private and server-owned.

const Story := preload("res://features/adventure_machine/story.gd")
const Screen := preload("res://features/adventure_machine/screen.gd")
const ACTION_DELAY_MSEC := 120

var _stories: Dictionary[int, Story] = {}
var _next_action: Dictionary[int, int] = {}
var _screen: Screen
@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _open)
	entity.register_action(&"choose", _may_choose, _choose)
	entity.event_received.connect(_event)
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(_disconnect)
	Network.mode_changed.connect(_mode_changed)


func interaction_text() -> String:
	return "Brine & Bureaucracy · play text adventure (free)"


func can_use(player: Player) -> bool:
	if not can_play(player):
		return false
	var eye := _eye(player)
	var offset := to_global(entity.interaction_offset) - eye
	if offset.length_squared() < .0001:
		return false
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	return look.dot(offset.normalized()) > .75


## Modal play retains range/front/obstruction/life checks, without requiring a new aim.
func can_play(player: Player) -> bool:
	if not entity.in_range(player):
		return false
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	var peer := player.get_multiplayer_authority()
	if combat != null and (combat.is_respawning(peer) or combat.health_for(peer) <= 0):
		return false
	var eye := _eye(player)
	if (eye - global_position).dot(global_basis.z) <= .05:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		eye, to_global(entity.interaction_offset), 1, [player.get_rid()]
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == self


func _eye(player: Player) -> Vector3:
	return (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * .5)
	)


func use() -> void:
	entity.request_use()


func request_choice(id: String, revision: int) -> void:
	entity.request_action(&"choose", {"choice": id, "revision": revision})


func _open(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	if not _stories.has(peer):
		_stories[peer] = Story.new()
	entity.send_event(&"open", _stories[peer].page(), peer)
	return true


func _may_choose(peer: int, payload: Dictionary) -> bool:
	return (
		payload.size() == 2
		and payload.get("choice") is String
		and payload.get("revision") is int
		and _stories.has(peer)
		and can_play(entity.player_for_peer(peer))
		and Time.get_ticks_msec() >= _next_action.get(peer, 0)
		and payload["revision"] == _stories[peer].revision
		and _stories[peer].allows(payload["choice"])
	)


func _choose(peer: int, payload: Dictionary) -> bool:
	if not _stories[peer].choose(payload["choice"]):
		return false
	_next_action[peer] = Time.get_ticks_msec() + ACTION_DELAY_MSEC
	entity.send_event(&"page", _stories[peer].page(), peer)
	return true


func _event(event: StringName, payload: Dictionary) -> void:
	if Network.mode == Network.Mode.SERVER:
		return
	if event == &"open":
		if not can_play(entity.player_for_peer(multiplayer.get_unique_id())):
			return
		for modal: Node in get_tree().get_nodes_in_group(&"modal_ui"):
			if modal != _screen:
				return
		if not is_instance_valid(_screen):
			_screen = Screen.new()
			_screen.machine = self
			add_child(_screen)
		_screen.open(payload)
	elif event == &"page" and is_instance_valid(_screen):
		_screen.update_page(payload)


func _disconnect(peer: int) -> void:
	if entity.is_authority():
		_stories.erase(peer)
		_next_action.erase(peer)


func _reset(_mode: Network.Mode) -> void:
	_stories.clear()
	_next_action.clear()


func _mode_changed(mode: Network.Mode) -> void:
	# Discard a previous offline story even when this process becomes a client.
	_reset(mode)
	if is_instance_valid(_screen):
		_screen.close(false)
