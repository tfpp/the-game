class_name PlayerModels
extends Node
## Attaches a cosmetic rig to each existing Player, including late joiners and
## respawns. The girl body uses a smaller collision capsule; movement, authority and
## camera ownership stay intact.
##
## Also holds each player's chosen body model (see `model_picker.gd`), replicated
## from the server like clothing so everyone sees the same silhouette.

const VALID_BODY_TYPES: Array[String] = ["default", "girl", "penguin"]
const VALID_HEAD_TYPES: Array[String] = ["human", "frog", "bird"]
const VALID_TAIL_TYPES: Array[String] = ["none", "lizard", "fin", "fluffy"]
const EMOTE_SECONDS := 3.0
const EMOTE_COOLDOWN := 3.5
const EMOTE_ACTION := &"emote_flip_off"
const GIRL_RADIUS_SCALE := 0.6
const GIRL_HEIGHT_SCALE := 0.75

## Replicated (server -> everyone). peer_id -> "girl"; peers without an entry use
## the default body type. See the synchronizer config in feature.tscn.
@export var body_types: Dictionary = {}

## Same shape as `body_types`, but for the head and tail, so players can mix and
## match any body with any head and tail (see `model_picker.gd`).
@export var head_types: Dictionary = {}
@export var tail_types: Dictionary = {}
@export var appearances: Dictionary = {}
@export var emotes: Dictionary = {}
@export var emote_clock := 0.0:
	set(value):
		emote_clock = value
		_visual_clock = value
		_clock_received = true

var _visual_clock := 0.0
var _clock_received := false
var _emote_ready: Dictionary[int, float] = {}

@onready var entity: NetworkedEntity = $NetworkedEntity


func _ready() -> void:
	process_priority = 5
	add_to_group(&"player_models")
	entity.register_action(&"body", _valid_body, _apply_body)
	entity.register_action(&"head", _valid_head, _apply_head)
	entity.register_action(&"tail", _valid_tail, _apply_tail)
	entity.register_action(&"appearance", _valid_appearance, _apply_appearance)
	entity.register_action(&"emote", _valid_emote, _apply_emote)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_LEFT_STICK
	Controls.ensure_action(EMOTE_ACTION, [key, pad])
	entity.session_reset.connect(_reset_session)
	multiplayer.peer_disconnected.connect(_remove_peer)


func _unhandled_input(event: InputEvent) -> void:
	if (
		not Controls.gameplay_active()
		or not event.is_action_pressed(EMOTE_ACTION)
		or event.is_echo()
	):
		return
	if not _emote_player_exists(multiplayer.get_unique_id()):
		return
	entity.request_action(&"emote", {"name": "flip_off"})
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if multiplayer.is_server():
		emote_clock += delta
		_expire_emotes()
	else:
		_visual_clock += delta
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or player.is_queued_for_deletion():
			continue
		_apply_collider(player)
		var body := player.get_node("Body") as Node3D
		if body.has_node("Avatar"):
			continue
		var model := BlockPlayerModel.new()
		model.name = "Avatar"
		model.player = player
		model.set_skin_index(PlayerSkin.index_for_id(player.get_multiplayer_authority()))
		model.set_body_type(type_for(player.get_multiplayer_authority()))
		model.set_head_type(type_for_head(player.get_multiplayer_authority()))
		model.set_tail_type(type_for_tail(player.get_multiplayer_authority()))
		model.set_appearance(appearance_for(player.get_multiplayer_authority()))
		body.add_child(model)
		(body.get_node("Mesh") as Node3D).hide()
		(body.get_node("Visor") as Node3D).hide()


func _apply_collider(player: Player) -> void:
	var collider := player.get_node("Collider") as CollisionShape3D
	var capsule := collider.shape as CapsuleShape3D
	var girl := type_for(player.get_multiplayer_authority()) == "girl"
	var radius := player.movement.hull_radius_m() * (GIRL_RADIUS_SCALE if girl else 1.0)
	var height := player.movement.hull_height_m() * (GIRL_HEIGHT_SCALE if girl else 1.0)
	# Crouching (features/crouch) shortens the capsule; its bottom stays at the feet.
	var crouch := get_tree().get_first_node_in_group(&"crouching")
	if crouch != null and bool(crouch.call("is_crouching", player.get_multiplayer_authority())):
		height *= Crouch.HEIGHT_SCALE
	var offset := (height - player.movement.hull_height_m()) * 0.5
	if is_equal_approx(capsule.radius, radius) and is_equal_approx(capsule.height, height):
		return
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	collider.shape = shape
	collider.position.y = offset


## The body type a peer sees for themselves and everyone else. Falls back to
## "default" for peers with no stored choice or a value that isn't recognized.
func type_for(peer_id: int) -> String:
	var value := str(body_types.get(peer_id, "default"))
	return value if value in VALID_BODY_TYPES else "default"


## Compatibility adapters retain existing callers while sharing transport validation.
@rpc("any_peer", "call_local", "reliable")
func request_body_type(body_type: String) -> void:
	entity.receive_legacy_action(&"body", {"value": body_type})


