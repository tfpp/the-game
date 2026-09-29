extends SceneTree
## Real engine processes for smoke, hotel and shared-door multiplayer checks.
## Run: godot --headless --path game -s scripts/network_checks.gd -- smoke|hotel|doors

var _processes: Dictionary[String, int] = {}
var _logs := ""
var _port := 0
var _scenario := "smoke"
var _stop := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_scenario = args[0]
	if _scenario not in ["smoke", "hotel", "doors"]:
		printerr("Usage: network_checks.gd -- smoke|hotel|doors")
		quit(1)
		return
	_logs = ProjectSettings.globalize_path(
		"user://network-checks/%s-%d-%d" % [_scenario, OS.get_process_id(), Time.get_ticks_msec()]
	)
	DirAccess.make_dir_recursive_absolute(_logs)
	_stop = _logs.path_join("stop")
	var listener := TCPServer.new()
	if listener.listen(0, "127.0.0.1") != OK:
		quit(1)
		return
	_port = listener.get_local_port()
	listener.stop()
	var ok := false
	match _scenario:
		"smoke":
			ok = await _smoke()
		"hotel":
			ok = await _hotel()
		"doors":
			ok = await _doors()
	for pid: int in _processes.values():
		if OS.is_process_running(pid):
			OS.kill(pid)
	if ok:
		ok = _healthy(true)
	if not ok:
		for name: String in _processes:
			printerr("\n%s:\n%s" % [name, _read(name)])
	print("%s: %s (logs: %s)" % [_scenario, "PASS" if ok else "FAIL", _logs])
	quit(0 if ok else 1)


func _spawn(name: String, options: Array[String]) -> void:
	var args := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--log-file",
			_logs.path_join(name + ".log")
		]
	)
	if _scenario == "hotel":
		args.append("res://tests/features/hotel_annex/probe.tscn")
	elif _scenario == "doors":
		args.append("res://tests/features/room_doors/network_probe.tscn")
	args.append("--")
	if _scenario == "hotel":
		args.append_array(["--dev-insecure-auth", "--hotel-role=" + name])
	elif _scenario == "doors":
		args.append_array(
			[
				"--dev-insecure-auth",
				"--door-role=" + name,
				"--probe-stop=" + _stop,
				"--name=" + name
			]
		)
	args.append_array(options)
	_processes[name] = OS.create_process(OS.get_executable_path(), args)


func _read(name: String) -> String:
	var path := _logs.path_join(name + ".log")
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _healthy(allow_exit: bool = false) -> bool:
	for name: String in _processes:
		if _processes[name] <= 0 or "ERROR:" in _read(name):
			return false
		if not allow_exit and not OS.is_process_running(_processes[name]):
			return false
	return true


func _wait(check: Callable, label: String, allow_exit: bool = false) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		if not _healthy(allow_exit):
			return false
		if check.call():
			return true
		await create_timer(0.05).timeout
	printerr("Timed out: " + label)
	return false


func _marker(name: String, marker: String) -> bool:
	return await _wait(func() -> bool: return marker in _read(name), name + ": " + marker)


func _connection() -> String:
	return "--connect=ws://127.0.0.1:%d" % _port


func _smoke() -> bool:
	_spawn("server", ["--server", "--port=%d" % _port, "--dev-insecure-auth", "--debug-roster"])
	if not await _marker("server", "Server listening on port"):
		return false
	_spawn("c1", [_connection(), "--dev-insecure-auth", "--name=Alice", "--debug-roster"])
	_spawn("c2", [_connection(), "--dev-insecure-auth", "--name=Bob", "--debug-roster"])
	_spawn("intruder", [_connection(), "--ticket=v1.forged.ticket"])
	_spawn("stale", [_connection(), "--dev-insecure-auth", "--build-version=stale"])
	if not await _wait(_smoke_ready, "two players, authentication and version checks"):
		return false
	await create_timer(6).timeout
	return _healthy() and _smoke_ready()


func _smoke_ready() -> bool:
	for name: String in ["server", "c1", "c2"]:
		var last := ""
		for line: String in _read(name).split("\n"):
			if line.begins_with("ROSTER"):
				last = line
		if last.get_slice("players=", 1).split(",", false).size() != 2:
			return false
	return (
		"authenticated as Alice" in _read("server")
		and "authenticated as Bob" in _read("server")
		and "Connection failed: invalid or expired join ticket" in _read("intruder")
		and (
			"Connection failed: This game is version stale but the server runs dev"
			in _read("stale")
		)
	)


func _hotel() -> bool:
	_spawn("server", ["--server", "--port=%d" % _port])
	if not await _marker("server", "Server listening on port"):
		return false
	_spawn("driver", [_connection(), "--name=HotelVisitor"])
	if not await _marker("driver", "HOTEL_ENTERED"):
		return false
	_spawn("observer", [_connection(), "--name=HotelObserver"])
	for marker: String in ["ATRIUM_ROUND_TRIP_PASSED", "REENTRY_PASSED"]:
		if not await _marker("driver", marker):
			return false
	return (
		await _marker("observer", "OBSERVER_UNCHANGED")
		and await _marker("server", "SERVER_UNLOADED")
	)


func _doors() -> bool:
	_spawn("server", ["--server", "--port=%d" % _port])
	if not await _marker("server", "DOORS_SERVER_READY"):
		return false
	_spawn("observer", [_connection()])
	_spawn("driver", [_connection()])
	if (
		not await _marker("driver", "DOORS_DRIVER_PASSED")
		or not await _marker("observer", "DOORS_OBSERVER_PASSED")
	):
		return false
	_spawn("late", [_connection()])
	if not await _marker("late", "DOORS_LATE_JOIN_PASSED"):
		return false
	for name: String in _processes:
		if not await _marker(name, "ENTITY_DESPAWN_OBSERVED"):
			return false
	_touch(_stop + ".pause")
	for name: String in _processes:
		if not await _marker(name, "DOORS_QUIESCED"):
			return false
	_touch(_stop)
	return await _wait(_all_exited, "peer shutdown", true)


func _all_exited() -> bool:
	for pid: int in _processes.values():
		if OS.is_process_running(pid):
			return false
	return true


func _touch(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.close()
