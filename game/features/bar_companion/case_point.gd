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
var _label: SignBoard
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
	_label = SignBoard.new()
	_label.position = Vector3(0, .17, .14)
	_label.rotation.y = -PI / 2 if index == 4 else PI / 2
	_label.letter_height = .04
	_label.padding = .02
	_label.scale = Vector3.ONE * .5
	_label.text = "CASE PHONE" if index == 3 else TITLES[index]
	var post := MeshInstance3D.new()
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(.015, .17, .015)
	post.mesh = post_mesh
	post.position = Vector3(0, .085, .14)
	post.material_override = preload("res://features/procedural_rooms/materials/grey.tres")
	add_child(post)
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
