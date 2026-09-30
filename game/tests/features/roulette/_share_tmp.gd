extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	$Game/Features/character_memory.queue_free()
	await get_tree().create_timer(0.5).timeout
	Controls.select_device(Controls.Device.TOUCH)
	$Game/LoginScreen._resume()
	var table := $Game/Features/roulette/Table as RouletteTable
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	player.global_position = table.to_global(Vector3(0.6, 0.9144, -2.4))
	player.net_position = player.global_position
	player.yaw = table.seat_yaw()
	player.net_yaw = player.yaw
	player.pitch = -0.3
	player.net_pitch = player.pitch
	await get_tree().create_timer(0.3).timeout
	table.use()
	await get_tree().create_timer(0.5).timeout
	table.set_process(false)
	var state := table.state.duplicate(true)
	state["seats"] = [1, 98, 99]
	state["names"] = ["You", "Bob", "Cara"]
	state["bets"] = {
		1: [["17", 500], ["17", 100], ["red", 500], ["22-23-24", 100]],
		98: [["17", 5000], ["17", 500], ["22-23-24", 500]],
		99: [["17", 100], ["17", 100], ["17", 10000], ["dozen2", 500]],
	}
	table.state = state
	var view := table.get_node("View") as RouletteTableView
	view.open_betting()
	await get_tree().create_timer(1.5).timeout
	view.screen._hover("17")
	view.screen._preview.visible = false
	view.screen.set_process(false)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/roulette/shared.png")
	get_tree().quit()
