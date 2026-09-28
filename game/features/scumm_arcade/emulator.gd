class_name ScummArcadeEmulator
extends Node
## Runs the same wasm in a browser Worker or a private local Node process.
## Pixels and PCM here are local IPC only; they never pass through multiplayer RPCs.

signal frame_ready(tick: int, checksum: int, pixels: PackedByteArray, pcm: PackedByteArray)

const ROOT := "res://features/scumm_arcade/runtime/"
const DIST := ROOT + "dist/"
const PIXEL_BYTES := 320 * 200 * 4
const MAX_PACKET := PIXEL_BYTES + 8 + 441 * 4 * 10

static var _fingerprints: Dictionary = {}

var status := "stopped"
var failure := ""
var busy := false
var runtime_id := ""
var _web_id := ""
var _web: JavaScriptObject
var _listener: TCPServer
var _stream: StreamPeerTCP
var _packets: PacketPeerStream
var _pid := -1
var _token := ""
var _started_at := 0
var _step_started := 0
var _runtime_directory := ""


func start(game_id: String = "monkey") -> void:
	stop()
	if not FileAccess.file_exists(DIST + "scummvm.wasm"):
		_fail("Arcade runtime is not installed")
		return
	runtime_id = fingerprint(game_id)
	_started_at = Time.get_ticks_msec()
	status = "loading"
	if OS.has_feature("web"):
		JavaScriptBridge.eval(FileAccess.get_file_as_string(ROOT + "browser.js"), true)
		_web_id = "scummArcade_" + str(get_instance_id())
		JavaScriptBridge.eval("globalThis.%s = createScummArcade('%s')" % [_web_id, _web_id], true)
		_web = JavaScriptBridge.get_interface(_web_id)
		_web.start(
			FileAccess.get_file_as_string(DIST + "scummvm.js"),
			FileAccess.get_file_as_string(ROOT + "driver.js"),
			Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(DIST + "scummvm.wasm")),
			game_id,
			(
				""
				if game_id == "monkey"
				else Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(DIST + game_id + ".pak"))
			)
		)
		return
	var directory := ProjectSettings.globalize_path(
		(
			"user://scumm_arcade/"
			+ runtime_id
			+ "-"
			+ str(OS.get_process_id())
			+ "-"
			+ str(get_instance_id())
		)
	)
	_runtime_directory = directory
	DirAccess.make_dir_recursive_absolute(directory)
	for file: String in ["scummvm.js", "scummvm.wasm", "native.cjs", "driver.js"]:
		var source := DIST if file.begins_with("scummvm") else ROOT
		var output := FileAccess.open(directory.path_join(file), FileAccess.WRITE)
		if output == null:
			_fail("Cannot prepare the arcade runtime")
			return
		output.store_buffer(FileAccess.get_file_as_bytes(source + file))
	if game_id != "monkey":
		var output := FileAccess.open(directory.path_join("demo.pak"), FileAccess.WRITE)
		if output == null:
			_fail("Cannot prepare arcade demo data")
			return
		output.store_buffer(FileAccess.get_file_as_bytes(DIST + game_id + ".pak"))
		output.close()
	_listener = TCPServer.new()
	if _listener.listen(0, "127.0.0.1") != OK:
		_fail("Cannot open the local arcade runtime")
		return
	_token = Crypto.new().generate_random_bytes(24).hex_encode()
	var executable: String = Network.args.get("scumm-node", "node")
	_pid = OS.create_process(
		executable,
		[directory.path_join("native.cjs"), str(_listener.get_local_port()), _token, game_id]
	)
	if _pid < 0:
		_fail("Desktop arcade needs Node.js on PATH (or --scumm-node=PATH)")


# gdlint: disable=max-returns
func _process(_delta: float) -> void:
	if status not in ["loading", "ready"]:
		return
	if busy and Time.get_ticks_msec() - _step_started > 30000:
		_fail("Arcade stopped responding; reopen to replay")
		return
	if status == "loading" and Time.get_ticks_msec() - _started_at > 30000:
		_fail("Arcade startup timed out")
		return
	if _web != null:
		status = str(_web.status)
		if status == "failed":
			_fail(str(_web.error))
		elif status == "ready":
			var packet: Variant = JavaScriptBridge.eval(
				"globalThis.scummArcades['%s'].take()" % _web_id, true
			)
			if packet is PackedByteArray:
				_receive(packet)
		return
	if _pid > 0 and not OS.is_process_running(_pid):
		_fail("Arcade runtime exited")
		return
	if _stream == null and _listener != null and _listener.is_connection_available():
		_stream = _listener.take_connection()
		_packets = PacketPeerStream.new()
		_packets.input_buffer_max_size = 1048576
		_packets.output_buffer_max_size = 262144
		_packets.stream_peer = _stream
	if _stream == null:
		return
	_stream.poll()
	if _stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_fail("Local arcade connection closed")
		return
	while _packets.get_available_packet_count() > 0:
		var packet := _packets.get_packet()
		if status == "loading":
			if packet.get_string_from_utf8() != _token:
				_stream.disconnect_from_host()
				_stream = null
				_packets = null
				return
			status = "ready"
			_listener.stop()
		else:
			_receive(packet)


func advance(frames: Array) -> void:
	if status != "ready" or busy or frames.is_empty():
		return
	busy = true
	_step_started = Time.get_ticks_msec()
	var json := JSON.stringify(frames)
	if _web != null:
		_web.send(json)
	elif _packets.put_packet(json.to_utf8_buffer()) != OK:
		_fail("Cannot advance the arcade runtime")


func _receive(packet: PackedByteArray) -> void:
	if packet.size() < 8 + PIXEL_BYTES or packet.size() > MAX_PACKET:
		_fail("Invalid arcade frame")
		return
	busy = false
	frame_ready.emit(
		packet.decode_u32(0),
		packet.decode_u32(4),
		packet.slice(8, 8 + PIXEL_BYTES),
		packet.slice(8 + PIXEL_BYTES)
	)


func stop() -> void:
	if _web != null:
		_web.stop()
		JavaScriptBridge.eval(
			"delete globalThis.scummArcades['%s']; delete globalThis.%s" % [_web_id, _web_id], true
		)
		_web = null
	if _stream != null:
		_stream.disconnect_from_host()
	_stream = null
	_packets = null
	if _listener != null:
		_listener.stop()
	_listener = null
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if not _runtime_directory.is_empty():
		for file: String in ["scummvm.js", "scummvm.wasm", "native.cjs", "driver.js", "demo.pak"]:
			DirAccess.remove_absolute(_runtime_directory.path_join(file))
		DirAccess.remove_absolute(_runtime_directory)
		_runtime_directory = ""
	status = "stopped"
	busy = false


func _fail(message: String) -> void:
	stop()
	failure = message
	status = "failed"


func _exit_tree() -> void:
	stop()


static func fingerprint(game_id: String) -> String:
	if not _fingerprints.has(game_id):
		var engine := FileAccess.get_sha256(DIST + "scummvm.wasm")
		# Preserve existing Monkey Island saves: its interpreter and data are unchanged.
		_fingerprints[game_id] = (
			engine
			if game_id == "monkey"
			else (
				(engine + ":" + game_id + ":" + FileAccess.get_sha256(DIST + game_id + ".pak"))
				. sha256_text()
			)
		)
	return str(_fingerprints[game_id])
