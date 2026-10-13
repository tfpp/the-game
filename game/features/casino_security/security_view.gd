class_name SecurityView
extends Node
## Local presentation for a detained player: holds them still while a guard comes
## over, pins their (client-authoritative) capsule to the guard's shoulder while
## carried, looks out from their dangling head in first person, and fades the
## screen through the throw. Reads only replicated CasinoSecurity state.

## Above HUD/subtitles/touch controls, below the death screen (20) and menus.
const LAYER := 19

var darkness := 0.0
var _pinned: Player
var _pin := Vector3.ZERO
var _was_detained := false
var _layer := CanvasLayer.new()
var _black := ColorRect.new()
var _caption := Label.new()

@onready var security: CasinoSecurity = get_parent() as CasinoSecurity


func _ready() -> void:
	# After Player (0) and the third-person camera (10) place the camera; before
	# held items (15-20) and the first-person view (30) copy it.
	process_priority = 12
	# After the local Player's own physics step.
	process_physics_priority = 1
	_layer.name = "SecurityScreen"
	_layer.layer = LAYER
	add_child(_layer)
	_black.name = "Black"
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_black)
	_caption.name = "Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 26)
	_caption.add_theme_color_override("font_color", Color("e8c766"))
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.offset_top = 90
	_caption.offset_left = 24
	_caption.offset_right = -24
	_layer.add_child(_caption)
	_layer.visible = false


func _process(_delta: float) -> void:
	var peer := multiplayer.get_unique_id()
	var player := _local_player()
	var phase := security.phase_for(peer) if player != null else SecurityRules.Phase.NONE
	var elapsed := security.phase_elapsed(peer)
	darkness = SecurityRules.darkness(phase, elapsed)
	_layer.visible = phase != SecurityRules.Phase.NONE
	if _layer.visible:
		_black.color = Color(0, 0, 0, darkness)
		_caption.text = SecurityRules.caption(phase, security.offence_for(peer))
		# Centred on the black screen, otherwise near the top, clear of subtitles.
		var dark := darkness > 0.5
		_caption.vertical_alignment = (
			VERTICAL_ALIGNMENT_CENTER if dark else VERTICAL_ALIGNMENT_TOP
		)
		_caption.offset_top = 0 if dark else 90
	if player != null and not get_viewport().use_xr:
		_look_from_head(player, peer)


func _physics_process(_delta: float) -> void:
	var player := _local_player()
	var peer := multiplayer.get_unique_id()
	var phase := security.phase_for(peer) if player != null else SecurityRules.Phase.NONE
	if phase == SecurityRules.Phase.NONE or phase == SecurityRules.Phase.LANDED:
		if _was_detained:
			_was_detained = false
			_pinned = null
			Controls.clear_input()
		return
	_was_detained = true
	if phase == SecurityRules.Phase.CARRIED:
		var body: Variant = security.body_transform(peer)
		if body != null:
			_place(player, (body as Transform3D).origin)
			_pinned = player
			_pin = player.global_position
			return
	_hold(player, phase)


## Keeps a held/thrown player on the spot (gravity still lands them while held)
## and accepts server teleports such as the metro drop-off.
func _hold(player: Player, phase: int) -> void:
	var at := player.global_position
	if _pinned != player or at.distance_to(_pin) > 0.75:
		_pinned = player
		_pin = at
	else:
		if phase == SecurityRules.Phase.HELD and at.y < _pin.y:
			_pin.y = at.y
		player.global_position = _pin
	var fall := minf(player.velocity.y, 0.0) if phase == SecurityRules.Phase.HELD else 0.0
	_place(player, player.global_position, fall)


func _place(player: Player, at: Vector3, fall: float = 0.0) -> void:
	player.global_position = at
	player.velocity = Vector3(0, fall, 0)
	player.net_position = at
	player.net_velocity = player.velocity


## First person while carried or thrown: the eye rides the dangling head.
func _look_from_head(player: Player, peer: int) -> void:
	var body := player.get_node_or_null("Body") as Node3D
	var camera := player.get_node_or_null("Camera") as Camera3D
	if body == null or camera == null or not camera.current or body.visible:
		return
	var drawn: Variant = security.body_transform(peer)
	if drawn == null:
		return
	var eye := SecurityRules.carried_eye(drawn as Transform3D)
	if security.phase_for(peer) == SecurityRules.Phase.THROWN:
		if security.phase_elapsed(peer) >= SecurityRules.FLIGHT_S:
			return
	camera.global_position = eye


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
