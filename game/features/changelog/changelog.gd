extends CanvasLayer
## In-game feature changelog: open "Release notes" from the Esc menu (or press L) to see
## what's shipped, Esc or L again to close.
##
## The entries live in entries.gd so new features can add to the list without touching
## this script (see AGENTS.md for the rule that every new feature must add one). This
## is static, read-only content baked into the client, so it needs no server round trip.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const TOGGLE_ACTION := &"toggle_changelog"
const MODAL_GROUP := &"modal_ui"
## Nodes in this group get a link in the Esc menu (`ui/login/login_screen.gd`); they
## must implement `esc_menu_label() -> String` and `esc_menu_open() -> void`.
const ESC_MENU_GROUP := &"esc_menu_links"
const PANEL_WIDTH := 420.0
const PANEL_MAX_HEIGHT := 480.0

var _backdrop: Control


func _ready() -> void:
	Controls.ensure_action(TOGGLE_ACTION, [_key_event(KEY_L)])
	add_to_group(ESC_MENU_GROUP)
	_build()


func _input(event: InputEvent) -> void:
	if _is_open():
		if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(TOGGLE_ACTION):
			get_viewport().set_input_as_handled()
			_close()
		return
	if get_tree().get_first_node_in_group(MODAL_GROUP):
		return
	if event.is_action_pressed(TOGGLE_ACTION):
		get_viewport().set_input_as_handled()
		_open()


func esc_menu_label() -> String:
	return "Release notes"


func esc_menu_open() -> void:
	_open()


## One BBCode line for `entry`, tolerant of missing keys so a malformed entry can't
## crash the panel.
static func entry_line(entry: Dictionary) -> String:
	var title := str(entry.get("title", ""))
	var summary := str(entry.get("summary", ""))
	return "[b]%s[/b] — %s" % [title, summary]


## The full BBCode body, one line per entry, in the order given.
static func body_text(entries: Array[Dictionary]) -> String:
	var lines: Array[String] = []
	for entry: Dictionary in entries:
		lines.append(entry_line(entry))
	return "\n".join(lines)


func _open() -> void:
	add_to_group(MODAL_GROUP)
	_backdrop.visible = true


func _close() -> void:
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	_backdrop.visible = false


func _is_open() -> bool:
	return _backdrop.visible


func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.05, 0.06, 0.08, 0.6)
	_backdrop.visible = false
	_backdrop.theme = UI_THEME
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var heading := Label.new()
	heading.text = "What's new"
	heading.theme_type_variation = &"HeadingLabel"
	box.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_MAX_HEIGHT)
	box.add_child(scroll)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	body.add_theme_color_override("default_color", Color.WHITE)
	body.text = body_text(ChangelogEntries.ENTRIES)
	scroll.add_child(body)

	var footer := Label.new()
	footer.text = "Esc or L to close"
	footer.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	box.add_child(footer)


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
