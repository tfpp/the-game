extends Node3D
## Static passage geometry, built only for players inside the streamed room.


func _ready() -> void:
	_box("Floor", Vector3(60, -0.25, 0), Vector3(128, 0.5, 8))
	_box("Ceiling", Vector3(60, 3.75, 0), Vector3(128, 0.5, 8))
	_box("NorthWall", Vector3(60, 1.75, -3.75), Vector3(128, 3.5, 0.5))
	_box("SouthWall", Vector3(60, 1.75, 3.75), Vector3(128, 3.5, 0.5))
	_box("WestEnd", Vector3(-3.75, 1.75, 0), Vector3(0.5, 3.5, 8))
	_box("EastEnd", Vector3(123.75, 1.75, 0), Vector3(0.5, 3.5, 8))
	for i in 16:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(i * 8, 2.8, 0)
		lamp.light_color = Color(1, 0.75, 0.4)
		lamp.omni_range = 10
		add_child(lamp)
		var sign := Label3D.new()
		sign.position = Vector3(i * 8, 2, 3.45)
		sign.rotation.y = PI
		sign.text = "GNOME EXPRESS\n4x running speed\n< North / South / East / West >"
		sign.font_size = 32
		add_child(sign)


func _box(node_name: String, pos: Vector3, dimensions: Vector3) -> void:
	var box := CSGBox3D.new()
	box.name = node_name
	box.position = pos
	box.size = dimensions
	box.use_collision = true
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 0.21, 0.12)
	material.roughness = 1.0
	box.material = material
	add_child(box)
