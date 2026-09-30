class_name GarbageCan
extends Node3D
## A dented casino trash can. Use it (E / B / Circle / USE) and confirm to throw away
## your held item and everything in your backpack. Worn clothes and keys stay.
## The confirmation panel is local; the server re-checks range and ownership.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const TRASH_ICON := preload("res://assets/kenney/game-icons/PNG/White/1x/trashcan.png")

var _dialog: CanvasLayer
var _confirm: Button
var _cancel: Button

@onready var entity: NetworkedInteraction = $NetworkedEntity


func _ready() -> void:
	add_to_group(&"interactables")
	entity.register_use(can_use, _empty, 0.5)
	Controls.menu_requested.connect(_close)
	Network.mode_changed.connect(func(_mode: Network.Mode) -> void: _close())


func can_use(player: Player) -> bool:
	if not entity.in_range(player):
		return false
	var hand := Hand.for_peer(get_tree(), player.get_multiplayer_authority())
	return hand != null and carried_count(hand.inventory()) > 0


func interaction_text() -> String:
	return "Empty inventory into the trash"


## Opens the confirmation. Nothing is thrown away until it is accepted.
func use() -> void:
	if _dialog == null:
		_build()
	_dialog.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	GameAudio.play_ui(self, &"open")
	_cancel.grab_focus()


func confirm() -> void:
	_close()
	entity.request_use()


func is_confirming() -> bool:
	return _dialog != null and _dialog.visible


static func carried_count(inventory: PlayerInventory) -> int:
	if inventory == null:
		return 0
	var count := 0 if inventory.hand().net_item_id.is_empty() else 1
	return count + inventory.backpack.size() - inventory.backpack.count("")


func _empty(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	var hand := Hand.for_peer(get_tree(), peer)
	if hand == null:
		return false
	var count := hand.inventory().clear_carried()
	if count <= 0:
		return false
	hand._play_inventory.rpc_id(peer, &"drop")
	var chat := get_tree().get_first_node_in_group(&"chat_box")
	if chat != null:
		chat.send_notice(peer, "Threw %d item%s in the trash" % [count, "" if count == 1 else "s"])
	return true


func _input(event: InputEvent) -> void:
	if not is_confirming() or event.is_echo():
		return
	if event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if not is_confirming():
		return
	_dialog.hide()
	remove_from_group(&"modal_ui")
	Controls.start()


func _build() -> void:
	_dialog = CanvasLayer.new()
	_dialog.layer = 9
	add_child(_dialog)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.05, 0.075, 0.8)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.theme = UI_THEME
	_dialog.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 280
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var icon := TextureRect.new()
	icon.texture = TRASH_ICON
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	box.add_child(icon)
	var title := Label.new()
	title.text = "EMPTY YOUR INVENTORY?"
	title.theme_type_variation = &"HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := Label.new()
	body.text = (
		"Your held item and every backpack item go in the trash for good."
		+ "\nWorn clothes and keys stay."
	)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 260
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_cancel = _button(buttons, "Cancel", _close)
	_confirm = _button(buttons, "Throw away", confirm)
	_dialog.hide()


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(120, 44)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
