extends Node3D
## Playable cohesive vertical level, separate from the live casino.

const Layout := preload("res://features/procedural_rooms/world_layout.gd")
const PLAYER := preload("res://core/player/player.tscn")
const CONCRETE := preload("res://features/procedural_rooms/materials/concrete.tres")
const ASPHALT := preload("res://features/procedural_rooms/materials/asphalt.tres")
const SKY_SHADER := preload("res://features/procedural_rooms/materials/storm_sky.gdshader")
@export var layout_seed := 73021
## Bottom (B5) to top (B1); omitted rules use the garage defaults.
@export var floor_population: Array[ProceduralPopulationRule] = []
var player: Player
var level: Node3D
var _hud: Label


func _ready() -> void:
	level = Layout.build(self, layout_seed, floor_population)
	(level.get_node("Structure/Floor") as MeshInstance3D).material_override = CONCRETE
	_add_ground()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY_SHADER
	sky.sky_material = sky_material
	environment.environment.sky = sky
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d8e6ee")
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 0.8
	add_child(sun)
	player = PLAYER.instantiate() as Player
	player.position = Vector3(0, 17, 5)
	player.yaw = 0
	add_child(player)
	Controls.apply_scheme(Controls.Scheme.RIGHT_HANDED)
	Controls.playing = true
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud = Label.new()
	_hud.position = Vector2(22, 18)
	_hud.add_theme_font_size_override("font_size", 20)
	canvas.add_child(_hud)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _add_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(220, 220)
	ground.mesh = plane
	ground.material_override = ASPHALT
	ground.position = Vector3(0, -0.12, 21)
	add_child(ground)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = plane.create_trimesh_shape()
	body.add_child(collider)
	ground.add_child(body)


func _process(_delta: float) -> void:
	var stop := nearby_lift()
	_hud.text = (
		"GOLDEN CROWN / SERVICE GARAGE\nWASD / mouse / Space jump / Esc release\n"
		+ "West: ramps   East: stairs   B5: sewer + pump station\n"
		+ "R: new garage population / Seed %d" % layout_seed
	)
	if stop != null:
		_hud.text += "\n[E] " + str(stop.call("interaction_text"))
	elif nearby_door() != null:
		_hud.text += "\n[E] Open / close door"


func nearby_lift() -> Node3D:
	for stop: Node3D in get_tree().get_nodes_in_group(&"world_lift_controls"):
		if (stop.global_position + Vector3.UP).distance_to(player.global_position) < 2.5:
			return stop
	return null


func nearby_door() -> ProceduralSlidingDoor:
	for door: ProceduralSlidingDoor in get_tree().get_nodes_in_group(&"prototype_doors"):
		if (door.global_position + Vector3.UP).distance_to(player.global_position) < 2.5:
			return door
	return null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
			layout_seed += 1
			Layout.repopulate(level, layout_seed, floor_population)
		if event.keycode == KEY_E and Controls.gameplay_active():
			var stop := nearby_lift()
			if stop != null:
				stop.call("use")
			elif nearby_door() != null:
				nearby_door().use()
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			Controls.playing = false
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Controls.playing = true
