extends Node
## Real WebSocket peers and actual Compatibility-renderer review of the main casino.

const RealTime := preload("res://tests/fixtures/real_time.gd")
@onready var club: VipLounge = $Game/Features/vip_lounge


func _ready() -> void:
	$Game/Features/character_memory.queue_free()
	# Dedicated servers have no hotbar presentation; the existing HUD retains a
	# remote Hand after disconnect on this base snapshot.
	if Network.mode == Network.Mode.SERVER:
		$Game/Features/weapon_hotbar.set_process(false)
	$Game/Features/money._starting_cents = 200_000
	_run.call_deferred()


func _run() -> void:
	var role := str(Network.args.get("vip-role", "server"))
	if role == "server":
		return
	assert(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return get_tree().get_first_node_in_group(&"local_player") != null,
			10.0
		)
	)
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	player.set_physics_process(false)
	if role == "capture":
		await _capture(player)
	elif role == "driver":
		await _driver(player)
	else:
		await _observer(player)
	get_tree().quit()


func _place(player: Player, at: Vector3) -> void:
	player.global_position = at
	player.net_position = at
	player.reset_physics_interpolation()


func _driver(player: Player) -> void:
	assert(Network.mode == Network.Mode.CLIENT, "Driver must be a connected client")
	var peer := multiplayer.get_unique_id()
	assert(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool: return int(club.wallet().balances.get(peer, 0)) >= VipRules.ENTRY_CENTS,
			10.0
		)
	)
	var entrance := club.get_node("Entrance") as VipDoor
	_place(player, Vector3(0, 1, 16))
	await RealTime.wait(get_tree(), 0.7)
	entrance.use()
	await RealTime.wait(get_tree(), 0.3)
	assert(not club.admitted(peer), "Out-of-range entrance rejected")
	_place(player, Vector3(22, 1, -15))
	await RealTime.wait(get_tree(), 0.7)
	entrance.entity.request_action(&"use", {"peer": 1})
	await RealTime.wait(get_tree(), 0.3)
	assert(not club.admitted(peer), "Forged entrance payload rejected")
	entrance.use()
	assert(await RealTime.wait_until(get_tree(), func() -> bool: return club.admitted(peer), 5.0))
	assert(VipLounge.BOUNDS.has_point(player.net_position), "Owner receives upstairs teleport")
	var jade := club.get_node("Jade") as VipStation
	_place(player, jade.global_position + Vector3(-1.6, 0.95, 0))
	await RealTime.wait(get_tree(), 0.7)
	jade.entity.request_action(&"service", {"action": "luck", "options": {}})
	assert(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				var hand := Hand.for_peer(get_tree(), peer)
				return hand != null and hand.net_item_id == "luck_cocktail",
			5.0
		)
	)
	assert(int(club.profile(peer).get("luck", 0)) == 0, "Ordering only hands over an item")
	var hand := Hand.for_peer(get_tree(), peer)
	hand.request_primary_action.rpc_id(1)
	assert(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return int(club.profile(peer).get("luck", 0)) > 0, 5.0
		)
	)
	assert(int(club.profile(peer)["luck"]) <= 300)
	assert(hand.net_item_id.is_empty(), "Finished cocktail is consumed")
	jade.entity.request_action(&"service", {"action": "golden", "options": {}})
	assert(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return hand.net_item_id == "golden_hour", 5.0
		)
	)
	jade.entity.request_action(&"service", {"action": "luck", "options": {"peer": 1}})
	print("VIP_READY")
	assert(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return multiplayer.get_peers().size() >= 2, 20.0
		)
	)
	await RealTime.wait(get_tree(), 4.0)
	assert(club.admitted(peer), "Arrival grace expires without ejecting the guest")
	assert(int(club.profile(peer)["luck_ready"]) > 1700)
	var exit := club.get_node("Exit") as VipDoor
	_place(player, exit.global_position + Vector3(-1, 0, 0))
	await RealTime.wait(get_tree(), 0.7)
	exit.use()
	assert(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					player.net_position.distance_to(
						(club.get_node("DownstairsArrival") as Node3D).global_position
					)
					< 0.1
				),
			5.0
		)
	)
	hand.request_drop_item.rpc_id(1)
	assert(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return hand.net_item_id.is_empty(), 5.0
		)
	)
	await RealTime.wait(get_tree(), 0.7)
	print("VIP_DRIVER_PASS")


