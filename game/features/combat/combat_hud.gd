extends CanvasLayer
## Shows the local player's health in the bottom-right corner (the one HUD corner
## core/ui's HUD leaves free — see game/AGENTS.md's HUD corner layout) and a brief
## "You died" flash when combat.gd reports their death.

const DIED_FLASH_S := 2.0

var _health_label: Label
var _died_label: Label
var _died_timer := 0.0


func _ready() -> void:
	_health_label = _make_label(
		Control.PRESET_BOTTOM_RIGHT, Vector2(-160, -44), Color(0.95, 0.35, 0.35)
	)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_health_label)

	_died_label = _make_label(Control.PRESET_CENTER_TOP, Vector2(-100, 90), Color(1.0, 0.3, 0.3))
	_died_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_died_label.add_theme_font_size_override("font_size", 28)
	add_child(_died_label)

	var combat := get_parent() as Combat
	if combat != null:
		combat.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	var combat := get_parent() as Combat
	if combat != null:
		_health_label.text = "HP: %d" % int(combat.health_for(multiplayer.get_unique_id()))
	if _died_timer > 0.0:
		_died_timer -= delta
		if _died_timer <= 0.0:
			_died_label.text = ""


func _on_player_died(victim_peer: int, _attacker_peer: int) -> void:
	if victim_peer != multiplayer.get_unique_id():
		return
	_died_label.text = "You died"
	_died_timer = DIED_FLASH_S


func _make_label(preset: Control.LayoutPreset, offset: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(preset)
	label.position = offset
	label.size = Vector2(220, 36)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	return label
