extends Node3D
## Static room contents, instantiated by the shared StreamedRoom only on occupied clients.


func _ready() -> void:
	var floor_mat := _material(Color("162435"))
	var wall_mat := _material(Color("102d38"))
	var brass := _material(Color("b89550"))
	var neon := _material(Color("49ddce"), true)
	_box("Floor", Vector3(0, -0.15, 0), Vector3(15.4, 0.3, 12.4), floor_mat)
	_box("Ceiling", Vector3(0, 4.1, 0), Vector3(15.4, 0.2, 12.4), wall_mat)
	for z: float in [-6.0, 6.0]:
		_box("Wall", Vector3(0, 2, z), Vector3(15.4, 4, 0.25), wall_mat)
		_box("Rail", Vector3(0, 1.05, z * 0.97), Vector3(15, 0.06, 0.06), brass, false)
		_box("Neon", Vector3(0, 3.85, z * 0.97), Vector3(15, 0.035, 0.04), neon, false)
	for x: float in [-7.5, 7.5]:
		_box("Wall", Vector3(x, 2, 0), Vector3(0.25, 4, 12), wall_mat)
		_box("Rail", Vector3(x * 0.97, 1.05, 0), Vector3(0.06, 0.06, 12), brass, false)
	for x: int in range(-7, 8):
		_box("FloorLine", Vector3(x, 0.006, 0), Vector3(0.015, 0.005, 12), brass, false)
	for z: int in range(-5, 6):
		_box("FloorLine", Vector3(0, 0.006, z), Vector3(15, 0.005, 0.015), brass, false)
	for x: float in [-5.0, 0.0, 5.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 3.4, 0)
		light.light_color = Color("ffdfac")
		light.light_energy = 1.4
		light.omni_range = 8
		add_child(light)
	var sign := Label3D.new()
	sign.text = "THE ADVENTURE ROOM"
	sign.font_size = 72
	sign.pixel_size = 0.006
	sign.modulate = Color("f3d394")
	sign.position = Vector3(0, 3.45, -5.8)
	add_child(sign)


func _material(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	material.emission_enabled = glow
	material.emission = color
	return material


func _box(
	title: String, at: Vector3, size: Vector3, material: Material, solid: bool = true
) -> void:
	var box := CSGBox3D.new()
	box.name = title
	box.position = at
	box.size = size
	box.material = material
	box.use_collision = solid
	add_child(box)
