extends Node3D
## Database-owned one-shot puzzle; only public status is replicated.

const LocalPuzzle := preload("res://features/timed_bomb/local_puzzle.gd")

@export var net_state := "loading"
@export var net_remaining := 86400
@export var net_available := false
@export var practice_path := "user://timed_bomb_practice.json"

var _local: RefCounted
var _busy := false
var _generation := 0
var _next_poll := 0
var _sample_ticks := 0
var _sample_remaining := 0

@onready var entity: NetworkedInteraction = $NetworkedEntity
@onready var display: Label3D = $Display


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _open)
	entity.register_action(&"defuse", _may_defuse, _defuse, 0.5)
	entity.session_reset.connect(_reset)
	entity.event_received.connect(_event)
	_reset(Network.mode)


func _process(_delta: float) -> void:
	if entity.is_authority():
		if not _busy and Time.get_ticks_msec() >= _next_poll:
			_fetch()
		if net_state == "armed" and net_available:
			net_remaining = maxi(
				0, _sample_remaining - (Time.get_ticks_msec() - _sample_ticks) / 1000
			)
	display.text = status_text()
	$Body.visible = net_state != "exploded"
	$Wreck.visible = net_state == "exploded"


func status_text() -> String:
	if net_state == "defused":
		return "DEFUSED"
	if net_state == "exploded":
		return "SPENT — BOOM!"
	if not net_available:
		return "TIMED BOMB\nConnecting…"
	var hours := net_remaining / 3600
	var minutes := (net_remaining % 3600) / 60
	return "TIMED BOMB\n%02d:%02d:%02d" % [hours, minutes, net_remaining % 60]


func can_use(player: Player) -> bool:
	return net_available and net_state == "armed" and entity.in_range(player)


func interaction_text() -> String:
	return "Timed bomb — enter defusal code"


func use() -> void:
	entity.request_use()


func _open(player: Player) -> bool:
	entity.send_event(&"keypad", {}, player.get_multiplayer_authority())
	return true


func _may_defuse(peer: int, payload: Dictionary) -> bool:
	return (
		not _busy
		and can_use(entity.player_for_peer(peer))
		and payload.size() == 1
		and LocalPuzzle.valid_code(payload.get("code"))
	)


func _defuse(peer: int, payload: Dictionary) -> bool:
	if not entity.is_authority() or not _may_defuse(peer, payload):
		return false
	var player := entity.player_for_peer(peer)
	_fetch(str(payload["code"]), player)
	return true


func _fetch(guess := "", player: Player = null) -> void:
	_busy = true
	var generation := _generation
	var result: Dictionary = await _request(guess)
	if generation != _generation or not entity.is_authority():
		return
	_busy = false
	_next_poll = Time.get_ticks_msec() + 5000
	if result.is_empty():
		net_available = false
	else:
		var previous := net_state
		net_state = str(result["state"])
		net_remaining = int(result["remaining"])
		_sample_ticks = Time.get_ticks_msec()
		_sample_remaining = net_remaining
		net_available = true
		if net_state == "armed":
			_next_poll = Time.get_ticks_msec() + clampi(net_remaining * 1000, 1000, 5000)
		if previous == "armed" and net_state == "exploded":
			entity.send_event(&"blast")
	if (
		is_instance_valid(player)
		and entity.player_for_peer(player.get_multiplayer_authority()) == player
	):
		entity.send_event(
			&"reply",
			{"text": str(result.get("message", "Connection unavailable. Try again."))},
			player.get_multiplayer_authority()
		)


func _request(guess: String) -> Dictionary:
	if Network.mode == Network.Mode.OFFLINE or Network.ticket_key.is_empty():
		# Dev-auth servers use an isolated practice puzzle too, never live DB.
		if _local == null:
			_local = LocalPuzzle.new()
			_local.path = practice_path
			if not _local.load_or_create(int(Time.get_unix_time_from_system())):
				_local = null
				return {}
		return _local.snapshot(int(Time.get_unix_time_from_system()), guess)
	var body := JSON.stringify(
		{
			"action": "status" if guess.is_empty() else "defuse",
			"code": guess,
			"timestamp": int(Time.get_unix_time_from_system())
		}
	)
	var signature := (
		Crypto
		. new()
		. hmac_digest(
			HashingContext.HASH_SHA256,
			Network.ticket_key,
			("game-timed-bomb-v1\n" + body).to_utf8_buffer()
		)
		. hex_encode()
	)
	var request := HTTPRequest.new()
	request.timeout = 5.0
	add_child(request)
	var error := request.request(
		Network.resolve_api_url() + "/game/timed-bomb",
		["Content-Type: application/json", "X-Game-Signature: " + signature],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		request.queue_free()
		return {}
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		return {}
	var bytes: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if (
		not parsed is Dictionary
		or str(parsed.get("state")) not in ["armed", "defused", "exploded"]
		or not parsed.has("remaining")
	):
		return {}
	return parsed


func _reset(_mode: Network.Mode) -> void:
	_generation += 1
	_busy = false
	_local = null
	_next_poll = 0
	net_available = false
	net_state = "loading"


func _event(event: StringName, _payload: Dictionary) -> void:
	if event != &"blast" or Network.mode == Network.Mode.SERVER:
		return
	GameAudio.play_at(self, &"explosion", global_position + Vector3.UP)
	var flash := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0.55, 0.08)
	sphere.material = material
	flash.mesh = sphere
	add_child(flash)
	flash.position.y = 0.6
	var tween := create_tween()
	tween.tween_property(flash, "scale", Vector3.ONE * 4, 0.4)
	tween.tween_callback(flash.queue_free)