func _observer(player: Player) -> void:
	assert(Network.mode == Network.Mode.CLIENT, "Observer must be a connected client")
	var peer := multiplayer.get_unique_id()
	assert(
		await RealTime.wait_until(get_tree(), func() -> bool: return club.profiles.size() == 1, 5.0)
	)
	var guests: Array = club.profiles.keys()
	assert(guests.size() == 1, "Late join receives the existing guest profile")
	var driver := int(guests[0])
	assert(driver != peer)
	assert(club.profile(driver)["inside"])
	assert(int(club.profile(driver)["luck"]) > 0, "Late join receives active boost")
	var hand := Hand.for_peer(get_tree(), driver)
	assert(hand != null and hand.net_item_id == "golden_hour", "Late join receives held drink")
	assert(hand.held_view() != null, "Remote drink has its model")
	hand.request_primary_action.rpc_id(1)
	await RealTime.wait(get_tree(), 0.3)
	assert(not hand.consumption.active(), "Foreign peer cannot drink another guest's item")
	assert(not club.get_node("Menu").is_in_group(&"modal_ui"), "Private menus are not replayed")
	var jade := club.get_node("Jade") as VipStation
	_place(player, jade.global_position + Vector3(-1, 0.95, 0))
	assert(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					player.net_position.distance_to(
						(club.get_node("DownstairsArrival") as Node3D).global_position
					)
					< 0.1
				),
			5.0
		)
	)
	assert(club.get_node("Menu").toast.text == "naughty naughty, ya stinky poor")
	assert(not club.admitted(peer), "Noclip cannot grant admission")
	print("VIP_NOCLIP_EJECTION_PASS")
	jade.entity.request_action(&"service", {"action": "luck", "options": {}})
	await RealTime.wait(get_tree(), 0.7)
	assert(club.profile(peer).is_empty(), "An unadmitted peer cannot use the lounge")
	print("VIP_LATE_JOIN_PASS")
	var thrown := $Game/Features/holdables/Thrown
	assert(
		await RealTime.wait_until(
			get_tree(),
			func() -> bool:
				return (
					thrown.get_child_count() == 1 and (thrown.get_child(0) as ThrownItem).net_landed
				),
			10.0
		)
	)
	var gift := thrown.get_child(0) as ThrownItem
	assert(gift.item_id == "golden_hour", "Dropped drink retains its identity")
	_place(player, gift.global_position + Vector3.UP * 0.95)
	await RealTime.wait(get_tree(), 0.7)
	gift.use()
	var own_hand := Hand.for_peer(get_tree(), peer)
	assert(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return own_hand.net_item_id == "golden_hour", 5.0
		)
	)
	own_hand.request_primary_action.rpc_id(1)
	assert(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return int(club.profile(peer).get("golden", 0)) > 0, 5.0
		)
	)
	assert(own_hand.net_item_id.is_empty(), "Shared drink is consumed once by its new owner")
	assert(not club.admitted(peer), "A gift does not grant lounge admission")
	print("VIP_SHARED_DRINK_PASS")
	assert(
		await RealTime.wait_until(
			get_tree(), func() -> bool: return club.profile(driver).is_empty(), 10.0
		)
	)
	print("VIP_DISCONNECT_PASS")


func _capture(player: Player) -> void:
	print("VIP_CAPTURE_START")
	$Game/LoginScreen.set_process(false)
	$Game/LoginScreen._on_play_prompt_pressed()
	Controls.select_device(Controls.Device.GAMEPAD)
	await RealTime.wait(get_tree(), 1.0)
	var camera := Camera3D.new()
	add_child(camera)
	camera.make_current()
	for canvas: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(canvas as CanvasLayer).visible = false
	await _view(camera, Vector3(29.5, 6.6, -9), Vector3(27, 6.2, 4), "/tmp/vip-lounge.png")
	await _view(camera, Vector3(28, 6.65, -2), Vector3(-8, 0, 0), "/tmp/vip-view.png")
	await _view(camera, Vector3(0, 1, 1), Vector3(24, 6.8, 0), "/tmp/vip-mirror-outside.png")
	await _view(camera, Vector3(-13, 3.5, 13), Vector3(11, 3, 0), "/tmp/vip-floor-clear.png")
	await _view(camera, Vector3(27.6, 6.6, 3), Vector3(31, 6.2, 0), "/tmp/vip-jade.png")
	var space := player.get_world_3d().direct_space_state
	var old_deck := PhysicsRayQueryParameters3D.create(Vector3(18, 6, -8), Vector3(18, 4.8, -8), 1)
	assert(space.intersect_ray(old_deck).is_empty(), "No VIP deck covers the casino floor")
	var new_deck := PhysicsRayQueryParameters3D.create(
		Vector3(29, 6, -11), Vector3(29, 4.8, -11), 1
	)
	assert(
		is_equal_approx(space.intersect_ray(new_deck)["position"].y, 5.0), "Recess has a solid deck"
	)
	await _check_mirror(camera)
	club.get_node("Menu").visible = true
	var money := $Game/Features/money as PlayerMoney
	money.balances = {1: 200_000}
	_place(player, Vector3(29, 5.95, 0))
	club._admitted[1] = true
	club.record(1)["discovered"] = true
	club._publish()
	var jade := club.get_node("Jade") as VipStation
	club.talk(1, "Jade", jade.entity)
	await RealTime.wait(get_tree(), 0.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/vip-menu.png")
	club.leave(1)
	_place(player, Vector3(29, 5.95, 0))
	club._process(0)
	assert(club.get_node("Menu").toast.text == "naughty naughty, ya stinky poor")
	await RealTime.wait(get_tree(), 0.9)
	await _view(camera, Vector3(21.5, 1.8, -14), Vector3(10, 1, -2), "/tmp/vip-ejected.png")
	print("VIP_CAPTURE_PASS")


func _check_mirror(camera: Camera3D) -> void:
	var marker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	var finish := StandardMaterial3D.new()
	finish.albedo_color = Color.MAGENTA
	finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = finish
	marker.mesh = box
	add_child(marker)
	marker.global_position = Vector3(26, 6.8, 0)
	await _view(camera, Vector3(10, 6.8, 0), marker.global_position, "/tmp/vip-privacy-outside.png")
	assert(not _center_is_magenta(), "Casino-side mirror hides a guest behind it")
	marker.global_position = Vector3(22, 6.8, 0)
	await _view(camera, Vector3(28, 6.8, 0), marker.global_position, "/tmp/vip-privacy-inside.png")
	assert(_center_is_magenta(), "VIP-side pane allows a clear view of the floor")
	marker.queue_free()
	print("VIP_MIRROR_PRIVACY_PASS")


func _center_is_magenta() -> bool:
	var picture := get_viewport().get_texture().get_image()
	var color := picture.get_pixel(picture.get_width() / 2, picture.get_height() / 2)
	return color.r > 0.7 and color.b > 0.7 and color.g < 0.3


func _view(camera: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	print("VIP_CAPTURE_VIEW ", path)
	camera.global_position = eye
	camera.look_at(target)
	await RealTime.wait(get_tree(), 0.4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
