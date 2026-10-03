extends SceneTree
var _pids: Dictionary = {}
var _logs := ""
var _port := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_logs = "/tmp/crown-net-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(_logs)
	var listener := TCPServer.new()
	assert(listener.listen(0, "127.0.0.1") == OK)
	_port = listener.get_local_port()
	listener.stop()
	_spawn("server", ["--server", "--port=%d" % _port])
	var ok := await _wait("server", "TABLE_SERVER_READY")
	if ok:
		_spawn("a", ["--connect=ws://127.0.0.1:%d" % _port])
		_spawn("b", ["--connect=ws://127.0.0.1:%d" % _port])
		ok = await _wait("a", "TABLE_POKER_JOINED") and await _wait("b", "TABLE_POKER_JOINED")
	if ok:
		_spawn("late", ["--connect=ws://127.0.0.1:%d" % _port])
		ok = await _wait("late", "TABLE_LATE_PRIVATE_PASS")
	if ok:
		ok = await _wait("a", "TABLE_DRIVER_PASS") and await _wait("b", "TABLE_DRIVER_PASS")
	_touch(_logs + "/stop.pause")
	for role: String in _pids:
		if not await _wait(role, "TABLE_QUIESCED"):
			ok = false
	_touch(_logs + "/stop")
	for i: int in 10:
		await create_timer(.1).timeout
	for role: String in _pids:
		if OS.is_process_running(int(_pids[role])):
			OS.kill(int(_pids[role]))
		var log := _read(role)
		if "ERROR:" in log or not ok:
			printerr(role, ":\n", log)
			ok = false
	print("CROWN_MULTIPLAYER: ", "PASS" if ok else "FAIL", " logs=", _logs)
	quit(0 if ok else 1)


func _spawn(role: String, options: Array[String]) -> void:
	var args := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--log-file",
			_logs + "/" + role + ".log",
			"res://tests/features/table_games/network_probe.tscn",
			"--",
			"--dev-insecure-auth",
			"--name=" + role,
			"--table-role=" + role,
			"--probe-stop=" + _logs + "/stop"
		]
	)
	args.append_array(options)
	_pids[role] = OS.create_process(OS.get_executable_path(), args)


func _read(role: String) -> String:
	var path := _logs + "/" + role + ".log"
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _wait(role: String, marker: String) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		for peer: String in _pids:
			if "ERROR:" in _read(peer):
				return false
		if marker in _read(role):
			return true
		await create_timer(.1).timeout
	return false


func _touch(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("stop")
	file.close()
