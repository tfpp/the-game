class_name Celeste
extends CharacterBody3D
## A free, noncombat casino sidekick. Only the server owns her trail and allegiance
## is deliberately never resolved. Clients animate the replicated pose.

const RANGE := 2.4
const FOLLOW_DISTANCE := 1.8
const SPEED := 4.2
const VISIT_S := 300.0
const REMARK_S := 22.0
const MAX_GAP := 18.0
const LINES: Array[String] = [
	"Keep your stake small, darling. I'd hate to see someone else take everything.",
	"The elevator is your way to the slums. Coming back is the clever part.",
	"I'm watching your back. You needn't turn around to check what I'm doing.",
	"The bartender charges five dollars. Some people here ask for rather more.",
	"If anyone asks, we arrived separately. Especially if I ask.",
	"Those card tables are just for show. The slots and roulette take real wagers.",
	"You can trust me with a secret. I already know which ones are worth keeping.",
	"No, darling, I haven't decided what I want from you. Walk with me a little longer.",
]

@export var net_leader := 0
@export var net_position := Vector3.ZERO
@export var net_yaw := PI

var _home := Vector3.ZERO
var _leader: Player
var _trail: Array[Vector3] = []
var _visit_left := 0.0
var _remark_left := REMARK_S
var _line := 0
var _idle := 0.0
var _previous := Vector3.ZERO

@onready var _talk: NetworkedInteraction = $NetworkedEntity
@onready var _body: CompanionModel = $Body


func _ready() -> void:
	_home = global_position
	net_position = _home
	_previous = _home
	add_to_group(&"interactables")
	_talk.interaction_range = RANGE
	_talk.register_use(can_use, _apply_use, 1.0)
	_talk.event_received.connect(_on_event)
	_talk.session_reset.connect(func(_mode: Network.Mode) -> void: _return_home())
	multiplayer.peer_disconnected.connect(_on_disconnect)
	# Combat loads after bar_companion in the feature loader.
	_connect_combat.call_deferred()


func _connect_combat() -> void:
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null:
		combat.player_died.connect(_on_death)


func interaction_text() -> String:
	if net_leader == multiplayer.get_unique_id():
		return "Part ways with Celeste"
	return "Invite Celeste along (free)"


func can_use(player: Player) -> bool:
	return (
		_talk.in_range(player)
		and on_gaming_floor(player.net_position)
		and (net_leader == 0 or net_leader == player.get_multiplayer_authority())
	)


func use() -> void:
	_talk.request_use()


func _apply_use(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	if net_leader == peer:
		_say(
			"Of course. I'll be at the bar. You know where to find me... and I know where to find you."
		)
		_return_home()
	else:
		net_leader = peer
		_leader = player
		_trail.assign([player.net_position])
		_visit_left = VISIT_S
		_remark_left = REMARK_S
		_say(
			"Celeste. I'll watch your back around the gaming floor. For now. Use again to part ways."
		)
	return true


## Bounds deliberately exclude streamed rooms, gallery and slums; jumping is allowed.
static func on_gaming_floor(point: Vector3) -> bool:
	return absf(point.x) < 14.0 and absf(point.z) < 11.5 and point.y > -2.0 and point.y < 2.5


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_advance(delta)
	else:
		if global_position.distance_to(net_position) > 4.0:
			global_position = net_position
		else:
			global_position = global_position.lerp(net_position, minf(delta * 12.0, 1.0))
	rotation.y = lerp_angle(rotation.y, net_yaw, minf(delta * 12.0, 1.0))
	var moved := global_position.distance_to(_previous)
	_previous = global_position
	_idle += delta
	_body.pose(delta, clampf(moved / maxf(delta * SPEED, 0.001), 0.0, 1.0), 0, 0, _idle)


func _advance(delta: float) -> void:
	if not multiplayer.is_server() or net_leader == 0:
		return
	_visit_left -= delta
	if not is_instance_valid(_leader) or _talk.player_for_peer(net_leader) != _leader:
		_return_home()
		return
	var point := _leader.net_position
	if (
		_visit_left <= 0.0
		or not on_gaming_floor(point)
		or global_position.distance_to(point) > MAX_GAP
	):
		_say("This is where we part, darling. I'll keep a place for you at the bar. Perhaps.")
		_return_home()
		return
	# Follow the player's route around furniture rather than cutting straight across tables.
	var flat := Vector3(point.x, -1.5, point.z)
	if _trail.is_empty() or _trail.back().distance_to(flat) > 0.6:
		_trail.append(flat)
	if _trail.size() > 128:
		_say("You've lost me. Or have you? Find me at the bar.")
		_return_home()
		return
	var offset := point - global_position
	offset.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	if offset.length() > FOLLOW_DISTANCE and not _trail.is_empty():
		var heading := _trail[0] - global_position
		heading.y = 0.0
		if heading.length() < 0.35:
			_trail.pop_front()
		else:
			var motion := heading.normalized() * minf(SPEED, heading.length() / maxf(delta, 0.001))
			velocity.x = motion.x
			velocity.z = motion.z
			net_yaw = atan2(-heading.x, -heading.z)
	velocity.y = -2.0 if is_on_floor() else maxf(velocity.y - 20.0 * delta, -20.0)
	move_and_slide()
	net_position = global_position
	_remark_left -= delta
	if _remark_left <= 0.0 and offset.length() < 5.0:
		_say(LINES[_line % LINES.size()])
		_line += 1
		_remark_left = REMARK_S


func _return_home() -> void:
	if not multiplayer.is_server():
		return
	net_leader = 0
	_leader = null
	_trail.clear()
	velocity = Vector3.ZERO
	net_position = _home
	global_position = _home
	net_yaw = PI


func _on_disconnect(peer: int) -> void:
	if net_leader == peer:
		_return_home()


func _on_death(peer: int, _attacker: int) -> void:
	_on_disconnect(peer)


func _say(line: String) -> void:
	_talk.send_event(&"say", {"text": line}, net_leader)


func _on_event(event: StringName, payload: Dictionary) -> void:
	if event == &"say":
		Subtitles.say(get_tree(), "Celeste", str(payload.get("text", "")))
