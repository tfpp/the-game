extends Node
## Minimal authenticated peers exercising the production appearance endpoint.

const LOOK := {
	"skin": 6, "hair": "long", "hair_color": 3, "eyes": 2, "outfit": "tactical", "chest": "full"
}
var _role := ""
var _results: Array[int] = []
var _emote_results: Array[int] = []
var _emote_peer := 0
var _emote_started := -1.0
var _emote_finished := false
var _observed := false
var _paused := false
var _authenticated := false
@onready var _models: PlayerModels = $PlayerModels


func _ready() -> void:
	# Explicit probe requests must not race this machine's saved character restore.
	_models.get_node("ModelPicker").set_process(false)
	_models.entity.request_finished.connect(
		func(action: StringName, result: NetworkedEntity.Result) -> void:
			if action == &"emote":
				_emote_results.append(result)
			else:
				_results.append(result)
	)
	_role = str(Network.args.get("avatar-role", "server"))
	multiplayer.connected_to_server.connect(func() -> void: _authenticated = true)
	if Network.has_flag("emote-probe"):
		multiplayer.peer_connected.connect(_emote_player)
	Network.start_from_environment()
	_run.call_deferred()


func _process(_delta: float) -> void:
	if Network.has_flag("emote-probe"):
		for peer: int in _models.emotes:
			if _models.emote_elapsed(peer) < 0.0:
				continue
			if _emote_peer == 0:
				_emote_peer = peer
				_emote_started = float(_models.emotes[peer]["started"])
				var age := _models.emote_elapsed(peer)
				if _models.emote_name(peer) != str(Network.args.get("emote-name", "flip_off")):
					push_error("Replicated emote name differs from requested selection")
					get_tree().quit(1)
				if peer == 1 or (_role == "late" and (age < 0.4 or age > 2.5)):
					push_error("Emote identity or late-join phase invalid: %d age=%f" % [peer, age])
					get_tree().quit(1)
				print("EMOTE_OBSERVED peer=%d age=%f" % [peer, age])
			elif peer == _emote_peer and float(_models.emotes[peer]["started"]) != _emote_started:
				push_error("Repeated emote request restarted the timeline")
				get_tree().quit(1)
		if _emote_peer != 0 and not _models.emotes.has(_emote_peer) and not _emote_finished:
			_emote_finished = true
			print("EMOTE_FINISHED")
	for peer: int in _models.appearances:
		if (
			_models.appearance_for(peer) == LOOK
			and _models.type_for(peer) == "girl"
			and not _observed
		):
			if not _models.heights.has(peer):
				continue
			var emote := str(Network.args.get("emote-name", "flip_off"))
			var account_name := "Sor" if emote in ["flip_off", "salute"] else "driver"
			var expected := PlayerHeight.for_identity(peer, account_name)
			if not is_equal_approx(float(_models.heights[peer]), expected):
				push_error("Identity height did not replicate")
				get_tree().quit(1)
			var player := get_node_or_null("EmotePeer%d" % peer) as Player
			if player == null or not player.has_node("Body/Avatar"):
				continue
			var avatar := player.get_node("Body/Avatar") as BlockPlayerModel
			var factor := _models.height_scale_for(peer)
			if not is_equal_approx(avatar.height_scale(), factor):
				continue
			var capsule := (player.get_node("Collider") as CollisionShape3D).shape as CapsuleShape3D
			if not is_equal_approx(capsule.height, factor * PlayerHeight.BASE_METERS):
				push_error("Replicated height did not reach the avatar/capsule")
				get_tree().quit(1)
			if not is_equal_approx(avatar.human.shape_weight(PlayerChest.SHAPE), 1.0):
				continue
			if not bool(avatar.human.material.get_shader_parameter("chest_covered")):
				push_error("Replicated chest did not reach the shared avatar material")
				get_tree().quit(1)
			if (
				_role == "late"
				and _models.appearance_for(multiplayer.get_unique_id())["chest"] != "default"
			):
				push_error("Another player changed the late observer's appearance")
				get_tree().quit(1)
			_observed = true
			print("AVATAR_OBSERVED peer=%d height=%f" % [peer, float(_models.heights[peer])])
	var stop := str(Network.args.get("probe-stop", ""))
	if FileAccess.file_exists(stop + ".pause") and not _paused:
		get_tree().multiplayer_poll = false
		_paused = true
		print("AVATAR_PAUSED")
	if FileAccess.file_exists(stop):
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		get_tree().quit()


func _run() -> void:
	if _role != "driver":
		return
	while not _authenticated:
		await get_tree().process_frame
	_models.entity.request_action(&"appearance", LOOK)
	_models.entity.request_action(&"body", {"value": "girl"})
	var forged := LOOK.duplicate()
	forged["peer_id"] = 1
	_models.entity.request_action(&"appearance", forged)
	_models.entity.request_action(
		&"appearance", {"skin": 999999, "hair": "bald", "hair_color": 0, "eyes": 0}
	)
	var bad_chest := LOOK.duplicate()
	bad_chest["chest"] = "unknown"
	_models.entity.request_action(&"appearance", bad_chest)
	_models.entity.request_action(&"height", {"value": 100, "peer_id": 1})
	while _results.size() < 6:
		await get_tree().process_frame
	var peer := multiplayer.get_unique_id()
	while _models.appearance_for(peer) != LOOK or _models.type_for(peer) != "girl":
		await get_tree().process_frame
	if _results != [0, 0, 3, 3, 3, 1] or _models.appearances.has(1):
		push_error("Appearance request identity/validation failed: %s" % [_results])
		get_tree().quit(1)
		return
	if Network.has_flag("emote-probe"):
		_emote_player(peer)
		_models.entity.request_action(&"emote", {"name": "unknown"})
		var emote := str(Network.args.get("emote-name", "flip_off"))
		_models.entity.request_action(&"emote", {"name": emote, "peer_id": 1})
		_models.entity.request_action(&"emote", {"name": emote})
		_models.entity.request_action(&"emote", {"name": emote})
		while _emote_results.size() < 4:
			await get_tree().process_frame
		if _emote_results != [3, 3, 0, 3]:
			push_error("Emote validation/cooldown failed: %s" % [_emote_results])
			get_tree().quit(1)
			return
		while _models.emote_elapsed(peer) < 0.65:
			await get_tree().process_frame
	print("AVATAR_DRIVER_PASS")


func _emote_player(peer: int) -> void:
	var label := "EmotePeer%d" % peer
	if has_node(label):
		return
	# Real avatars exercise production pose overlays on all peers. Movement sync
	# is excluded from this static probe; normal movement has multiplayer smoke coverage.
	var player: Player = preload("res://core/player/player.tscn").instantiate()
	player.get_node("Sync").free()
	player.name = label
	player.set_multiplayer_authority(peer)
	add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
