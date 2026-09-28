extends Node
## Attaches a cosmetic rig to each existing Player, including late joiners and
## respawns. Player collision, movement, authority and camera ownership stay intact.


func _ready() -> void:
	process_priority = 5


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
		body.add_child(model)
		(body.get_node("Mesh") as Node3D).hide()
		(body.get_node("Visor") as Node3D).hide()
