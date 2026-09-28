class_name PlayerModels
extends Node
## Attaches a cosmetic rig to each existing Player, including late joiners and
## respawns. Player collision, movement, authority and camera ownership stay intact.
##
## Also holds each player's chosen body model (see `model_picker.gd`), replicated
## from the server like clothing so everyone sees the same silhouette.

const VALID_BODY_TYPES: Array[String] = ["default", "girl", "penguin"]

## Replicated (server -> everyone). peer_id -> "girl"; peers without an entry use
## the default body type. See the synchronizer config in feature.tscn.
@export var body_types: Dictionary = {}


func _ready() -> void:
	process_priority = 5
	add_to_group(&"player_models")


func _process(_delta: float) -> void:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player == null or player.is_queued_for_deletion():
			continue
		var body := player.get_node("Body") as Node3D
		if body.has_node("Avatar"):
			continue
		var model := BlockPlayerModel.new()
		model.name = "Avatar"
		model.player = player
		model.set_skin_index(PlayerSkin.index_for_id(player.get_multiplayer_authority()))
		model.set_body_type(type_for(player.get_multiplayer_authority()))
		body.add_child(model)
		(body.get_node("Mesh") as Node3D).hide()
		(body.get_node("Visor") as Node3D).hide()


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
