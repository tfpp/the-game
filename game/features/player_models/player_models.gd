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
const GIRL_RADIUS_SCALE := 0.6
const GIRL_HEIGHT_SCALE := 0.75

## Replicated (server -> everyone). peer_id -> "girl"; peers without an entry use
## the default body type. See the synchronizer config in feature.tscn.
@export var body_types: Dictionary = {}

## Same shape as `body_types`, but for the head and tail, so players can mix and
## match any body with any head and tail (see `model_picker.gd`).
@export var head_types: Dictionary = {}
@export var tail_types: Dictionary = {}


func _ready() -> void:
	process_priority = 5
	add_to_group(&"player_models")


func _process(_delta: float) -> void:
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
		body.add_child(model)
		(body.get_node("Mesh") as Node3D).hide()
		(body.get_node("Visor") as Node3D).hide()


func _apply_collider(player: Player) -> void:
	var collider := player.get_node("Collider") as CollisionShape3D
	var capsule := collider.shape as CapsuleShape3D
	var girl := type_for(player.get_multiplayer_authority()) == "girl"
	var radius := player.movement.hull_radius_m() * (GIRL_RADIUS_SCALE if girl else 1.0)
	var height := player.movement.hull_height_m() * (GIRL_HEIGHT_SCALE if girl else 1.0)
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


## Clients request their own body type; the server validates and applies it.
@rpc("any_peer", "call_local", "reliable")
func request_body_type(body_type: String) -> void:
	if not multiplayer.is_server() or body_type not in VALID_BODY_TYPES:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	if type_for(peer_id) == body_type:
		return
	var next: Dictionary = body_types.duplicate()
	if body_type == "default":
		next.erase(peer_id)
	else:
		next[peer_id] = body_type
	body_types = next


## The head type a peer sees for themselves and everyone else. Falls back to
## "human" for peers with no stored choice or a value that isn't recognized.
func type_for_head(peer_id: int) -> String:
	var value := str(head_types.get(peer_id, "human"))
	return value if value in VALID_HEAD_TYPES else "human"


## Clients request their own head type; the server validates and applies it.
@rpc("any_peer", "call_local", "reliable")
func request_head_type(head_type: String) -> void:
	if not multiplayer.is_server() or head_type not in VALID_HEAD_TYPES:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	if type_for_head(peer_id) == head_type:
		return
	var next: Dictionary = head_types.duplicate()
	if head_type == "human":
		next.erase(peer_id)
	else:
		next[peer_id] = head_type
	head_types = next


## The tail type a peer sees for themselves and everyone else. Falls back to
## "none" for peers with no stored choice or a value that isn't recognized.
func type_for_tail(peer_id: int) -> String:
	var value := str(tail_types.get(peer_id, "none"))
	return value if value in VALID_TAIL_TYPES else "none"


## Clients request their own tail type; the server validates and applies it.
@rpc("any_peer", "call_local", "reliable")
func request_tail_type(tail_type: String) -> void:
	if not multiplayer.is_server() or tail_type not in VALID_TAIL_TYPES:
		return
	var sender := multiplayer.get_remote_sender_id()
	var peer_id := sender if sender != 0 else multiplayer.get_unique_id()
	if type_for_tail(peer_id) == tail_type:
		return
	var next: Dictionary = tail_types.duplicate()
	if tail_type == "none":
		next.erase(peer_id)
	else:
		next[peer_id] = tail_type
	tail_types = next
