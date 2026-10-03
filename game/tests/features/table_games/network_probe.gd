extends Game
## Minimal real-transport fixture: actual Player spawner, wallet and all five tables.
const ORDER: Array[String] = ["Poker", "Blackjack", "Baccarat", "Craps", "VideoPoker"]
var _role := ""
var _late_seen := false
var _denied := 0
var _quiesced := false
var _video_seen := false
var _driven_table: CrownGameTable
var _driven_seat := -1
@onready var suites: Node3D = $Features/table_games
@onready var wallet: PlayerMoney = $Features/money


func _ready() -> void:
	_spawner.spawn_function = _spawn_player
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.mode_changed.connect(_on_mode_changed)
	Network.start_from_environment()
	_role = str(Network.args.get("table-role", "server"))
	for id: String in ORDER:
		var table := suites.get_node("Room/" + id) as CrownGameTable
		table.betting_seconds = 4
		table.turn_seconds = 2
		table.entity.request_finished.connect(
			func(_action: StringName, result: NetworkedEntity.Result) -> void:
				if result == NetworkedEntity.Result.DENIED:
					_denied += 1
		)
	if _role == "a" or _role == "b":
		_drive.call_deferred()
	if _role == "server":
		print("TABLE_SERVER_READY")


func _spawn_player(data: Variant) -> Node:
	var player := super._spawn_player(data) as Player
	player.set_physics_process(false)
	return player


func _process(_delta: float) -> void:
	if is_instance_valid(_driven_table):
		var local := get_tree().get_first_node_in_group(&"local_player") as Player
		if local != null:
			# Behave like the normal movement loop: continuously publish the pose,
			# including after the spawner's initial state has arrived.
			local.set_physics_process(false)
			var seating := _driven_table.get_node("Seats") as CrownTableSeating
			var occupied := seating.seat_of(multiplayer.get_unique_id())
			local.global_position = (
				seating.sit_position(occupied)
				if occupied >= 0
				else (
					seating.seats[_driven_seat].global_position + Vector3.UP * .9144
					if _driven_seat >= 0
					else _driven_table.to_global(Vector3(-.5 if _role == "a" else .5, .9144, 2))
				)
			)
			local.net_position = local.global_position
			local.yaw = (
				seating.sit_yaw(occupied if occupied >= 0 else _driven_seat)
				if occupied >= 0 or _driven_seat >= 0
				else 0
			)
			local.net_yaw = local.yaw
			local.pitch = -.2
			local.net_pitch = -.2
	var video := suites.get_node("Room/VideoPoker") as CrownGameTable
	_video_seen = _video_seen or video.state["phase"] == "result"
	if multiplayer.is_server():
		for id: String in ORDER:
			var table := suites.get_node("Room/" + id) as CrownGameTable
			if (
				id != "VideoPoker"
				and table.state["phase"] == "betting"
				and table.state["players"].size() < 2
			):
				table._clock = maxf(table._clock, 1)
	var stop := str(Network.args.get("probe-stop", ""))
	if FileAccess.file_exists(stop + ".pause") and not _quiesced:
		get_tree().multiplayer_poll = false
		_quiesced = true
		print("TABLE_QUIESCED")
	if FileAccess.file_exists(stop):
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		get_tree().quit()
	if _role == "late" and not _late_seen:
		var poker := suites.get_node("Room/Poker") as CrownGameTable
		if poker.state["players"].size() == 2 and poker.state["phase"] == "playing":
			for entry: Dictionary in poker.state["players"].values():
				if entry.has("cards"):
					_fail("Late spectator received hole cards")
			if not poker.private_hand.is_empty():
				_fail("Late spectator received a private event")
			var seats := poker.get_node("Seats") as CrownTableSeating
			if seats.net_seats.count(0) != 2:
				return
			for peer: int in poker.state["players"]:
				if not seats.is_seated(peer):
					_fail("Late spectator did not receive occupied poker chairs")
			if not poker.state.has("dealer_animation"):
				return
			_late_seen = true
			print("TABLE_LATE_PRIVATE_PASS")


func _drive() -> void:
	var player: Player
	var peer := multiplayer.get_unique_id()
	while player == null or not wallet.balances.has(peer):
		await get_tree().process_frame
		player = get_tree().get_first_node_in_group(&"local_player") as Player
		peer = multiplayer.get_unique_id()
	for id: String in ORDER:
		var table := suites.get_node("Room/" + id) as CrownGameTable
		if id == "VideoPoker" and _role == "b":
			while not _video_seen:
				await get_tree().process_frame
			print("TABLE_RESULT VideoPoker spectator")
			continue
		_driven_table = table
		var seating := table.get_node("Seats") as CrownTableSeating
		_driven_seat = (
			(0 if _role == "a" else 1)
			if seating.seats.size() > 1
			else (0 if not seating.seats.is_empty() else -1)
		)
		player.set_physics_process(false)
		player.global_position = table.to_global(Vector3(-.5 if _role == "a" else .5, .9144, 2))
		player.net_position = player.global_position
		player.net_yaw = 0
		player.net_pitch = -.2
		await get_tree().create_timer(.6).timeout
		if _driven_seat >= 0:
			if id == "Poker" and _role == "b":
				while seating.net_seats[0] == 0:
					await get_tree().process_frame
				seating.entity.request_action(&"sit", {"seat": 0})
				await get_tree().create_timer(.25).timeout
				if seating.net_seats[0] == peer:
					_fail("Occupied chair was stolen over RPC")
			seating.request_sit(_driven_seat)
			while not seating.is_seated(peer):
				await get_tree().create_timer(.3).timeout
				seating.request_sit(_driven_seat)
			print("TABLE_SEAT_JOINED ", id, " ", _role)
		# Identity injection and arbitrary action names must fail through real RPCs.
		table.entity.request_action(&"move", {"move": "check", "hold": 0, "peer": 1})
		if id != "VideoPoker" or _role == "a":
			table.entity.request_use()
			while not table.state["players"].has(peer):
				await get_tree().create_timer(.3).timeout
				table.entity.request_use()
		while table.state["phase"] == "idle":
			await get_tree().process_frame
		if id == "Poker":
			print("TABLE_POKER_JOINED ", _role)
		while table.state["phase"] != "result":
			if table.state["phase"] == "playing":
				if id == "Poker" and table.private_hand.size() != 2:
					await get_tree().process_frame
					continue
				var options := table.moves(peer)
				if not options.is_empty():
					# Pause first poker action to give the late spectator time to join.
					await get_tree().create_timer(.35 if id == "Poker" else .2).timeout
					var move := (
						"check"
						if id == "Poker"
						else (
							"stand"
							if id == "Blackjack"
							else ("draw" if id == "VideoPoker" else "roll")
						)
					)
					table.entity.request_action(&"move", {"move": move, "hold": 0})
					await get_tree().create_timer(.2).timeout
			await get_tree().process_frame
		print("TABLE_RESULT ", id, " ", JSON.stringify(table.state))
		if id == "Poker":
			var sum := 0
			for entry: Dictionary in table.state["players"].values():
				sum += int(entry["payout"]) - int(entry["stake"])
			if sum != 0:
				_fail("Poker pot does not conserve chips")
		if seating.is_seated(peer):
			seating.request_stand()
			while seating.is_seated(peer):
				await get_tree().process_frame
		_driven_seat = -1
		await get_tree().create_timer(.3).timeout
	if _denied == 0:
		_fail("Forged requests were not rejected")
	print("TABLE_DRIVER_PASS ", _role)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
