class_name ArcadeComputer
extends StaticBody3D
## One authoritative game per terminal. Clients send only screen coordinates.

const USE_RANGE := 3.5
const START := Rect2i(90, 155, 140, 32)
const TURKEY := Rect2i(105, 48, 110, 102)
const ROUND_SECONDS := 30.0
const PUNCH_MS := 150
const LEASE_MS := 6000

@export var state: Dictionary = initial_state()
var _lease := 0
var _last_punch := -PUNCH_MS
var _remaining := 0.0
var _view: Node3D
var _activation := 0.0


static func initial_state() -> Dictionary:
	return {
		"owner": 0,
		"epoch": 0,
		"name": "",
		"score": 0,
		"best": 0,
		"seconds": 0,
		"hits": 0,
		"running": false
	}


func _ready() -> void:
	add_to_group(&"interactables")
	multiplayer.peer_disconnected.connect(_peer_left)
	Network.mode_changed.connect(_mode_changed)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		advance(delta)
	_activation -= delta
	if _activation > 0:
		return
	_activation = 0.2
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	var nearby := player != null and ScummArcadeRoom.contains(player.global_position)
	if nearby and _view == null and DisplayServer.get_name() != "headless":
		ensure_view()
	elif not nearby and _view != null:
		_view.close(false)
		_view.queue_free()
		_view = null


func ensure_view() -> void:
	if _view == null:
		_view = preload("res://features/computers/computer_view.gd").new()
		add_child(_view)
		_view.build(self)


func interaction_point() -> Vector3:
	return to_global(Vector3(0, 1.65, 0.46))


func interaction_text() -> String:
	return "Turkey Puncher computer" if int(state.owner) == 0 else "Computer in use — watch screen"


func can_use(player: Player) -> bool:
	var eye := player.net_position + Vector3.UP * 0.65
	var offset := interaction_point() - eye
	if offset.length() > USE_RANGE or offset.length() < 0.01:
		return false
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	if look.dot(offset.normalized()) < 0.7 or to_local(eye).z <= 0.46:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		eye, to_global(Vector3(0, 1.65, 0)), 1, [player.get_rid()]
	)
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") == self


func use() -> void:
	request_open.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_open() -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	var player := player_for(peer)
	if player == null or not can_use(player) or int(state.owner) != 0:
		return
	state = state.duplicate()
	state.owner = peer
	state.epoch = int(state.epoch) + 1
	state.name = player.display_name
	_lease = Time.get_ticks_msec() + LEASE_MS
	opened.rpc_id(peer, int(state.epoch))


@rpc("authority", "call_local", "reliable")
func opened(epoch: int) -> void:
	if get_tree().get_first_node_in_group(&"modal_ui") != null:
		request_close.rpc_id(1, epoch)
		return
	ensure_view()
	_view.open(epoch)


@rpc("any_peer", "call_local", "reliable")
func request_click(epoch: int, point: Vector2i) -> void:
	if not multiplayer.is_server() or not _valid_session(_sender(), epoch):
		return
	if not state.running:
		if not START.has_point(point):
			return
		state = state.duplicate()
		state.score = 0
		state.hits = 0
		state.running = true
		state.seconds = int(ROUND_SECONDS)
		_remaining = ROUND_SECONDS
		_last_punch = -PUNCH_MS
	elif TURKEY.has_point(point) and Time.get_ticks_msec() - _last_punch >= PUNCH_MS:
		_last_punch = Time.get_ticks_msec()
		state = state.duplicate()
		state.hits = int(state.hits) + 1
		state.score = int(state.score) + 10
		state.best = maxi(int(state.best), int(state.score))
		punch_sound.rpc()


@rpc("authority", "call_local", "unreliable")
func punch_sound() -> void:
	GameAudio.play_at(self, &"hit", interaction_point())


@rpc("any_peer", "call_local", "reliable")
func keep_alive(epoch: int) -> void:
	if multiplayer.is_server() and _valid_session(_sender(), epoch):
		_lease = Time.get_ticks_msec() + LEASE_MS


@rpc("any_peer", "call_local", "reliable")
func request_close(epoch: int) -> void:
	if multiplayer.is_server() and int(state.owner) == _sender() and int(state.epoch) == epoch:
		_release()


func advance(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if int(state.owner) != 0:
		var player := player_for(int(state.owner))
		if player == null or not can_use(player) or Time.get_ticks_msec() > _lease:
			_release()
	if state.running:
		_remaining = maxf(0, _remaining - delta)
		if int(ceil(_remaining)) != int(state.seconds):
			state = state.duplicate()
			state.seconds = int(ceil(_remaining))
			state.running = _remaining > 0


func player_for(peer: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node is Player and node.get_multiplayer_authority() == peer:
			return node as Player
	return null


func _valid_session(peer: int, epoch: int) -> bool:
	var player := player_for(peer)
	return (
		peer == int(state.owner)
		and epoch == int(state.epoch)
		and Time.get_ticks_msec() <= _lease
		and player != null
		and can_use(player)
	)


func _sender() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()


func _release() -> void:
	state = state.duplicate()
	state.owner = 0
	state.running = false
	state.seconds = 0
	_remaining = 0


func _peer_left(peer: int) -> void:
	if multiplayer.is_server() and int(state.owner) == peer:
		_release()


func _mode_changed(_mode: Network.Mode) -> void:
	if _view != null:
		_view.close(false)
	state = initial_state()
	_remaining = 0
	_lease = 0
