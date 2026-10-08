class_name DrunkView
extends Node
## Local-only presentation of the local player's intoxication: swaying view and aim,
## weaving steps and sideways stumbles, double vision, and the blackout fade. It reads
## replicated state (BarCompanion intoxication, Booze blackout phase) and changes
## only this client's own camera, view angles and client-authoritative movement.

const SHADER := preload("res://features/booze/drunk_screen.gdshader")
## Below the HUD and menus, above the 3D world and first-person hands.
const SCREEN_LAYER := 0
## Above HUD/subtitles/touch controls, below the death screen (20) and menus.
const BLACKOUT_LAYER := 19
## How fast the effect level follows intoxication (per second): seconds, not a snap.
const EASE_PER_S := 0.2

## Current eased effect strength, 0 sober … 1 hammered.
var level := 0.0
## Current local screen darkness, 0 clear … 1 black.
var darkness := 0.0
var _time := 0.0
var _last_sway := Vector2.ZERO
var _stumble_in := 3.0
var _stumble_side := 1.0
var _pinned: Player
var _pin := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _effect := ColorRect.new()
var _material := ShaderMaterial.new()
var _black := ColorRect.new()
var _caption := Label.new()

@onready var booze: Booze = get_parent() as Booze


func _ready() -> void:
	# After Player (0) and the third-person camera (10) place the camera; before
	# held items (15-20) and the first-person view (30) copy it.
	process_priority = 12
	# After the local Player's own physics step.
	process_physics_priority = 1
	_rng.randomize()
	var screen := CanvasLayer.new()
	screen.name = "DrunkScreen"
	screen.layer = SCREEN_LAYER
	add_child(screen)
	_material.shader = SHADER
	_effect.name = "DoubleVision"
	_effect.material = _material
	_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_effect.visible = false
	screen.add_child(_effect)
	var dark := CanvasLayer.new()
	dark.name = "Blackout"
	dark.layer = BLACKOUT_LAYER
	add_child(dark)
	_black.name = "Black"
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.visible = false
	dark.add_child(_black)
	_caption.name = "Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 30)
	_caption.add_theme_color_override("font_color", Color(0.93, 0.88, 0.78))
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.offset_left = 24
	_caption.offset_right = -24
	_black.add_child(_caption)


func _process(delta: float) -> void:
	_time += delta
	var player := _local_player()
	var peer := multiplayer.get_unique_id()
	var phase := booze.phase_for(peer) if player != null else BoozeRules.Phase.NONE
	var elapsed := booze.phase_elapsed(peer)
	level = move_toward(level, BoozeRules.intensity(_drinks(peer)), delta * EASE_PER_S)
	darkness = BoozeRules.darkness(phase, elapsed)
	_update_screen(phase, elapsed)
	if player == null or get_viewport().use_xr:
		_last_sway = Vector2.ZERO
		return
	_sway_aim(player, phase)
	_tilt_camera(player)


func _physics_process(delta: float) -> void:
	var player := _local_player()
	if player == null:
		_pinned = null
		return
	var phase := booze.phase_for(multiplayer.get_unique_id())
	if phase != BoozeRules.Phase.NONE:
		_hold(player, phase)
		return
	if _pinned != null:
		_pinned = null
		Controls.clear_input()
	_stagger(player, delta)


## Keeps a collapsing/blacked-out player on the spot (gravity still lands a fall
## during the collapse) while accepting server teleports such as the metro drop-off.
func _hold(player: Player, phase: int) -> void:
	var at := player.global_position
	if _pinned != player or at.distance_to(_pin) > 0.75:
		_pinned = player
		_pin = at
	else:
		if phase == BoozeRules.Phase.COLLAPSE and at.y < _pin.y:
			_pin.y = at.y
		player.global_position = _pin
	var fall := minf(player.velocity.y, 0.0) if phase == BoozeRules.Phase.COLLAPSE else 0.0
	player.velocity = Vector3(0, fall, 0)
	player.net_position = player.global_position
	player.net_velocity = player.velocity


func _stagger(player: Player, delta: float) -> void:
	if level < BoozeRules.VEER_LEVEL or not Controls.gameplay_active() or not player.is_on_floor():
		return
	player.velocity = stagger(player.velocity, player.yaw, delta)


## Weaves walking off course and adds the odd sideways stumble (ground only).
func stagger(velocity: Vector3, yaw: float, delta: float) -> Vector3:
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.5:
		flat = flat.rotated(BoozeRules.veer_rate(_time, level) * delta)
	_stumble_in -= delta
	if _stumble_in <= 0.0:
		_stumble_in = BoozeRules.stumble_interval(level, _rng.randf())
		_stumble_side = -_stumble_side if _rng.randf() < 0.7 else _stumble_side
		var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		flat += Vector2(right.x, right.z) * _stumble_side * BoozeRules.stumble_speed(level)
	return Vector3(flat.x, velocity.y, flat.y)


func _sway_aim(player: Player, phase: int) -> void:
	var sway := BoozeRules.aim_sway(_time, level)
	if Controls.gameplay_active() and phase == BoozeRules.Phase.NONE:
		player.yaw += sway.x - _last_sway.x
		player.pitch = clampf(
			player.pitch + sway.y - _last_sway.y, deg_to_rad(-89.0), deg_to_rad(89.0)
		)
	_last_sway = sway


func _tilt_camera(player: Player) -> void:
	var camera := player.get_node_or_null("Camera") as Camera3D
	if camera == null or not camera.current:
		return
	var view := camera.global_transform
	view.basis = view.basis * Basis(Vector3.BACK, BoozeRules.camera_roll(_time, level))
	var peer := player.get_multiplayer_authority()
	var lying := booze.lying_weight(peer)
	var body := player.get_node_or_null("Body") as Node3D
	if lying > 0.0 and body != null and not body.visible:
		var origin := player.get_global_transform_interpolated().origin
		var eye := BoozeRules.lying_eye(
			origin,
			booze.lying_yaw(peer, player.yaw),
			player.movement.hull_height_m(),
			Booze.standing_height(player)
		)
		view = view.interpolate_with(eye, smoothstep(0.0, 1.0, lying))
	camera.global_transform = view


func _update_screen(phase: int, elapsed: float) -> void:
	var strength := BoozeRules.screen_strength(level)
	_effect.visible = strength > 0.02
	if _effect.visible:
		_material.set_shader_parameter("strength", strength)
		_material.set_shader_parameter("time_s", _time)
	_black.visible = darkness > 0.001
	_black.color = Color(0, 0, 0, darkness)
	_caption.text = BoozeRules.caption(phase, elapsed)


func _drinks(peer: int) -> float:
	for node: Node in get_tree().get_nodes_in_group(&"bar_companion"):
		var bar := node as BarCompanion
		if bar != null and bar.multiplayer == multiplayer:
			return float(bar.intoxication_for(peer))
	return 0.0


func _local_player() -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"local_player"):
		var player := node as Player
		if (
			player != null
			and player.multiplayer == multiplayer
			and not player.is_queued_for_deletion()
		):
			return player
	return null
