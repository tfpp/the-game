extends Node
## Opt-in real-peer check and native UI capture; never loaded by the feature.

var _observer_ready := false
@onready var _case: VivienneCase = $Game/Features/bar_companion/VivienneCase
@onready var _npc: Vivienne = $Game/Features/bar_companion/Vivienne
@onready var _wallet: PlayerMoney = $Game/Features/money


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	_run.call_deferred()


func _run() -> void:
	var role := str(Network.args.get("case-role", "server"))
	if role == "server":
		# Existing Celeste/busboy workaround for unrelated freed remote-hand HUD.
		$Game/Features/weapon_hotbar.set_process(false)
		return
	var player: Player
	while player == null:
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	if role == "driver":
		await _drive(player)
	elif role == "capture":
		await _capture(player)
	else:
		await _observe(player)


func _drive(player: Player) -> void:
	var peer := multiplayer.get_unique_id()
	var talk := _npc.get_node("NetworkedEntity") as NetworkedInteraction
	await _move(player, Vector3(0, 0, 8))
	talk.request_action(&"case", {"step": 0})
	await get_tree().create_timer(0.3).timeout
	assert(_case.stage(peer) == 0, "server range check")
	await _move(player, _npc.global_position + Vector3(0, 0, 0.9))
	talk.request_action(&"case", {"step": 0, "peer": 1})
	await get_tree().create_timer(0.3).timeout
	assert(_case.stage(peer) == 0, "schema rejects supplied identity")
	while not _wallet.balances.has(peer):
		await get_tree().process_frame
	var before := int(_wallet.balances[peer])
	talk.request_action(&"case", {"step": 0})
	await _wait_stage(peer, 1)
	await _evidence(player, 0, 2)
	print("CASE_LATE_READY")
	while not _observer_ready:
		await get_tree().process_frame
	await _evidence(player, 1, 3)
	await _move(player, _npc.global_position + Vector3(0, 0, 0.9))
	talk.request_action(&"case", {"step": 3})
	await _wait_stage(peer, 4)
	await _evidence(player, 2, 5)
	await _evidence(player, 3, 6)
	await _evidence(player, 4, 7)
	await _evidence(player, 3, 8)
	await _evidence(player, 0, 9)
	await _move(player, _npc.global_position + Vector3(0, 0, 0.9))
	talk.request_action(&"case", {"step": 9})
	await _wait_stage(peer, 10)
	await get_tree().create_timer(0.3).timeout
	assert(int(_wallet.balances[peer]) == before + 10000, "real replicated $100 fee")
	talk.request_action(&"case", {"step": 9})
	await get_tree().create_timer(0.3).timeout
	assert(int(_wallet.balances[peer]) == before + 10000, "no replay payout")
	print("CASE_DRIVER_PASS")
	get_tree().quit()


func _observe(player: Player) -> void:
	await get_tree().create_timer(0.7).timeout
	var peer := multiplayer.get_unique_id()
	var owners := _case.progress.keys()
	assert(owners.size() == 1, "late snapshot contains driver's case")
	var owner := int(owners[0])
	assert(_case.stage(owner) == 2)
	assert(_case.stage(peer) == 0, "independent case for newcomer")
	var menu := _npc.get_node("CaseMenu") as CanvasLayer
	assert(not menu._root.visible, "private dialogue is not replayed")
	await _move(player, _npc.global_position + Vector3(0, 0, 0.9))
	var talk := _npc.get_node("NetworkedEntity") as NetworkedInteraction
	talk.request_action(&"case", {"step": 0, "peer": owner})
	await get_tree().create_timer(0.3).timeout
	assert(_case.stage(owner) == 2)
	assert(_case.stage(peer) == 0)
	talk.request_action(&"case", {"step": 0})
	await _wait_stage(peer, 1)
	assert(_case.stage(owner) == 2, "two players share NPC but not evidence progress")
	print("CASE_LATE_JOIN_PASS")
	_observer_checked.rpc_id(owner)
	while _case.progress.has(owner):
		await get_tree().process_frame
	assert(_case.stage(peer) == 1, "disconnect clears only departing player")
	print("CASE_DISCONNECT_PASS")
	get_tree().quit()


@rpc("any_peer", "call_local", "reliable")
func _observer_checked() -> void:
	_observer_ready = true


func _move(player: Player, spot: Vector3) -> void:
	player.global_position = spot
	player.net_position = spot
	await get_tree().create_timer(0.5).timeout


func _evidence(player: Player, index: int, next: int) -> void:
	var point := _case.get_node("Evidence%d" % index) as Node3D
	await _move(player, point.global_position + Vector3(0, -0.9, 0.8))
	point.use()
	await _wait_stage(multiplayer.get_unique_id(), next)


func _wait_stage(peer: int, step: int) -> void:
	while _case.stage(peer) != step:
		await get_tree().process_frame


func _capture(player: Player) -> void:
	if get_window().size.x < 600:
		var retro := $Game/Features/retro_style as RetroStyle
		retro.mobile = true
		retro._configure_viewport()
		Controls.touch_available = true
		Controls.select_device(Controls.Device.TOUCH)
	for menu: Node in get_tree().get_nodes_in_group(&"modal_ui"):
		menu.queue_free()
	await _move(player, _npc.global_position + Vector3(0, 0, 1.4))
	Controls.start()
	var camera := player.get_node("Camera") as Camera3D
	camera.make_current()
	var view := str(Network.args.get("case-view", "dialogue"))
	if view == "phone":
		var phone := _case.get_node("Evidence3") as Node3D
		camera = Camera3D.new()
		add_child(camera)
		camera.global_position = phone.global_position + Vector3(-1.1, 0.9, 1.3)
		camera.look_at(phone.global_position + Vector3.UP * 0.1)
		camera.make_current()
		_case.progress = {1: 5}
	elif view == "document":
		var envelope := _case.get_node("Evidence4") as Node3D
		camera = Camera3D.new()
		add_child(camera)
		camera.global_position = envelope.global_position + Vector3(0, 0.7, 1)
		camera.look_at(envelope.global_position)
		camera.make_current()
		_case.progress = {1: 6}
	else:
		_npc.use()
		(_npc.get_node("CaseMenu") as CanvasLayer)._choose("0")
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/vivienne-case-%s.png" % view)
	print("CASE_CAPTURE_PASS")
	get_tree().quit()
