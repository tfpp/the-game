class_name Vivienne
extends Node3D
## Vivienne sits at the bar. Pay her (the price falls with your charisma) and she
## follows you until you lead her into your Lily Apartments unit, which grants a
## lucky night in BarCompanion. The server simulates her; clients show `net_*` state.

const TALK_RANGE := 2.4
const ESCORT_S := 300.0
## How long she lingers in the room before heading back to her stool.
const LINGER_S := 4.0
const FOLLOW_DISTANCE := 1.3
const WALK_SPEED := 5.5
## Farther than this (doors, elevators), she catches up at once instead of walking.
const CATCH_UP_DISTANCE := 10.0
const ARRIVE_DISTANCE := 4.0

@export var net_position := Vector3.ZERO
@export var net_yaw := 0.0
## Peer she is following, or 0 while she sits at the bar.
@export var net_escort := 0

var _seat := Vector3.ZERO
var _escort_left := 0.0
var _linger_left := 0.0
var _pending := false
var _idle := 0.0
var _speech_left := 0.0

@onready var _companion := get_parent() as BarCompanion
@onready var _talk: NetworkedInteraction = $NetworkedEntity
@onready var _body: CompanionModel = $Body
@onready var _speech: Label3D = $Speech


func _ready() -> void:
	add_to_group(&"interactables")
	_seat = position
	net_position = global_position
	_body.build_vivienne()
	_body.sit(0.0, CompanionModel.SEATED_HIP, 0.0, 0.5, -0.9)
	_talk.interaction_range = TALK_RANGE
	_talk.register_use(can_use, _apply_use, 0.5)
	_talk.register_action(&"conversation", _may_converse, _open_conversation, 0.2)
	_talk.register_action(&"case", _may_case, _apply_case, 0.2)
	_talk.event_received.connect(_on_event)
	_talk.session_reset.connect(_on_session_reset)


func interaction_text() -> String:
	var peer := multiplayer.get_unique_id()
	return (
		"Talk to %s — story / night out (-%s, charisma %d)"
		% [
			CompanionModel.NAME,
			PlayerMoney.format_money(CharmMath.price_cents(_companion.charisma_for(peer))),
			_companion.charisma_for(peer),
		]
	)


func can_use(player: Player) -> bool:
	return net_escort == 0 and not _pending and _talk.in_range(player)


func use() -> void:
	_talk.request_action(&"conversation")


func _case() -> VivienneCase:
	return get_parent().get_node("VivienneCase") as VivienneCase


func _may_converse(peer: int, payload: Dictionary) -> bool:
	return (
		payload.is_empty()
		and can_use(_talk.player_for_peer(peer))
		and _case().active_player(_talk.player_for_peer(peer))
	)


func _open_conversation(peer: int, _payload: Dictionary) -> bool:
	_talk.send_event(
		&"case_page",
		{
			"title": "VIVIENNE — TOPICS",
			"text":
			(
				(VivienneCase.LINES[9] + "\n\n" if _case().stage(peer) == 9 else "")
				+ _case().objective(peer)
			),
			"choices":
			[
				{"id": str(_case().stage(peer)), "label": _case().topic(peer)},
				{
					"id": "hire",
					"label": "A night out — " + PlayerMoney.format_money(_companion.price_for(peer))
				}
			]
		},
		peer
	)
	return true


func _may_case(peer: int, payload: Dictionary) -> bool:
	return (
		payload.size() == 1
		and payload.get("step") is int
		and int(payload["step"]) == _case().stage(peer)
		and can_use(_talk.player_for_peer(peer))
		and _case().active_player(_talk.player_for_peer(peer))
	)


func _apply_case(peer: int, _payload: Dictionary) -> bool:
	if not _case().allowed(peer, -1):
		_open_conversation(peer, {})
		return true
	return _case().act(_talk.player_for_peer(peer), -1, _talk)


func is_seated() -> bool:
	return net_escort == 0


