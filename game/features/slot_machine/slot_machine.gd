class_name SlotMachine
extends StaticBody3D
## Clients request a spin; only the server validates, chooses, advances and settles it.
## One atomic replicated snapshot includes the visible reels, lock and result.

const USE_RANGE := 3.5
const FIRST_STOP_S := 1.2
const STOP_INTERVAL_S := 0.9
const FRAME_S := 0.1

## Each machine instance in feature.tscn sets its own price; every peer loads
## the same scene, so this needs no replication.
@export var buy_in_cents: int = 100

@export var state: Dictionary = initial_state()

var _pending := false
var _generation := 0
var _prize := 0
var _result: Array[int] = []
var _elapsed := 0.0
var _frame_elapsed := 0.0
var _last_sound_spin := 0
var _win_sound: AudioStream
var _lose_sound: AudioStream

@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	add_to_group(&"interactables")
	Network.mode_changed.connect(_on_mode_changed)
	_win_sound = _load_sound("res://features/slot_machine/audio/win.ogg")
	_lose_sound = _load_sound("res://features/slot_machine/audio/lose.ogg")


static func initial_state() -> Dictionary:
	return {
		"spin": 0,
		"spinning": false,
		"reels": [0, 1, 2],
		"stopped": 3,
		"operator": "",
		"won": false,
		"payout": 0,
		"message": ""
	}


func interaction_text() -> String:
	if state["spinning"]:
		return "Slot machine — spinning…"
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	var text := "Spin slot machine — %s" % PlayerMoney.format_money(buy_in_cents)
	if wallet != null and wallet.balances.has(multiplayer.get_unique_id()):
		text += (
			" (you have %s)"
			% PlayerMoney.format_money(int(wallet.balances[multiplayer.get_unique_id()]))
		)
	var prayer := get_tree().get_first_node_in_group(&"kaaba_prayer") as KaabaPrayer
	if prayer != null and prayer.blessings_for(multiplayer.get_unique_id()) > 0:
		text += " — blessed ×%d" % prayer.blessings_for(multiplayer.get_unique_id())
	return text


func interaction_point() -> Vector3:
	return to_global(Vector3(0, 1.65, 0.65))


func can_use(player: Player) -> bool:
	var eye := (
		player.net_position
		+ Vector3.UP * (player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5)
	)
	var offset := interaction_point() - eye
	if offset.length() > USE_RANGE or offset.length() < 0.01:
		return false
	var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0)) * Vector3.FORWARD
	if look.dot(offset.normalized()) < 0.75:
		return false
	# Only the front of the cabinet can be used; walls and other bodies block access.
	if (eye - global_position).dot(global_basis.z) <= 0.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		eye, to_global(Vector3(0, 1.65, 0)), 1, [player.get_rid()]
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == self


func use() -> void:
	request_spin.rpc_id(1)


@rpc("any_peer", "call_local", "reliable")
func request_spin() -> void:
	if not multiplayer.is_server() or state["spinning"] or _pending:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	var player := _player_for_peer(peer_id)
	if player == null or not can_use(player):
		return
	var wallet := get_tree().get_first_node_in_group(&"player_money") as PlayerMoney
	if wallet == null:
		return
	_pending = true
	state = state.duplicate(true)
	state["message"] = "Checking wallet…"
	var generation := _generation
	var operator_name := player.display_name
	var id := Crypto.new().generate_random_bytes(32).hex_encode()
	var prayer := get_tree().get_first_node_in_group(&"kaaba_prayer") as KaabaPrayer
	var rerolls := prayer.blessings_for(peer_id) if prayer != null else 0
	var result: Dictionary = await wallet.spin(peer_id, id, buy_in_cents, rerolls)
	if generation != _generation:
		return
	_pending = false
	if result.has("error"):
		var next := state.duplicate(true)
		next["message"] = str(result["error"])
		state = next
		return
	var reels: Array[int] = []
	reels.assign(result["reels"])
	if prayer != null and is_instance_valid(prayer) and SlotSpinCycle.is_win(reels):
		prayer.consume(peer_id)
	_begin_spin(peer_id, operator_name, reels, int(result["payout"]))


func _begin_spin(
	peer_id: int, display_name: String, reels: Array[int] = [0, 1, 2], prize: int = 0
) -> void:
	_result = reels
	_prize = prize
	_elapsed = 0.0
	_frame_elapsed = 0.0
	state = {
		"spin": int(state["spin"]) + 1,
		"spinning": true,
		"reels": [0, 1, 2],
		"stopped": 0,
		"operator": display_name if display_name else "Player %d" % peer_id,
		"won": false,
		"payout": 0,
		"message": ""
	}


func _process(delta: float) -> void:
	if multiplayer.is_server() and state["spinning"]:
		_advance(delta)


func _advance(delta: float) -> void:
	if not state["spinning"]:
		return
	_elapsed += delta
	_frame_elapsed += delta
	if _frame_elapsed < FRAME_S:
		return
	_frame_elapsed = 0.0
	var stopped := clampi(int(floor((_elapsed - FIRST_STOP_S) / STOP_INTERVAL_S)) + 1, 0, 3)
	var next := state.duplicate(true)
	var reels: Array[int] = []
	for index: int in 3:
		reels.append(
			(
				_result[index]
				if index < stopped
				else (int(_elapsed / FRAME_S) + index) % SlotSpinCycle.SYMBOL_COUNT
			)
		)
	next["reels"] = reels
	next["stopped"] = stopped
	if stopped == 3:
		next["spinning"] = false
		next["won"] = SlotSpinCycle.is_win(_result)
		next["payout"] = _prize
	state = next
	if stopped == 3:
		play_result.rpc(int(state["spin"]), bool(state["won"]))


## An event, not saved state: late joiners see the result without replaying old audio.
@rpc("authority", "call_local", "reliable")
func play_result(spin: int, won: bool) -> void:
	if spin <= _last_sound_spin:
		return
	_last_sound_spin = spin
	_audio.stream = _win_sound if won else _lose_sound
	if _audio.stream != null:
		_audio.play()


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null


func _on_mode_changed(_mode: Network.Mode) -> void:
	# Do not carry local/offline results into a newly joined server, or vice versa.
	state = initial_state()
	_pending = false
	_generation += 1
	_prize = 0
	_result.clear()
	_last_sound_spin = 0
	_audio.stop()


func _load_sound(path: String) -> AudioStream:
	return load(path) as AudioStream if ResourceLoader.exists(path) else null
