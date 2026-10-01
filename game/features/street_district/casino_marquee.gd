extends Node3D
## Cosmetic chase lights; gameplay remains owned by the existing portal.

const TEXTURE := preload("res://assets/street_district/textures/casino_marquee.png")
var _groups: Array[StandardMaterial3D] = []
var _lights: Array[OmniLight3D] = []
var _red: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	for i: int in range(2):
		var material := StandardMaterial3D.new()
		material.albedo_texture = TEXTURE
		material.uv1_scale = Vector3(.42, .42, 1)
		material.uv1_offset = Vector3(.04, .54, 0)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		material.emission_enabled = true
		material.emission = Color("ffd378")
		_groups.append(material)
	var bulb := SphereMesh.new()
	bulb.radius = .045
	bulb.height = .09
	bulb.radial_segments = 6
	bulb.rings = 1
	for i: int in range(23):
		for y: float in [-.67, .67]:
			var node := MeshInstance3D.new()
			node.name = "Bulb%d%s" % [i, "Top" if y > 0 else "Bottom"]
			node.mesh = bulb
			node.material_override = _groups[i % 2]
			node.position = Vector3(-2.64 + i * .24, y, .23)
			add_child(node)
	_red = StandardMaterial3D.new()
	_red.albedo_texture = TEXTURE
	_red.uv1_scale = Vector3(.42, .42, 1)
	_red.uv1_offset = Vector3(.54, .54, 0)
	_red.emission_enabled = true
	_red.emission = Color("ff3324")
	_red.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	for y: float in [-.81, .81]:
		var strip := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(5.8, .035, .035)
		strip.mesh = box
		strip.position = Vector3(0, y, .17)
		strip.material_override = _red
		add_child(strip)
	for x: float in [-2.0, 2.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 0, .8)
		light.light_color = Color("ffd17e")
		light.omni_range = 5
		add_child(light)
		_lights.append(light)
	_process(0)


func _process(delta: float) -> void:
	_time += delta
	var phase := int(_time / .18) % 2
	for i: int in _groups.size():
		_groups[i].emission_energy_multiplier = 4.0 if i == phase else .35
	_red.emission_energy_multiplier = 1.8 + sin(_time * 3.5) * .7
	for light: OmniLight3D in _lights:
		light.light_energy = .5 + sin(_time * 3.5) * .15
