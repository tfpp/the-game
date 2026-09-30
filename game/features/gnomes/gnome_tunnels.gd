extends Node3D
## Hole links stay present on every peer; only the tunnel's scenery is streamed.

const SPEED_MULTIPLIER := 4.0
var tunnel: StreamedRoom
var _boosted: Player


func _ready() -> void:
	tunnel = StreamedRoom.new()
	tunnel.name = "Tunnel"
	tunnel.position = Vector3(0, 0, -1000)
	tunnel.bounds = AABB(Vector3(-4, -1, -4), Vector3(128, 6, 8))
	tunnel.room_scene = "res://features/gnomes/tunnel_interior.tscn"
	add_child(tunnel)
	var index := 0
	for train: Node in get_children():
		if not train.name.begins_with("Train"):
			continue
		for hole: Node in train.get_children():
			if not hole.name.begins_with("Hole"):
				continue
			var label := "%s %d" % [str(train.name).trim_prefix("Train"), index % 4 + 1]
			_link(hole as Node3D, index, label)
			index += 1


func _link(hole: Node3D, index: int, label: String) -> void:
	var surface := Marker3D.new()
	surface.name = "SurfaceArrival"
	# Holes sit on walls facing +Z; surface a step into the room.
	surface.position = Vector3(0, 1.1, 1.2)
	hole.add_child(surface)
	var arrival := Marker3D.new()
	arrival.name = "Arrival%d" % index
	arrival.position = Vector3(index * 8, 1.1, 0)
	arrival.rotation.y = -PI / 2
	tunnel.add_child(arrival)
	_add_door(hole, "Enter", Vector3(0, 0.4, 0.2), arrival, "Enter gnome tunnels (4x speed)")
	_add_door(tunnel, "Exit%d" % index, Vector3(index * 8, 1, -2.8), surface, "Exit to " + label)
	var sign := Label3D.new()
	sign.text = label + "\nUSE to surface"
	sign.position = Vector3(index * 8, 2.4, -2.65)
	sign.font_size = 40
	sign.modulate = Color(1, 0.85, 0.45)
	tunnel.add_child(sign)
	var entry_sign := Label3D.new()
	entry_sign.text = label + "\nGnome tunnels - USE"
	entry_sign.position = Vector3(0, 1.0, 0.15)
	entry_sign.pixel_size = 0.003
	entry_sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hole.add_child(entry_sign)


func _add_door(
	parent: Node3D, node_name: String, pos: Vector3, arrival: Marker3D, label: String
) -> void:
	var door := RoomDoor.new()
	door.name = node_name
	door.position = pos
	door.size = Vector3(1.2, 1.8, 0.15)
	door.visible = parent == tunnel
	door.door_label = label
	# Resolve relative to the future parent before _ready runs.
	door.destination = NodePath("../" + str(parent.get_path_to(arrival)))
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25, 0.4, 0.16)
	door.material = material
	parent.add_child(door)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_boosted):
		_boosted = null
	var player := get_tree().get_first_node_in_group(&"local_player") as Player
	if (
		is_instance_valid(_boosted)
		and (_boosted != player or not tunnel.contains(player.global_position))
	):
		_restore_speed()
	if player != null and _boosted == null and tunnel.contains(player.global_position):
		_boosted = player
		# Each player must own its resource; never modify the scene's shared default.
		player.movement = player.movement.duplicate() as MovementConfig
		# Ratios compose with other speed changes such as crouching (features/crouch).
		player.movement.max_speed *= SPEED_MULTIPLIER


func _restore_speed() -> void:
	if is_instance_valid(_boosted):
		_boosted.movement.max_speed /= SPEED_MULTIPLIER
	_boosted = null


func _exit_tree() -> void:
	_restore_speed()
