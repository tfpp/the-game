extends Node3D
## Stable server-owned ambient scheduler. Streamed bodies only read its snapshot.

const LINES: Array[String] = [
	"City Sushi! Stop stealing my customers!",
	"City Wok! Let the customers choose!",
	"My wok is the king of this plaza!",
	"Your shouting is scaring the lunch crowd!",
	"Keep your sushi away from my wok!",
	"Then keep your wok away from my sushi!",
]
const TURN_SECONDS := 4.0
const REST_SECONDS := 10.0
const BUBBLE_SECONDS := 3.2

var net_turn := -1
var net_remaining := REST_SECONDS
@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"mall_rivalry")
	entity.session_reset.connect(_reset)
	entity.event_received.connect(_event)


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	# A disconnected transport has no valid peer ID for is_authority().
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not entity.is_authority() or not is_finite(delta) or delta <= 0.0:
		return
	net_remaining -= delta
	if net_remaining > 0.0:
		return
	# One step only: a stalled frame must not replay a backlog of shouts.
	net_turn += 1
	if net_turn >= LINES.size():
		net_turn = -1
	net_remaining = REST_SECONDS if net_turn < 0 else TURN_SECONDS
	if net_turn >= 0:
		entity.send_event(&"yell", {"turn": net_turn})


func active_speaker() -> int:
	return -1 if net_turn < 0 else net_turn % 2


func bubble_visible(speaker: int) -> bool:
	return active_speaker() == speaker and net_remaining > TURN_SECONDS - BUBBLE_SECONDS


func _event(event: StringName, payload: Dictionary) -> void:
	if event != &"yell" or not payload.get("turn") is int:
		return
	var turn: int = payload["turn"]
	if turn < 0 or turn >= LINES.size():
		return
	# No old sounds on streaming/late join. Only current visitors hear live events.
	var room := get_parent() as StreamedRoom
	if not room.is_loaded():
		return
	var speaker := turn % 2
	var point := Vector3(9.0 if speaker == 0 else 21.0, 1.5, 41)
	GameAudio.play_at(
		self, &"city_wok_yell" if speaker == 0 else &"city_sushi_yell", room.to_global(point)
	)


func _reset(_mode: Network.Mode) -> void:
	net_turn = -1
	net_remaining = REST_SECONDS
