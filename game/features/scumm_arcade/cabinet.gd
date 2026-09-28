class_name ScummArcadeCabinet
extends StaticBody3D
## The server owns control and immutable input ticks. Each client interprets the
## demo locally. Multiplayer messages contain only inputs, ticks and checksums.

const USE_RANGE := 3.5
const LEASE_MS := 6000
const CHECKPOINT_INTERVAL := 250
const SAVE_SECONDS := 5.0

@export_enum("monkey", "samnmax", "atlantis", "pass", "tentacle") var game_id := "monkey"

@export var state: Dictionary = {
	"epoch": 1, "tick": 0, "owner": 0, "operator": "", "running": false, "finished": false
}

var session := ScummArcadeSession.new()
var local_tick := 0
var local_error := ""
var _runtime_id := ""
var _epoch := 0
var _elapsed := 0.0
var _poll_in := 0.0
var _lease_until := 0
var _requested_at := -1000
var _waiting := false
var _ready_peers: Dictionary = {}
var _last_request: Dictionary = {}
var _checksums: Dictionary = {}
var _pending_checksums: Dictionary = {}
var _texture: ImageTexture
var _audio: AudioStreamPlayer3D
var _playback: AudioStreamGeneratorPlayback
var _emulator: ScummArcadeEmulator
var _progress: ScummArcadeProgressStore
var _save_in := SAVE_SECONDS
var _saved_tick := -1
var _save_blocked := false
var _view: ScummArcadeView


func _ready() -> void:
	add_to_group(&"interactables")
	Network.mode_changed.connect(_mode_changed)
	multiplayer.peer_disconnected.connect(_peer_left)
	_runtime_id = ScummArcadeEmulator.fingerprint(game_id)
	_emulator = ScummArcadeEmulator.new()
	add_child(_emulator)
	_emulator.frame_ready.connect(_frame_ready)
	_view = ScummArcadeView.new()
	add_child(_view)
	_view.build(self)
	_audio = AudioStreamPlayer3D.new()
	_audio.position = Vector3(0, 1.6, 0.6)
	# max_distance provides a linear fade to silence; no additional inverse falloff.
	_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	_audio.max_distance = 5.0
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.3
	_audio.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_audio.stream = generator
	add_child(_audio)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		_server_advance(delta)
	if (
		DisplayServer.get_name() == "headless"
		and Network.mode != Network.Mode.SERVER
		and not Network.has_flag("scumm-runtime")
	):
		return
	if _epoch != int(state["epoch"]):
		_restart_local()
	if _emulator.status == "failed" and local_error.is_empty():
		local_error = _emulator.failure
		if controls_local():
			request_release.rpc_id(1)
		if multiplayer.is_server():
			state = state.duplicate()
			state["error"] = "Arcade runtime unavailable on the server"
	if _emulator.status != "ready" or _emulator.busy or not local_error.is_empty():
		return
	_poll_in -= delta
	var now := Time.get_ticks_msec()
	if _poll_in <= 0 and (not _waiting or now - _requested_at > 1500):
		_poll_in = 0.1
		_waiting = true
		_requested_at = now
		request_batch.rpc_id(1, _epoch, local_tick, _emulator.runtime_id)


func _server_advance(delta: float) -> void:
	_ensure_progress()
	_save_in -= delta
	if _save_in <= 0:
		_save_progress()
		_save_in = SAVE_SECONDS
	if int(state["owner"]) != 0:
		var player := _player_for_peer(int(state["owner"]))
		if player == null or not _in_range(player) or Time.get_ticks_msec() > _lease_until:
			_release_control()
	if (
		not bool(state["running"])
		or session.finished()
		or _emulator.status != "ready"
		or not _has_audience()
		or session.tick - local_tick >= ScummArcadeSession.BATCH_TICKS
	):
		return
	_elapsed += minf(delta, 0.2)
	while _elapsed >= ScummArcadeSession.TICK_SECONDS:
		_elapsed -= ScummArcadeSession.TICK_SECONDS
		session.advance()
	state = state.duplicate()
	state["tick"] = session.tick
	state["finished"] = session.finished()


func interaction_text() -> String:
	return str(details()["title"]) + (" — play / watch" if is_interactive() else " — watch demo")


func interaction_point() -> Vector3:
	return to_global(Vector3(0, 1.65, 0.6))


func _in_range(player: Player) -> bool:
	return player.net_position.distance_to(global_position) <= USE_RANGE


func can_use(player: Player) -> bool:
	if not _in_range(player):
		return false
	var eye := player.net_position + Vector3.UP * 0.65
	var offset := interaction_point() - eye
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	if offset.length() < 0.01 or look.dot(offset.normalized()) < 0.65:
		return false
	if (eye - global_position).dot(global_basis.z) <= 0:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		eye, to_global(Vector3(0, 1.65, 0)), 1, [player.get_rid()]
	)
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider") == self


