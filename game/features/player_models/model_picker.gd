extends CanvasLayer
## Lets a player mix and match their avatar's body, head and tail, independently, like
## an impossible creature. Body is the original "default" build, the "girl" variant
## (narrower shoulders and waist, wider hips, longer hair) or the full "penguin"
## costume (its own fixed head, ignoring the head choice below). Head is a "human"
## face, a "frog" face or a "bird" beak. Tail is "none", a "lizard" tail, a fish
## "fin" or a "fluffy" tail. Opens from the Esc menu, like Controls. Each choice is
## server-validated and replicated by `PlayerModels` (see `player_models.gd`), so
## every peer draws the same combination for everyone, the same way clothing already
## works.

const MODAL_GROUP := &"modal_ui"
const ESC_MENU_GROUP := &"esc_menu_links"
const UI_THEME := preload("res://ui/theme/ui_theme.tres")

## Each row's `id` selects the matching `PlayerModels`/`BlockPlayerModel` calls in
## `_select` and `_refresh` below.
const ROWS: Array[Dictionary] = [
	{
		"id": "body",
		"label": "Body",
		"options":
		[
			{"id": "default", "label": "Default"},
			{"id": "girl", "label": "Girl"},
			{"id": "penguin", "label": "Penguin"},
		],
	},
	{
		"id": "head",
		"label": "Head",
		"options":
		[
			{"id": "human", "label": "Human"},
			{"id": "frog", "label": "Frog"},
			{"id": "bird", "label": "Bird"},
		],
	},
	{
		"id": "tail",
		"label": "Tail",
		"options":
		[
			{"id": "none", "label": "None"},
			{"id": "lizard", "label": "Lizard"},
			{"id": "fin", "label": "Fin"},
			{"id": "fluffy", "label": "Fluffy"},
		],
	},
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


func _select(row_id: String, option_id: String) -> void:
	var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
	if models == null:
		return
	match row_id:
		"body":
			models.request_body_type.rpc_id(1, option_id)
		"head":
			models.request_head_type.rpc_id(1, option_id)
		"tail":
			models.request_tail_type.rpc_id(1, option_id)


func _refresh() -> void:
	var models := get_tree().get_first_node_in_group(&"player_models") as PlayerModels
	var peer := multiplayer.get_unique_id()
	var body := models.type_for(peer) if models != null else "default"
	var head := models.type_for_head(peer) if models != null else "human"
	var tail := models.type_for_tail(peer) if models != null else "none"
	_set_row("body", body)
	_set_row("head", head)
	_set_row("tail", tail)
	_preview.model.set_body_type(body)
	_preview.model.set_head_type(head)
	_preview.model.set_tail_type(tail)
	var hand := Hand.for_peer(get_tree(), peer)
	var shirt := ""
	var pants := ""
	if hand != null:
		_preview.model.set_skin_index(hand.skin_tone_index())
		shirt = hand.inventory().shirt
		pants = hand.inventory().pants
	_preview.show_clothing(shirt, pants)


func _set_row(row_id: String, current: String) -> void:
	var buttons: Dictionary = _buttons[row_id]
	for option_id: String in buttons:
		(buttons[option_id] as Button).button_pressed = current == option_id


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
	box_panel.custom_minimum_size.x = 440.0
	center.add_child(box_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box_panel.add_child(box)
	var heading := Label.new()
	heading.text = "Character Model"
	heading.theme_type_variation = &"HeadingLabel"
	box.add_child(heading)
	var status := Label.new()
	status.text = "Mix and match a body, head and tail. Everyone sees your choice."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	_preview = InventoryPreview.new()
	_preview.custom_minimum_size.y = 200
	box.add_child(_preview)
	for row: Dictionary in ROWS:
		var row_id: String = row["id"]
		var row_label := Label.new()
		row_label.text = row["label"]
		box.add_child(row_label)
		var options := HBoxContainer.new()
		options.add_theme_constant_override("separation", 8)
		options.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_child(options)
		var buttons: Dictionary = {}
		for option: Dictionary in row["options"]:
			var button := Button.new()
			button.text = option["label"]
			button.theme_type_variation = &"SecondaryButton"
			button.toggle_mode = true
			button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
			button.custom_minimum_size.y = 44
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(_select.bind(row_id, option["id"]))
			options.add_child(button)
			buttons[option["id"]] = button
		_buttons[row_id] = buttons
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"SecondaryButton"
	close.custom_minimum_size.y = 40
	close.pressed.connect(_close)
	box.add_child(close)
