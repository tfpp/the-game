extends CanvasLayer
## The "Settings" entry in the Esc menu: a hub listing every settings page (Audio,
## Controls, ...), each opening in the same panel with a Back button. Esc (or the
## controller's B) steps back one level: page -> hub -> Esc menu.
##
## Features add a page by joining SETTINGS_PAGES_GROUP and implementing:
## - `settings_page_label() -> String`: the hub button and page heading.
## - `settings_page_build() -> Control`: fresh page content, built each time it opens
##   and freed when it closes.
## - optionally `settings_page_input(event: InputEvent) -> bool`: sees input first
##   while its page is open; return true to consume it (e.g. while capturing a key to
##   rebind).
## Persist preferences with `SettingsStore`.

const MODAL_GROUP := &"modal_ui"
## Nodes in this group get a link in the Esc menu (`ui/login/login_screen.gd`).
const ESC_MENU_GROUP := &"esc_menu_links"
const SETTINGS_PAGES_GROUP := &"settings_pages"
const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const PANEL_WIDTH := 640.0
## Tallest the scrolling page body gets, as a share of the window height.
const MAX_BODY_HEIGHT_RATIO := 0.7

var _backdrop: Control
var _heading: Label
var _scroll: ScrollContainer
var _body: VBoxContainer
var _back: Button
## The page node whose content is showing, or null on the hub.
var _page: Node


func _ready() -> void:
	layer = 9
	add_to_group(ESC_MENU_GROUP)
	_build()
	Controls.menu_requested.connect(_on_menu_requested)


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if _page != null and _page.has_method(&"settings_page_input"):
		if _page.settings_page_input(event):
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		go_back()


func _process(_delta: float) -> void:
	if is_open():
		_scroll.custom_minimum_size.y = minf(_body.get_combined_minimum_size().y, _body_height())


func esc_menu_label() -> String:
	return "Settings"


func esc_menu_open() -> void:
	open()


func is_open() -> bool:
	return _backdrop.visible


## Shows the hub.
func open() -> void:
	_backdrop.visible = true
	add_to_group(MODAL_GROUP)
	Controls.pause()
	show_hub()


## Hides the panel without resuming play (the caller decides what comes next).
func close() -> void:
	_clear_body()
	_page = null
	_backdrop.visible = false
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)


## One level up: from a page to the hub, from the hub back to the Esc menu.
func go_back() -> void:
	if _page != null:
		show_hub()
		return
	close()
	Controls.menu_requested.emit()


## Every registered page, alphabetically by label.
func pages() -> Array[Node]:
	var result: Array[Node] = get_tree().get_nodes_in_group(SETTINGS_PAGES_GROUP)
	result.sort_custom(func(a: Node, b: Node) -> bool: return _label_of(a) < _label_of(b))
	return result


func show_hub() -> void:
	_page = null
	_clear_body()
	_heading.text = "Settings"
	_back.text = "Back to menu"
	for page: Node in pages():
		var button := Button.new()
		button.text = _label_of(page)
		button.custom_minimum_size.y = 48
		button.pressed.connect(show_page.bind(page))
		_body.add_child(button)
	if pages().is_empty():
		var empty := Label.new()
		empty.text = "Nothing to set up yet."
		_body.add_child(empty)
	_focus_first.call_deferred()


func show_page(page: Node) -> void:
	_clear_body()
	_page = page
	_heading.text = _label_of(page)
	_back.text = "Back to settings"
	var content: Control = page.settings_page_build()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(content)
	_scroll.scroll_vertical = 0
	_focus_first.call_deferred()


## A controller Start press (or the touch pause button) while this is up opens the Esc
## menu on top, so step aside for it.
func _on_menu_requested() -> void:
	if is_open():
		close()


func _clear_body() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _label_of(page: Node) -> String:
	return str(page.settings_page_label())


func _body_height() -> float:
	return get_viewport().get_visible_rect().size.y * MAX_BODY_HEIGHT_RATIO


func _focus_first() -> void:
	if not is_open():
		return
	var target := _first_focusable(_body)
	(target if target != null else _back).grab_focus()


static func _first_focusable(node: Node) -> Control:
	for child: Node in node.get_children():
		var control := child as Control
		if control == null or not control.is_visible_in_tree():
			continue
		if control.focus_mode == Control.FOCUS_ALL:
			return control
		var nested := _first_focusable(control)
		if nested != null:
			return nested
	return null


func _build() -> void:
	_backdrop = ColorRect.new()
	(_backdrop as ColorRect).color = Color(0.05, 0.06, 0.08, 0.6)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.theme = UI_THEME
	_backdrop.visible = false
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
	_heading = Label.new()
	_heading.theme_type_variation = &"HeadingLabel"
	box.add_child(_heading)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(PANEL_WIDTH, 120.0)
	box.add_child(_scroll)
	# Keeps page content clear of the scrollbar.
	var gutter := MarginContainer.new()
	gutter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right", 18)
	_scroll.add_child(gutter)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	gutter.add_child(_body)
	_back = Button.new()
	_back.theme_type_variation = &"SecondaryButton"
	_back.custom_minimum_size.y = 40
	_back.pressed.connect(go_back)
	box.add_child(_back)