func use() -> void:
	_view.open()


func controls_local() -> bool:
	return int(state["owner"]) == multiplayer.get_unique_id()


func send_input(event: Array) -> void:
	if controls_local() and local_error.is_empty():
		request_input.rpc_id(1, int(state["epoch"]), event)


@rpc("any_peer", "call_local", "reliable")
func request_control() -> void:
	if not multiplayer.is_server() or int(state["owner"]) != 0:
		return
	var peer := _sender()
	var player := _player_for_peer(peer)
	if (
		player == null
		or not can_use(player)
		or not _ready_peers.has(peer)
		or session.tick - int(_ready_peers[peer]) > CHECKPOINT_INTERVAL
	):
		return
	state = state.duplicate()
	state["owner"] = peer
	state["operator"] = player.display_name if player.display_name else "Player %d" % peer
	_lease_until = Time.get_ticks_msec() + LEASE_MS


@rpc("any_peer", "call_local", "reliable")
func request_release() -> void:
	if multiplayer.is_server() and _sender() == int(state["owner"]):
		_release_control()


@rpc("any_peer", "call_local", "reliable")
func keep_control() -> void:
	if multiplayer.is_server() and _sender() == int(state["owner"]):
		_lease_until = Time.get_ticks_msec() + LEASE_MS


@rpc("any_peer", "call_local", "reliable")
func request_input(epoch: int, event: Array) -> void:
	if not multiplayer.is_server() or not is_interactive() or epoch != int(state["epoch"]):
		return
	var peer := _sender()
	var player := _player_for_peer(peer)
	if peer != int(state["owner"]) or player == null or not _in_range(player):
		return
	session.enqueue(event)


@rpc("any_peer", "call_local", "reliable")
func request_restart() -> void:
	if not multiplayer.is_server() or _sender() != int(state["owner"]):
		return
	session = ScummArcadeSession.new()
	state = state.duplicate()
	state["epoch"] = int(state["epoch"]) + 1
	state["tick"] = 0
	state["finished"] = false
	state["running"] = false
	_elapsed = 0.0
	_ready_peers.clear()
	_checksums.clear()
	_pending_checksums.clear()
	_save_progress(true)


@rpc("any_peer", "call_local", "reliable")
func request_batch(epoch: int, from_tick: int, signature: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender()
	if _player_for_peer(peer) == null and peer != 1:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_request.get(peer, -1000)) < 40:
		return
	_last_request[peer] = now
	if signature.is_empty() or signature != _runtime_id:
		reject_runtime.rpc_id(peer, "Arcade versions differ; reload the game")
		return
	if epoch != int(state["epoch"]) or from_tick < 0 or from_tick > session.tick:
		return
	_ready_peers[peer] = from_tick
	if not state["running"]:
		state = state.duplicate()
		state["running"] = true
	receive_batch.rpc_id(peer, epoch, from_tick, session.batch(from_tick))


@rpc("authority", "call_local", "reliable")
func receive_batch(epoch: int, from_tick: int, frames: Array) -> void:
	if epoch != _epoch or from_tick != local_tick or _emulator.busy:
		return
	_waiting = false
	# Stop exactly at checksum boundaries, so differently sized replay batches
	# compare the same point. The remainder is requested again on the next pull.
	var until_check := CHECKPOINT_INTERVAL - local_tick % CHECKPOINT_INTERVAL
	if frames.size() > until_check:
		frames.resize(until_check)
	_emulator.advance(frames)


@rpc("authority", "call_local", "reliable")
func reject_runtime(reason: String) -> void:
	local_error = reason
	_emulator.stop()


@rpc("any_peer", "call_local", "reliable")
func report_checksum(epoch: int, tick: int, checksum: int) -> void:
	if not multiplayer.is_server() or epoch != int(state["epoch"]):
		return
	var peer := _sender()
	if not _ready_peers.has(peer) or tick <= 0 or tick > session.tick:
		return
	if tick % CHECKPOINT_INTERVAL != 0:
		return
	# Only the server's locally emulated result is a trusted baseline. A malicious
	# checksum can only reject its sender; it cannot poison other peers' state.
	if peer == 1:
		_checksums[tick] = checksum
		var waiting: Dictionary = _pending_checksums.get(tick, {})
		for other: int in waiting:
			_compare_checksum(other, checksum, int(waiting[other]))
		_pending_checksums.erase(tick)
	elif _checksums.has(tick):
		_compare_checksum(peer, int(_checksums[tick]), checksum)
	else:
		if not _pending_checksums.has(tick):
			_pending_checksums[tick] = {}
		_pending_checksums[tick][peer] = checksum