## The head type a peer sees for themselves and everyone else. Falls back to
## "human" for peers with no stored choice or a value that isn't recognized.
func type_for_head(peer_id: int) -> String:
	var value := str(head_types.get(peer_id, "human"))
	return value if value in VALID_HEAD_TYPES else "human"


@rpc("any_peer", "call_local", "reliable")
func request_head_type(head_type: String) -> void:
	entity.receive_legacy_action(&"head", {"value": head_type})


## The tail type a peer sees for themselves and everyone else. Falls back to
## "none" for peers with no stored choice or a value that isn't recognized.
func type_for_tail(peer_id: int) -> String:
	var value := str(tail_types.get(peer_id, "none"))
	return value if value in VALID_TAIL_TYPES else "none"


@rpc("any_peer", "call_local", "reliable")
func request_tail_type(tail_type: String) -> void:
	entity.receive_legacy_action(&"tail", {"value": tail_type})


func appearance_for(peer: int) -> Dictionary:
	var data: Variant = appearances.get(peer, {})
	return (
		data.duplicate()
		if data is Dictionary and PlayerAppearance.valid(data)
		else PlayerAppearance.defaults()
	)


func skin_for(peer: int, fallback: int) -> int:
	var index := int(appearance_for(peer)["skin"])
	return fallback if index < 0 else index


func _valid_body(_peer: int, payload: Dictionary) -> bool:
	return payload.size() == 1 and payload.get("value") in VALID_BODY_TYPES


func _valid_head(_peer: int, payload: Dictionary) -> bool:
	return payload.size() == 1 and payload.get("value") in VALID_HEAD_TYPES


func _valid_tail(_peer: int, payload: Dictionary) -> bool:
	return payload.size() == 1 and payload.get("value") in VALID_TAIL_TYPES


func _apply_body(peer: int, payload: Dictionary) -> bool:
	body_types = _with_choice(body_types, peer, payload["value"], "default")
	return true


func _apply_head(peer: int, payload: Dictionary) -> bool:
	head_types = _with_choice(head_types, peer, payload["value"], "human")
	return true


func _apply_tail(peer: int, payload: Dictionary) -> bool:
	tail_types = _with_choice(tail_types, peer, payload["value"], "none")
	return true


func _with_choice(state: Dictionary, peer: int, value: String, default_value: String) -> Dictionary:
	var next := state.duplicate()
	if value == default_value:
		next.erase(peer)
	else:
		next[peer] = value
	return next


func _valid_appearance(_peer: int, payload: Dictionary) -> bool:
	return PlayerAppearance.valid(payload)


func _apply_appearance(peer: int, payload: Dictionary) -> bool:
	var next := appearances.duplicate(true)
	next[peer] = payload.duplicate()
	appearances = next
	return true


func _remove_peer(peer: int) -> void:
	if not multiplayer.is_server():
		return
	_emote_ready.erase(peer)
	for field: String in ["body_types", "head_types", "tail_types", "appearances", "emotes"]:
		var next: Dictionary = get(field).duplicate(true)
		next.erase(peer)
		set(field, next)


func _reset_session(_mode: Network.Mode) -> void:
	body_types = {}
	head_types = {}
	tail_types = {}
	appearances = {}
	emotes = {}
	emote_clock = 0.0
	_clock_received = false
	_emote_ready.clear()


func _valid_emote(_peer: int, payload: Dictionary) -> bool:
	return payload.size() == 1 and payload.get("name") is String and payload["name"] == "flip_off"


func _apply_emote(peer: int, _payload: Dictionary) -> bool:
	if not _emote_player_exists(peer) or emote_clock < _emote_ready.get(peer, 0.0):
		return false
	var next := emotes.duplicate(true)
	next[peer] = {"name": "flip_off", "started": emote_clock}
	emotes = next
	_emote_ready[peer] = emote_clock + EMOTE_COOLDOWN
	return true


func _emote_player_exists(peer: int) -> bool:
	for player: Node in get_tree().get_nodes_in_group(&"players"):
		if player.get_multiplayer_authority() == peer and not player.is_queued_for_deletion():
			return true
	return false


func emote_elapsed(peer: int) -> float:
	if not _clock_received or not emotes.has(peer):
		return -1.0
	var elapsed := _visual_clock - float(emotes[peer]["started"])
	return elapsed if elapsed >= 0.0 and elapsed < EMOTE_SECONDS else -1.0


func emote_weight(peer: int) -> float:
	return emote_envelope(emote_elapsed(peer))


static func emote_envelope(elapsed: float) -> float:
	if elapsed < 0.0 or elapsed >= EMOTE_SECONDS:
		return 0.0
	return smoothstep(0.0, 0.35, elapsed) * (1.0 - smoothstep(2.55, EMOTE_SECONDS, elapsed))


func _expire_emotes() -> void:
	var next := emotes.duplicate(true)
	for peer: int in emotes:
		if (
			emote_clock - float(emotes[peer]["started"]) >= EMOTE_SECONDS
			or not _emote_player_exists(peer)
		):
			next.erase(peer)
	if next != emotes:
		emotes = next
