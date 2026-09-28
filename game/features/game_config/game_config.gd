class_name GameConfig
extends Node
## A "Game" page in the Esc menu's Settings (features/settings/) that tunes global
## gamestate knobs for the whole world: how high everyone jumps and how often frogs
## hop. Server-authoritative like every other shared value (game/AGENTS.md): clients
## ask for a change with a validated request RPC, the server clamps and applies it,
## and the result replicates back to every peer via the synchronizer in feature.tscn.
##
## Neither system is driven by this feature directly, so applying a change means
## reaching into the other feature's public state each frame: jump height scales
## the local player's own MovementConfig.jump_speed (movement is client-authoritative,
## so only the local player's copy matters), and frog hop rate/jump height scale
## each Frog's hop_rate_scale/jump_height_scale (server-only; frogs simulate hops
## only on the server).

const SETTINGS_PAGES_GROUP := &"settings_pages"

const JUMP_HEIGHT_RANGE := Vector3(0.5, 2.5, 0.1)
const FROG_HOP_RATE_RANGE := Vector3(0.4, 3.0, 0.1)
## Frogs used to hop at a fixed height; this multiplier defaults to 2x that so
## frogs hop noticeably higher out of the box, and can still be tuned per world.
const FROG_JUMP_HEIGHT_RANGE := Vector3(0.5, 4.0, 0.1)

## Replicated (server -> everyone). See the synchronizer config in feature.tscn.
@export var jump_height_scale := 1.0
@export var frog_hop_rate := 1.0
@export var frog_jump_height_scale := 2.0

## Default jump speed (Source units/s) a fresh MovementConfig carries, captured once
## so scaling never compounds across repeated applications.
var _base_jump_speed := 0.0


func _ready() -> void:
	add_to_group(SETTINGS_PAGES_GROUP)
	_base_jump_speed = MovementConfig.new().jump_speed


func _process(_delta: float) -> void:
	_apply_jump_height()
	if multiplayer.is_server():
		_apply_frog_scales()


func settings_page_label() -> String:
	return "Game"


func settings_page_icon() -> Texture2D:
	return preload("res://assets/kenney/game-icons/PNG/White/1x/wrench.png")


func settings_page_build() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	page.add_child(grid)
	_slider(grid, "Jump height", jump_height_scale, JUMP_HEIGHT_RANGE, request_jump_height_scale)
	_slider(grid, "Frog hop rate", frog_hop_rate, FROG_HOP_RATE_RANGE, request_frog_hop_rate)
	_slider(
		grid,
		"Frog jump height",
		frog_jump_height_scale,
		FROG_JUMP_HEIGHT_RANGE,
		request_frog_jump_height_scale
	)
	var note := Label.new()
	note.text = "These affect everyone in this world, not just you."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color(0.22, 0.25, 0.33, 0.75))
	page.add_child(note)
	return page


## Client -> server: ask for a new jump height multiplier.
@rpc("any_peer", "call_local", "reliable")
func request_jump_height_scale(value: float) -> void:
	if not _valid_request(value):
		return
	jump_height_scale = clampf(value, JUMP_HEIGHT_RANGE.x, JUMP_HEIGHT_RANGE.y)


## Client -> server: ask for a new frog hop rate multiplier.
@rpc("any_peer", "call_local", "reliable")
func request_frog_hop_rate(value: float) -> void:
	if not _valid_request(value):
		return
	frog_hop_rate = clampf(value, FROG_HOP_RATE_RANGE.x, FROG_HOP_RATE_RANGE.y)


## Client -> server: ask for a new frog jump height multiplier.
@rpc("any_peer", "call_local", "reliable")
func request_frog_jump_height_scale(value: float) -> void:
	if not _valid_request(value):
		return
	frog_jump_height_scale = clampf(value, FROG_JUMP_HEIGHT_RANGE.x, FROG_JUMP_HEIGHT_RANGE.y)


func _apply_jump_height() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"local_player"):
		var player := node as Player
		if player != null:
			player.movement.jump_speed = _base_jump_speed * jump_height_scale


func _apply_frog_scales() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"frogs"):
		var frog := node as Frog
		if frog != null:
			frog.hop_rate_scale = frog_hop_rate
			frog.jump_height_scale = frog_jump_height_scale


func _slider(
	grid: GridContainer, label: String, value: float, bounds: Vector3, request: Callable
) -> void:
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 140
	grid.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = bounds.x
	slider.max_value = bounds.y
	slider.step = bounds.z
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 28
	grid.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size.x = 48
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.text = "%.1fx" % value
	grid.add_child(readout)
	slider.value_changed.connect(
		func(next: float) -> void:
			readout.text = "%.1fx" % next
			request.rpc_id(1, next)
	)


func _valid_request(value: float) -> bool:
	if not multiplayer.is_server() or not is_finite(value):
		return false
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or sender == 1:
		return true
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if node is Player and node.name == str(sender) and not node.is_queued_for_deletion():
			return true
	return false