func _compare_checksum(peer: int, expected: int, actual: int) -> void:
	if expected != actual and _ready_peers.has(peer):
		reject_runtime.rpc_id(peer, "Arcade lost sync; close and reopen to replay")
		_ready_peers.erase(peer)
		if peer == int(state["owner"]):
			_release_control()


func _frame_ready(tick: int, checksum: int, pixels: PackedByteArray, pcm: PackedByteArray) -> void:
	local_tick = tick
	var frame := Image.create_from_data(320, 200, false, Image.FORMAT_RGBA8, pixels)
	if _texture == null:
		_texture = ImageTexture.create_from_image(frame)
		_view.set_screen(_texture)
	else:
		_texture.update(frame)
	if tick % CHECKPOINT_INTERVAL == 0:
		report_checksum.rpc_id(1, _epoch, tick, checksum)
	if int(state["tick"]) - tick > 10:
		return
	if not _audio.playing:
		_audio.play()
		_playback = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	var audio_frames := PackedVector2Array()
	for index: int in range(0, pcm.size() - 3, 4):
		audio_frames.append(Vector2(pcm.decode_s16(index), pcm.decode_s16(index + 2)) / 32768.0)
	if _playback != null and _playback.get_frames_available() >= audio_frames.size():
		_playback.push_buffer(audio_frames)


func _restart_local() -> void:
	_epoch = int(state["epoch"])
	local_tick = 0
	local_error = ""
	_waiting = false
	_audio.stop()
	_emulator.start(game_id)
	if multiplayer.is_server():
		state = state.duplicate()
		state.erase("error")


func retry_local() -> void:
	_restart_local()


func _release_control() -> void:
	state = state.duplicate()
	state["owner"] = 0
	state["operator"] = ""
	session.release_buttons()


func _sender() -> int:
	var remote := multiplayer.get_remote_sender_id()
	return remote if remote != 0 else multiplayer.get_unique_id()


func _player_for_peer(peer: int) -> Player:
	for player: Player in get_tree().get_nodes_in_group(&"players"):
		if player.get_multiplayer_authority() == peer:
			return player
	return null


func _peer_left(peer: int) -> void:
	_ready_peers.erase(peer)
	_last_request.erase(peer)
	for waiting: Dictionary in _pending_checksums.values():
		waiting.erase(peer)
	if multiplayer.is_server():
		if peer == int(state["owner"]):
			_release_control()
		_save_progress()


func _mode_changed(_mode: Network.Mode) -> void:
	# Network has already switched role here; only the previous authority has a store.
	if _progress != null:
		_save_progress()
	_progress = null
	_saved_tick = -1
	_save_blocked = false
	_save_in = SAVE_SECONDS
	_view.close(false)
	_emulator.stop()
	_audio.stop()
	_epoch = 0
	state = {"epoch": 1, "tick": 0, "owner": 0, "operator": "", "running": false, "finished": false}
	session = ScummArcadeSession.new()
	_ready_peers.clear()
	_last_request.clear()
	_checksums.clear()
	_pending_checksums.clear()
	_elapsed = 0.0


func _has_audience() -> bool:
	if Network.mode != Network.Mode.SERVER:
		return true
	for peer: int in _ready_peers:
		if peer != 1:
			return true
	return false


func _ensure_progress() -> void:
	if _progress != null or Network.has_flag("scumm-no-save"):
		return
	if Network.mode not in [Network.Mode.SERVER, Network.Mode.OFFLINE]:
		return
	var slot := "server-" + str(Network.args.get("port", "7777"))
	if Network.mode == Network.Mode.OFFLINE:
		slot = "offline"
	var path: String = Network.args.get("scumm-save-path", "user://scumm_arcade/" + slot + ".sav")
	# The original monkey save path stays compatible; every additional game is isolated.
	if game_id != "monkey":
		path += "." + game_id
	_progress = ScummArcadeProgressStore.new(path)
	var restored := _progress.load_progress(_runtime_id)
	if restored != null:
		session = restored
		_saved_tick = session.tick
		state = state.duplicate()
		state["tick"] = session.tick
		state["finished"] = session.finished()
		state["saved_tick"] = session.tick
		print("ARCADE_RESTORED ", session.tick)
	if not _progress.failure.is_empty():
		state["save_error"] = _progress.failure
		_save_blocked = true


func _save_progress(force: bool = false) -> void:
	if _progress == null or (not force and (_saved_tick == session.tick or _save_blocked)):
		return
	state = state.duplicate()
	if _progress.save_progress(session, _runtime_id):
		_saved_tick = session.tick
		_save_blocked = false
		state["saved_tick"] = session.tick
		state.erase("save_error")
	else:
		state["save_error"] = _progress.failure


func _exit_tree() -> void:
	_save_progress()


func details() -> Dictionary:
	return ScummArcadeCatalog.GAMES[game_id]


func is_interactive() -> bool:
	return bool(details()["interactive"])
