extends Node
## Full-game real server/client check plus an optional rendered offline view.

@onready var _desk: Node3D = $Game/Features/irs_desk
@onready var _wallet: PlayerMoney = $Game/Features/money


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_run.call_deferred()


func _run() -> void:
	var role := str(Network.args.get("irs-role", "server"))
	if role == "server":
		$Game/Features/weapon_hotbar.set_process(false)
		return
	var player: Player
	while player == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	if role == "capture":
		await _capture(player)
		return
	var entity := _desk.get_node("NetworkedEntity") as NetworkedInteraction
	var form: CanvasLayer = _desk.get_node("TaxForm")
	var peer := multiplayer.get_unique_id()
	while not _wallet.balances.has(peer):
		await get_tree().create_timer(0.1).timeout
	if role == "driver":
		player.global_position = Vector3(0, 1, 16)
		player.net_position = player.global_position
		await get_tree().create_timer(0.7).timeout
		_desk.use()
		await get_tree().create_timer(0.3).timeout
		assert(not form._root.visible, "Server rejects out-of-range Use")
		player.global_position = _desk.global_position + Vector3(0, 0.9, -1.2)
		player.net_position = player.global_position
		await get_tree().create_timer(0.7).timeout
		_desk.use()
		await get_tree().create_timer(0.3).timeout
		assert(form._root.visible, "Validated private form arrives")
		form._winnings.text = "123.45"
		form._tax.text = "1.35"
		var payload := {"token": form._token, "winnings": 12345, "tax": 135}
		form._pay()
		entity.request_action(&"file", payload)
		await get_tree().create_timer(0.5).timeout
		assert(int(_wallet.balances[peer]) == 1865, "Exact debit once after replay")
		assert(form._status.text.contains("Tax paid: $1.35"))
		print("IRS_PAID")
		await get_tree().create_timer(18.0).timeout
		assert(int(_wallet.balances[peer]) == 1865, "Other players cannot charge this wallet")
		print("IRS_DRIVER_PASS")
		get_tree().quit()
	else:
		await get_tree().create_timer(0.8).timeout
		assert(not form._root.visible, "Late joins receive no other player's form")
		var driver := 0
		for id: int in _wallet.balances:
			if id != peer and int(_wallet.balances[id]) == 1865:
				driver = id
		assert(driver != 0, "Late join receives already-debited wallet")
		player.global_position = _desk.global_position + Vector3(0.8, 0.9, -1.2)
		player.net_position = player.global_position
		await get_tree().create_timer(0.7).timeout
		entity.request_action(&"file", {"token": "forged", "winnings": 100, "tax": 100})
		await get_tree().create_timer(0.3).timeout
		assert(int(_wallet.balances[driver]) == 1865)
		_desk.use()
		await get_tree().create_timer(0.3).timeout
		form._winnings.text = "10"
		form._tax.text = "1"
		form._pay()
		await get_tree().create_timer(0.5).timeout
		assert(int(_wallet.balances[peer]) == 1900)
		assert(int(_wallet.balances[driver]) == 1865)
		print("IRS_OBSERVER_PASS")
		get_tree().quit()


func _capture(player: Player) -> void:
	player.global_position = _desk.global_position + Vector3(0, 0.9, -1.2)
	player.net_position = player.global_position
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = _desk.global_position + Vector3(1.5, 1.8, -2.5)
	camera.look_at(_desk.global_position + Vector3(0, 0.5, 0))
	camera.make_current()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/irs-desk.png")
	_desk.use()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/irs-form.png")
	get_window().size = Vector2i(390, 844)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/irs-phone.png")
	print("IRS_CAPTURE_PASS")
	get_tree().quit()
