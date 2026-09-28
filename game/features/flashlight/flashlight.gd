extends Node3D
## Server-owned switches; lights are cosmetic views of the replicated snapshot.

const ACTION := &"toggle_flashlight"

@export var enabled_peers: Dictionary = {}
var _lights: Dictionary[int, SpotLight3D] = {}


func _ready() -> void:
	process_priority = 20
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	Controls.ensure_action(ACTION, [key])
	Network.mode_changed.connect(_reset)
	multiplayer.peer_disconnected.connect(_remove_peer)


func _unhandled_input(event: InputEvent) -> void:
	if not Controls.gameplay_active() or not event.is_action_pressed(ACTION):
		return
	if _player(multiplayer.get_unique_id()) == null:
		return
	request_toggle.rpc_id(1)
	get_viewport().set_input_as_handled()


@rpc("any_peer", "call_local", "reliable")
func request_toggle() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	# No target argument: a sender can only change their own existing player's light.
	if _player(sender) == null:
		return
	var next := enabled_peers.duplicate()
	if next.has(sender):
		next.erase(sender)
	else:
		next[sender] = true
	enabled_peers = next


func _process(_delta: float) -> void:
	for peer: int in _lights.keys():
		if not enabled_peers.has(peer) or _player(peer) == null:
			_lights[peer].free()
			_lights.erase(peer)
	for peer: int in enabled_peers:
		var player := _player(peer)
		if player == null:
			continue
		if not _lights.has(peer):
			var light := SpotLight3D.new()
			light.light_color = Color(1.0, 0.96, 0.85)
			light.light_energy = 3.0
			light.spot_range = 24.0
			light.spot_angle = 32.0
			light.spot_attenuation = 0.7
			light.shadow_enabled = true
			add_child(light)
			_lights[peer] = light
		_lights[peer].global_transform = _beam_transform(player)


func _beam_transform(player: Player) -> Transform3D:
	# Stay at the player's eyes even when F3 pulls the camera behind their body.
	var origin := player.get_global_transform_interpolated().origin
	origin.y += player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5
	var pitch := player.pitch if player.is_local() else player.net_pitch
	var yaw := player.yaw if player.is_local() else player.net_yaw
	return Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), origin)


func _player(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.name == str(peer) and not player.is_queued_for_deletion():
			return player
	return null


func _remove_peer(peer: int) -> void:
	if multiplayer.is_server():
		var next := enabled_peers.duplicate()
		next.erase(peer)
		enabled_peers = next


func _reset(_mode: Network.Mode) -> void:
	# Clear old-session snapshots on clients too, before the new server sync arrives.
	enabled_peers = {}
	for light: SpotLight3D in _lights.values():
		light.free()
	_lights.clear()