func _apply_use(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null:
		return false
	var apartments := get_tree().get_first_node_in_group(&"apartments") as Apartments
	if apartments == null or apartments.unit_for(peer) == 0:
		_say(peer, "Get a room at Lily Apartments first, darling.")
		return false
	_pending = true
	_hire(wallet, peer, _companion.price_for(peer))
	return true


func _hire(wallet: PlayerMoney, peer: int, price: int) -> void:
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var result: Dictionary = await wallet.charge(peer, id, price)
	_pending = false
	if not is_inside_tree() or _talk.player_for_peer(peer) == null or net_escort != 0:
		return
	if result.has("error"):
		_say(peer, str(result["error"]))
		return
	var apartments := get_tree().get_first_node_in_group(&"apartments") as Apartments
	var unit := apartments.unit_for(peer) if apartments != null else 0
	net_escort = peer
	_escort_left = ESCORT_S
	_linger_left = 0.0
	_say(0, "Lead me to your room, unit %s." % Apartments.unit_label(unit))


func _physics_process(delta: float) -> void:
	if multiplayer.is_server() and net_escort != 0:
		_escort_step(delta)
	_present(delta)


## Server-only.
func _escort_step(delta: float) -> void:
	var player := _talk.player_for_peer(net_escort)
	_escort_left -= delta
	if player == null or _escort_left <= 0.0:
		_return_to_bar()
		return
	if _linger_left > 0.0:
		_linger_left -= delta
		if _linger_left <= 0.0:
			_return_to_bar()
		return
	net_position = follow_point(net_position, player.net_position, delta)
	var facing := player.net_position - net_position
	facing.y = 0.0
	if facing.length() > 0.05:
		net_yaw = atan2(-facing.x, -facing.z)
	var apartments := get_tree().get_first_node_in_group(&"apartments") as Apartments
	if (
		apartments != null
		and apartments.in_unit(net_escort, player.net_position)
		and net_position.distance_to(player.net_position) <= ARRIVE_DISTANCE
	):
		_companion.grant_luck(net_escort)
		_say(0, "Lady Luck is on your side tonight.")
		_linger_left = LINGER_S


## Where she walks this frame to stay FOLLOW_DISTANCE behind `leader`.
static func follow_point(from: Vector3, leader: Vector3, delta: float) -> Vector3:
	var offset := from - leader
	offset.y = 0.0
	var distance := offset.length()
	var away := offset / distance if distance > 0.01 else Vector3.BACK
	if distance > CATCH_UP_DISTANCE:
		return leader + away * FOLLOW_DISTANCE
	if distance <= FOLLOW_DISTANCE:
		return Vector3(from.x, leader.y, from.z)
	var step := minf(WALK_SPEED * delta, distance - FOLLOW_DISTANCE)
	var next := from - away * step
	next.y = leader.y
	return next


func _return_to_bar() -> void:
	net_escort = 0
	_escort_left = 0.0
	_linger_left = 0.0
	net_position = get_parent().to_global(_seat) if get_parent() is Node3D else _seat
	net_yaw = 0.0


func _present(delta: float) -> void:
	var moved := global_position.distance_to(net_position)
	if moved > CATCH_UP_DISTANCE * 0.5:
		global_position = net_position
	else:
		global_position = global_position.lerp(net_position, minf(delta * 12.0, 1.0))
	rotation.y = lerp_angle(rotation.y, net_yaw, minf(delta * 10.0, 1.0))
	_idle += delta
	if net_escort == 0:
		_body.sit(delta, CompanionModel.SEATED_HIP, _idle, 0.5, -0.9)
	else:
		var speed := moved / maxf(delta, 0.001)
		_body.pose(delta, clampf(speed / 2.0, 0.0, 1.0), 0.0, 0.0, _idle)
	if _speech.visible:
		_speech_left -= delta
		_speech.visible = _speech_left > 0.0


## Shows a speech bubble to `peer`, or to everyone when `peer` is 0.
func _say(peer: int, text: String) -> void:
	_talk.send_event(&"say", {"text": text}, peer)


func _on_event(event: StringName, payload: Dictionary) -> void:
	if event == &"say":
		Subtitles.say(get_tree(), CompanionModel.NAME, str(payload.get("text", "")))
		_speech.text = str(payload.get("text", ""))
		_speech.visible = true
		_speech_left = 4.0


func _on_session_reset(_mode: Network.Mode) -> void:
	_pending = false
	_return_to_bar()
