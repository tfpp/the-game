extends Node
## Real room lifecycle, portal, audio and presentation test (native or exported web).

var machines: Array[ScummArcadeCabinet] = []
var player: Player
var frame_times: Array[int] = []
var capture := AudioEffectCapture.new()
var measuring := false
var last_frame := 0
var cabinet: ScummArcadeCabinet


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Network.args["scumm-no-save"] = ""
	var game := get_tree().current_scene
	if game.name != "Game":
		game = game.get_node("Game")
	game.get_node("Features/character_memory").queue_free()
	var room := game.get_node("Features/scumm_arcade") as ScummArcadeRoom
	for node: Node in room.get_children():
		if node is ScummArcadeCabinet:
			machines.append(node as ScummArcadeCabinet)
	cabinet = room.get_node("FateOfAtlantis") as ScummArcadeCabinet
	cabinet._emulator.frame_ready.connect(_frame)
	await get_tree().create_timer(1).timeout
	player = get_tree().get_first_node_in_group(&"local_player") as Player
	assert(player != null)
	player.set_physics_process(false)
	_move(ScummArcadeRoom.ENTRANCE + Vector3(0, 0.95, 2))
	for machine: ScummArcadeCabinet in machines:
		assert(machine._emulator.status == "stopped" and machine._view == null)
	print("ROOM_COLD: zero interpreters or cabinet views outside")
	(room.get_node("Entrance") as RoomDoor).use()
	await get_tree().create_timer(0.4).timeout
	assert(ScummArcadeRoom.contains(player.global_position))
	assert((room.get_node("Interior") as StreamedRoom).is_loaded())
	_move(cabinet.global_position + Vector3(0, 0.9144, 1.95))
	var bus := AudioServer.get_bus_index(GameAudio.BUS)
	AudioServer.add_bus_effect(bus, capture)
	while cabinet.local_tick < 150:
		await get_tree().process_frame
	cabinet.use()
	measuring = true
	capture.clear_buffer()
	await get_tree().create_timer(5).timeout
	measuring = false
	var samples := capture.get_buffer(capture.get_frames_available())
	var power := 0.0
	for sample: Vector2 in samples:
		power += sample.length_squared()
	var rms := sqrt(power / maxf(1, samples.size()))
	print("ROOM_AUDIO_RMS ", rms)
	assert(rms > 0.00001, "Actual running cabinet must reach the audio mixer")
	frame_times.sort()
	var median := frame_times[frame_times.size() / 2]
	print("ROOM_FRAME_MS median=", median, " p95=", frame_times[int(frame_times.size() * 0.95)])
	assert(median < 80, "Presentation must improve on the old 100 ms polling")
	if not OS.has_feature("web"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/scumm-room-play.png")
	else:
		JavaScriptBridge.eval("globalThis.arcadeRoomPlaying = true", true)
		await get_tree().create_timer(2).timeout
	cabinet._view.close(false)
	if not OS.has_feature("web"):
		_move(ScummArcadeRoom.ARRIVAL)
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/scumm-room-wide.png")
	var saved_tick := cabinet.session.tick
	_move(ScummArcadeRoom.ORIGIN + Vector3(0, 0.95, 4))
	(room.get_node("Exit") as RoomDoor).use()
	await get_tree().create_timer(0.5).timeout
	for machine: ScummArcadeCabinet in machines:
		assert(machine._emulator.status == "stopped" and machine._view == null)
	var paused := cabinet.session.tick
	await get_tree().create_timer(0.4).timeout
	assert(cabinet.session.tick == paused and paused >= saved_tick)
	assert(not (room.get_node("Interior") as StreamedRoom).is_loaded())
	print("ROOM_UNLOADED: all interpreters stopped; progress paused")
	(room.get_node("Entrance") as RoomDoor).use()
	await get_tree().create_timer(0.3).timeout
	_move(cabinet.global_position + Vector3(0, 0.9144, 1.95))
	while cabinet.local_tick < paused:
		await get_tree().process_frame
	assert(cabinet.local_error.is_empty())
	print("PASS: room entry, audible live mixer, smooth frames, exit, pause and re-entry")
	AudioServer.remove_bus_effect(bus, AudioServer.get_bus_effect_count(bus) - 1)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("globalThis.arcadeRoomPassed = true", true)
	else:
		get_tree().quit()


func _move(position: Vector3) -> void:
	player.global_position = position
	player.net_position = position
	player.velocity = Vector3.ZERO
	player.yaw = 0
	player.pitch = 0.02
	player.net_yaw = 0
	player.net_pitch = 0.02
	player.reset_physics_interpolation()


func _frame(_tick: int, _checksum: int, _pixels: PackedByteArray, _pcm: PackedByteArray) -> void:
	var now := Time.get_ticks_msec()
	if measuring and last_frame > 0:
		frame_times.append(now - last_frame)
	last_frame = now
