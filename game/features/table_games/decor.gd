extends Node3D
## Static furnishings stream with the rooms; all geometry and paint reuse existing props.
const PLANT := preload("res://features/hotel_props/props/potted_plant.tscn")
const SOFA := preload("res://features/casino_props/props/leather_sofa.tscn")
const COFFEE_TABLE := preload("res://features/casino_props/props/coffee_table.tscn")
const ART := preload("res://features/hotel_props/props/framed_art.tscn")
const CLOCK := preload("res://features/casino_props/props/wall_clock.tscn")
const SCONCE := preload("res://features/casino_props/props/wall_sconce.tscn")
const ASHTRAY := preload("res://features/casino_props/props/glass_ashtray.tscn")


func _ready() -> void:
	for x: float in [-12, 0, 12]:
		var room := Node3D.new()
		room.name = "Lounge%d" % int(x)
		room.position.x = x
		add_child(room)
		for corner: Vector2 in [
			Vector2(-4.6, -4.75), Vector2(4.6, -4.75), Vector2(-4.6, 4.75), Vector2(4.6, 4.75)
		]:
			var plant_at := Vector3(corner.x, 0, corner.y)
			if x == 0 and corner == Vector2(-4.6, -4.75):
				plant_at.z = 2.5
			_place(room, PLANT, plant_at)
		_place(room, SOFA, Vector3(2.5, 0, -5.3))
		_place(room, COFFEE_TABLE, Vector3(2.5, 0, -3.9))
		_place(room, ASHTRAY, Vector3(2.5, .4625, -3.9))
		_place(room, ART, Vector3(2.5, 1.65, -5.87))
		_place(room, ART, Vector3(-2.5, 1.8, -5.87))
		_place(room, CLOCK, Vector3(0, 2.5, -5.86))
		for side: float in [-1, 1]:
			_place(room, SCONCE, Vector3(side * 3.8, 2.3, -5.86))
			var light := OmniLight3D.new()
			light.position = Vector3(side * 3.8, 2.5, -5.5)
			light.light_color = Color("ffd0a0")
			light.light_energy = .45
			light.omni_range = 4.5
			light.shadow_enabled = false
			room.add_child(light)


func _place(parent: Node3D, prefab: PackedScene, at: Vector3) -> void:
	var prop := prefab.instantiate() as Node3D
	prop.position = at
	parent.add_child(prop)
