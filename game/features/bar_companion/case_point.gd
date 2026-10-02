extends Node3D
## Matching static endpoints; evidence is copied, never removed for other players.

const ENVELOPE := preload("res://features/hotel_props/props/mail_envelope.tscn")
const PHONE := preload("res://features/hotel_props/props/rotary_phone.tscn")
const MENU := preload("res://features/bar_companion/case_menu.gd")
const TITLES: Array[String] = [
	"CASE — program / court filing",
	"CASE — scoring ledger",
	"CASE — blacklist memo",
	"CASE — telephone\nWitness / Donald Gilt",
	"CASE — signed contract"
]
var index := 0
var talk: NetworkedInteraction
var _label: Label3D
@onready var case: VivienneCase = get_parent()


func _ready() -> void:
	add_to_group(&"interactables")
	talk = NetworkedInteraction.new()
	talk.name = "NetworkedEntity"
	talk.interaction_range = 2.2
	add_child(talk)
	talk.register_use(can_use, _apply, 0.2)
	var source := PHONE.instantiate() if index == 3 else ENVELOPE.instantiate()
	var model := source.get_node("Model").duplicate() as Node3D
	source.free()
	add_child(model)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position.y = 0.35
	_label.pixel_size = 0.0025
	_label.font_size = 24
	_label.outline_size = 6
	_label.text = "CASE PHONE" if index == 3 else TITLES[index]
	_label.modulate = Color("ead6a4")
	add_child(_label)
	var menu := CanvasLayer.new()
	menu.set_script(MENU)
	menu.name = "CaseMenu"
	add_child(menu)


func _process(_delta: float) -> void:
	_label.visible = case.allowed(multiplayer.get_unique_id(), index)


func can_use(player: Player) -> bool:
	return (
		talk.in_range(player)
		and case.active_player(player)
		and case.allowed(player.get_multiplayer_authority(), index)
	)


func interaction_text() -> String:
	return TITLES[index]


func use() -> void:
	talk.request_use()


func _apply(player: Player) -> bool:
	return case.act(player, index, talk)
