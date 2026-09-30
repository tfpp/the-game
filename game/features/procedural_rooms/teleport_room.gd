extends Node3D
## Walk-in socket room joined to the casino's existing east doorway.

const Kit := preload("res://features/procedural_rooms/example_kit.gd")
const Shell := preload("res://features/procedural_rooms/shell_mesh.gd")
const CONCRETE := preload("res://features/procedural_rooms/materials/concrete.tres")


func _ready() -> void:
	var room := Kit.room("Lobby")
	add_child(room)
	(room.get_node("In") as ProceduralSocketAttachment).open("casino-east-doorway")
	Shell.rebuild(self)
	($Structure/Floor as MeshInstance3D).material_override = CONCRETE
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.9, 4)
	lamp.light_color = Color(1, .82, .58)
	lamp.light_energy = 2.0
	lamp.omni_range = 10.0
	add_child(lamp)
