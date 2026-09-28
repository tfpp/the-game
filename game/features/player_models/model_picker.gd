extends CanvasLayer
## Lets a player pick their avatar's body model: the original "default" build or the
## "girl" variant (narrower shoulders and waist, wider hips, longer hair). Opens from
## the Esc menu, like Controls. The choice is server-validated and replicated by
## `PlayerModels` (see `player_models.gd`), so every peer draws the same silhouette
## for everyone, the same way clothing already works.

const MODAL_GROUP := &"modal_ui"
const ESC_MENU_GROUP := &"esc_menu_links"
const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const OPTIONS: Array[Dictionary] = [
	{"id": "default", "label": "Default"},
	{"id": "girl", "label": "Girl"},
]

var _panel: Control
var _preview: InventoryPreview
var _buttons: Dictionary = {}


func _ready() -> void:
	layer = 9
	add_to_group(ESC_MENU_GROUP)
	_build()


func _process(_delta: float) -> void:
	if _panel.visible:
		_refresh()


func _input(event: InputEvent) -> void:
	if _panel.visible and event.is_action_pressed(&"release_mouse"):
		get_viewport().set_input_as_handled()
		_close()


func esc_menu_label() -> String:
	return "Character Model"


func esc_menu_open() -> void:
	_panel.visible = true
	add_to_group(MODAL_GROUP)
	Controls.pause()
	_refresh()


func _close() -> void:
	_panel.visible = false
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	_preview.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	Controls.start()


func _select(body_type: String) -> void:
	var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
	if models == null:
		return
	models.request_body_type.rpc_id(1, body_type)


func _refresh() -> void:
	var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
	var peer := multiplayer.get_unique_id()
	var current := models.type_for(peer) if models != null else "default"
	for option: Dictionary in OPTIONS:
		(_buttons[option["id"]] as Button).button_pressed = current == option["id"]
	_preview.model.set_body_type(current)
	var hand := Hand.for_peer(get_tree(), peer)
	var shirt := ""
	var pants := ""
	if hand != null:
		_preview.model.set_skin_index(hand.skin_tone_index())
		shirt = hand.inventory().shirt
		pants = hand.inventory().pants
	_preview.show_clothing(shirt, pants)


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.06, 0.08, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.theme = UI_THEME
	backdrop.visible = false
	add_child(backdrop)
	_panel = backdrop
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var box_panel := PanelContainer.new()
	box_panel.custom_minimum_size.x = 400.0
	center.add_child(box_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box_panel.add_child(box)
	var heading := Label.new()
	heading.text = "Character Model"
	heading.theme_type_variation = &"HeadingLabel"
	box.add_child(heading)
	var status := Label.new()
	status.text = "Pick your avatar's body model. Everyone sees your choice."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	_preview = InventoryPreview.new()
	_preview.custom_minimum_size.y = 220
	box.add_child(_preview)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 10)
	options.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(options)
	for option: Dictionary in OPTIONS:
		var button := Button.new()
		button.text = option["label"]
		button.theme_type_variation = &"SecondaryButton"
		button.toggle_mode = true
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		button.custom_minimum_size.y = 48
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select.bind(option["id"]))
		options.add_child(button)
		_buttons[option["id"]] = button
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"SecondaryButton"
	close.custom_minimum_size.y = 40
	close.pressed.connect(_close)
	box.add_child(close)
