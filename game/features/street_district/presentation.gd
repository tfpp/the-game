extends RefCounted

const SKY_SHADER := preload("res://features/procedural_rooms/materials/storm_sky.gdshader")


static func add(parent: Node3D) -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ShaderMaterial.new()
	material.shader = SKY_SHADER
	sky.sky_material = material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a9bac6")
	environment.ambient_light_energy = .65
	world.environment = environment
	parent.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -30, 0)
	sun.light_color = Color("c3ced7")
	sun.light_energy = .65
	sun.shadow_enabled = true
	parent.add_child(sun)
