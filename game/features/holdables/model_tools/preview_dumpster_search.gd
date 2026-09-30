extends Node3D
## Native model preview exercises server-approved search presence and the live lid.

const DUMPSTER := preload("res://features/slum_alley/dumpster.tscn")
const LOOT := preload("res://features/loot/loot_container.tscn")
const PLAYER := preload("res://core/player/player.tscn")
var _loot: LootContainer
var _label: Label
var _keepalive_in := 0.0


func _ready() -> void:
	get_tree().root.size = Vector2i(900, 650)
	var dumpster := DUMPSTER.instantiate() as Node3D
	add_child(dumpster)
	_loot = LOOT.instantiate() as LootContainer
	_loot.name = "Loot"
	_loot.noun = "dumpster"
	dumpster.add_child(_loot)
	var player := PLAYER.instantiate() as Player
	player.name = "1"
	player.position = Vector3(0, 0, 2)
	add_child(player)
	player.set_physics_process(false)
	player.hide()
	var camera := Camera3D.new()
	camera.fov = 45
	camera.position = Vector3(3.6, 3.2, 4.8)
	add_child(camera)
	camera.look_at(Vector3(0, 1.2, 0))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("202a32")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b7c6d3")
	environment.environment.ambient_light_energy = .65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.shadow_enabled = true
	add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("394650")
	ground.material_override = material
	add_child(ground)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_label = Label.new()
	_label.position = Vector2(24, 22)
	_label.add_theme_font_size_override("font_size", 24)
	canvas.add_child(_label)
	if not OS.get_cmdline_user_args().is_empty():
		_capture.call_deferred()


func _process(delta: float) -> void:
	_label.text = (
		"DUMPSTER / " + ("ACTIVELY SEARCHING" if _loot.net_active_searchers > 0 else "CLOSED")
	)
	_label.text += "\nSpace: start / stop search"
	_keepalive_in -= delta
	if _loot.net_active_searchers > 0 and _keepalive_in <= 0:
		_keepalive_in = .75
		_loot.request_keep_searching()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if _loot.net_active_searchers > 0:
			_loot.request_stop_searching()
		else:
			_loot.request_search()


func _capture() -> void:
	var folder := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(folder)
	await get_tree().create_timer(.2).timeout
	await RenderingServer.frame_post_draw
	var closed := get_viewport().get_texture().get_image()
	assert(closed.save_png(folder.path_join("dumpster-closed.png")) == OK)
	_loot.request_search()
	await get_tree().create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	assert(
		is_equal_approx(
			(_loot.get_node("../Model/Hinge") as Node3D).rotation_degrees.x,
			DumpsterVisual.OPEN_ANGLE
		)
	)
	var opened := get_viewport().get_texture().get_image()
	assert(opened.save_png(folder.path_join("dumpster-searching.png")) == OK)
	_loot.request_stop_searching()
	await get_tree().create_timer(.6).timeout
	await RenderingServer.frame_post_draw
	assert(is_zero_approx((_loot.get_node("../Model/Hinge") as Node3D).rotation.x))
	var sheet := Image.create(1800, 650, false, Image.FORMAT_RGBA8)
	sheet.blit_rect(closed, Rect2i(0, 0, 900, 650), Vector2i.ZERO)
	sheet.blit_rect(opened, Rect2i(0, 0, 900, 650), Vector2i(900, 0))
	assert(sheet.save_png(folder.path_join("dumpster-search-animation.png")) == OK)
	print("DUMPSTER_SEARCH_CAPTURE PASS")
	get_tree().quit()
