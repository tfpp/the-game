extends Node
## Manual visual check, never loaded by the game or GUT: joins the real table in the
## main level, places chips and runs a round, saving screenshots to /tmp/roulette.
## Run: godot --path game res://tests/features/roulette/visual_probe.tscn

var _player: Player


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	$Game/Features/character_memory.queue_free()
	var cycle := $Game/Features/day_night as DayNight
	cycle.set_process(false)
	cycle._apply(0.5)
	await get_tree().create_timer(0.5).timeout
	_player = get_tree().get_first_node_in_group(&"local_player") as Player
	Controls.select_device(Controls.Device.TOUCH)
	$Game/LoginScreen._resume()
	var table := $Game/Features/roulette/Table as RouletteTable
	_view(table.to_global(Vector3(0.6, 1.63, -2.6)), table.to_global(Vector3(0.2, 0.9, 0.3)))
	await _capture("/tmp/roulette/approach.png")
	table.use()
	await get_tree().create_timer(0.5).timeout
	assert(table.seat_of(1) == 0, "seated")
	var wallet := $Game/Features/money as PlayerMoney
	wallet._set_balance(1, 3000000)
	for bet: Array in [
		["17", 500],
		["17", 100],
		["red", 5000],
		["dozen2", 10000],
		["0-37", 100],
		["13-14-16-17", 500],
		["column3", 50000],
		["22-23-24", 100],
		["odd", 2500000]
	]:
		table.request_bet(bet[0], bet[1])
	await get_tree().create_timer(0.3).timeout
	var view := table.get_node("View") as RouletteTableView
	_player.pitch = -0.35
	await _capture("/tmp/roulette/seated.png")
	view.open_betting()
	var screen := view.screen
	screen._hover("17")
	await _capture("/tmp/roulette/overview.png")
	table._elapsed = RouletteTable.BETTING_S - 0.1
	await get_tree().create_timer(1.0).timeout
	await _capture("/tmp/roulette/spinning.png")
	await get_tree().create_timer(2.5).timeout
	await _capture("/tmp/roulette/result.png")
	await get_tree().create_timer(RouletteTable.RESULT_S).timeout
	assert(table.seat_of(1) == -1, "released")
	await _capture("/tmp/roulette/released.png")
	screen._continue()
	_view(table.to_global(Vector3(1.8, 2.0, -2.8)), table.to_global(Vector3(0, 0.9, 0.6)))
	await _capture("/tmp/roulette/dealer.png")
	print("ROULETTE_PROBE PASS")
	get_tree().quit()


func _view(eye: Vector3, target: Vector3) -> void:
	var offset := _player.movement.eye_height_m() - _player.movement.hull_height_m() * 0.5
	_player.global_position = eye - Vector3(0, offset, 0)
	_player.net_position = _player.global_position
	var direction := (target - eye).normalized()
	_player.yaw = atan2(-direction.x, -direction.z)
	_player.pitch = asin(direction.y)
	_player.net_yaw = _player.yaw
	_player.net_pitch = _player.pitch
	_player.reset_physics_interpolation()


func _capture(path: String) -> void:
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
