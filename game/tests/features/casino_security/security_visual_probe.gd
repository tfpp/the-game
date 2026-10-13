extends Node
## Opt-in native-render review of the Golden Crown bouncers. From game/ with a display:
##   godot --audio-driver Dummy --rendering-method gl_compatibility --resolution 1100x750 \
##     res://tests/features/casino_security/security_visual_probe.tscn -- --offline
## Runs a real detention of the local player (a made-up firearm offence in the pit)
## and writes /tmp/security-<moment>.png: a posted guard up close, the guard on its
## way, the lift, the carry seen from outside and first person, the throw at the metro
## doors and the landing on a metro platform.

var _player: Player
var _camera := Camera3D.new()
var _third: Node

@onready var _security: CasinoSecurity = $Game/Features/casino_security


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	while _player == null:
		await get_tree().process_frame
		_player = get_tree().get_first_node_in_group(&"local_player") as Player
	Controls.start()
	for layer: Node in get_tree().get_nodes_in_group(&"modal_ui"):
		layer.queue_free()
	var day := $Game/Features/day_night as DayNight
	day.set_process(false)
	day._apply(0.5)
	_third = get_tree().get_first_node_in_group(&"third_person_camera")
	add_child(_camera)
	while not _security.grid.is_ready():
		await get_tree().physics_frame
	var guard := _security.guards()[2]
	await _shot("posted", guard.post + Vector3(-2.2, 1.7, 0.6), guard.post + Vector3(0, 1.3, 0))
	await _shot("posted-back", guard.post + Vector3(1.8, 1.6, 0.9), guard.post + Vector3(0, 1.2, 0))
	_player.server_teleport.rpc_id(1, Vector3(9.8, -0.3, 4.5), PI * 0.5)
	await get_tree().create_timer(0.5).timeout
	_third.set("enabled", true)
	_security.report_misconduct(1, &"firearm")
	await get_tree().create_timer(1.2).timeout
	await _follow("responding", Vector3(-3.5, 2.6, 4.5))
	while _security.phase_for(1) != SecurityRules.Phase.CARRIED:
		await get_tree().process_frame
	await get_tree().create_timer(0.55).timeout
	await _follow("lift", Vector3(-2.2, 1.0, 2.6))
	var carrier := _security.guard_for(1)
	while carrier.net_state != SecurityRules.GuardState.CARRYING or carrier.position.y < -0.05:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	await _follow("carry", Vector3(2.4, 1.8, 2.8))
	await _follow("carry-front", Vector3(0.4, 1.6, -3.0))
	await _follow("carry-side", Vector3(-3.6, 1.5, 0.3))
	_third.set("enabled", false)
	(_player.get_node("Camera") as Camera3D).make_current()
	await get_tree().create_timer(0.3).timeout
	await _save("carry-first-person")
	_third.set("enabled", true)
	var busy := _security.guard_for(1)
	while busy.net_state != SecurityRules.GuardState.THROWING:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await _shot("throw", Vector3(-8.4, 2.4, 13.6), Vector3(-12, 1.0, 19.0))
	await get_tree().create_timer(0.3).timeout
	await _shot("flight", Vector3(-8.4, 2.4, 13.6), Vector3(-12, 1.0, 19.0))
	_third.set("enabled", false)
	(_player.get_node("Camera") as Camera3D).make_current()
	while _security.phase_for(1) != SecurityRules.Phase.LANDED:
		await get_tree().process_frame
	await get_tree().create_timer(1.8).timeout
	await _save("landed")
	print("SECURITY_LANDED at ", _player.global_position)
	print("SECURITY_CAPTURE_PASS")
	get_tree().quit()


func _shot(moment: String, from: Vector3, at: Vector3) -> void:
	_camera.global_position = from
	_camera.look_at(at)
	_camera.make_current()
	await get_tree().create_timer(0.4).timeout
	await _save(moment)


## A camera offset from the busy guard, looking at it.
func _follow(moment: String, offset: Vector3) -> void:
	var guard := _security.guard_for(1)
	var basis := Basis(Vector3.UP, guard.rotation.y)
	_camera.global_position = guard.global_position + basis * offset
	_camera.look_at(guard.global_position + Vector3.UP * 1.3)
	_camera.make_current()
	await RenderingServer.frame_post_draw
	await _save(moment)


func _save(moment: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/security-%s.png" % moment)
