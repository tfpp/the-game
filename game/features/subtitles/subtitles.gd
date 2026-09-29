class_name Subtitles
extends CanvasLayer
## Movie-style subtitles: NPC dialogue shows as a line of text at the bottom centre of
## the screen, "Speaker: line", for a few seconds. Purely local presentation: the NPC
## decides who hears a line (usually only the player who talked) and calls
## `Subtitles.say()` on that peer. A new line replaces the current one.

const GROUP := &"subtitles"
const BASE_S := 2.5
const PER_CHAR_S := 0.05
const MAX_S := 7.0
const FADE_S := 0.3
const MAX_WIDTH := 900.0
const BOTTOM_MARGIN := 0.12

var _panel: PanelContainer
var _label: RichTextLabel
var _timer := 0.0


## Shows `text` from `speaker` on this peer's screen, if the subtitles feature is loaded.
static func say(tree: SceneTree, speaker: String, text: String) -> void:
	if tree == null:
		return
	var node := tree.get_first_node_in_group(GROUP) as Subtitles
	if node != null:
		node.show_line(speaker, text)


## Seconds a line stays up: long enough to read, never forever.
static func duration_for(text: String) -> float:
	return minf(BASE_S + PER_CHAR_S * text.length(), MAX_S)


## The line as displayed (BBCode), with the speaker name tinted gold.
static func format_line(speaker: String, text: String) -> String:
	var body := text.replace("[", "[lb]")
	if speaker.is_empty():
		return body
	return "[color=#f2c14e]%s:[/color] %s" % [speaker.replace("[", "[lb]"), body]


func _ready() -> void:
	layer = 5
	add_to_group(GROUP)
	var anchor := Control.new()
	anchor.name = "Control"
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.55)
	box.set_corner_radius_all(4)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", box)
	_panel.visible = false
	anchor.add_child(_panel)
	_label = RichTextLabel.new()
	_label.name = "Line"
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 24)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_panel.add_child(_label)
	get_viewport().size_changed.connect(_layout)


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_timer -= delta
	_panel.modulate.a = clampf(_timer / FADE_S, 0.0, 1.0)
	if _timer <= 0.0:
		_panel.visible = false


func show_line(speaker: String, text: String) -> void:
	_label.text = format_line(speaker, text)
	_timer = duration_for(text)
	_panel.modulate.a = 1.0
	_panel.visible = true
	_layout()


func is_showing() -> bool:
	return _panel.visible


func current_text() -> String:
	return _label.get_parsed_text()


func _layout() -> void:
	var screen := get_viewport().get_visible_rect().size
	var width := minf(MAX_WIDTH, screen.x * 0.9)
	_label.custom_minimum_size.x = width - 28.0
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -width * 0.5
	_panel.offset_right = width * 0.5
	_panel.offset_top = -screen.y * BOTTOM_MARGIN
	_panel.offset_bottom = -screen.y * BOTTOM_MARGIN
