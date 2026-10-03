extends Node3D
## Cosmetic cards, chips and cabinet text follow shared state; private data stays local.
const CHIP := preload("res://assets/casino_props/models/chip_stack.res")
const CHIP_MATERIAL := preload("res://features/casino_props/materials/chip_stack.tres")
var _last := ""
var _labels: Array[Label3D] = []
var _chips: Array[MeshInstance3D] = []
@onready var table: CrownGameTable = get_parent()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	for i: int in 7:
		var label := Label3D.new()
		label.position = Vector3(0, 1.0 if table.game == "craps" else .947, -.25 if i == 0 else 0)
		label.rotation.x = -PI / 2
		label.font_size = 24
		label.pixel_size = .0018
		label.modulate = Color("f3e3bf")
		if table.game == "video_poker":
			label.position = Vector3(0, 1.05, .158)
			label.rotation.x = -atan2(.12, .45)
			label.pixel_size = .0014
		elif table.game == "baccarat" and i < 2:
			label.position.x = .6 if i == 0 else -.6
		if i >= 3 and table.game != "video_poker":
			label.position = _player_spot(i - 3)
		add_child(label)
		_labels.append(label)
	if table.game == "baccarat":
		for x: float in [-.6, .6]:
			var area := Label3D.new()
			area.position = Vector3(x, .947, -.38)
			area.rotation.x = -PI / 2
			area.font_size = 24
			area.pixel_size = .002
			area.text = "PLAYER" if x < 0 else "BANKER"
			area.modulate = Color("dcc58b")
			add_child(area)
	for i: int in 4:
		var chip := MeshInstance3D.new()
		chip.mesh = CHIP
		chip.material_override = CHIP_MATERIAL
		chip.position = _player_spot(i) + Vector3(.12, 0, -.06)
		chip.position.y = 1.0 if table.game == "craps" else .947
		chip.scale = Vector3.ONE * .55
		add_child(chip)
		_chips.append(chip)


func _player_spot(index: int) -> Vector3:
	var seats := CrownTableSeating.layout(table.game)
	if index < seats.size():
		return Vector3(seats[index].x * .57, .947, seats[index].z * .40)
	return Vector3((index - 1.5) * .5, .99, .45)


func _process(_delta: float) -> void:
	var snapshot := JSON.stringify(table.state) + str(table.private_hand)
	if snapshot == _last:
		return
	_last = snapshot
	for label: Label3D in _labels:
		label.text = ""
	for chip: MeshInstance3D in _chips:
		chip.visible = false
	if table.game == "video_poker":
		var cards: Array = table.private_hand
		if cards.is_empty() and not (table.state["players"] as Dictionary).is_empty():
			cards = (table.state["players"].values()[0] as Dictionary).get("cards", [])
		_labels[0].text = CasinoCards.labels(cards) if not cards.is_empty() else "READY · $1"
		return
	_labels[0].text = CasinoCards.labels(table.state["dealer"])
	_labels[1].text = CasinoCards.labels(table.state["board"])
	_labels[2].text = str(table.state["dice"]) if table.game == "craps" else ""
	var i := 0
	for peer: int in table.state["players"]:
		var player: Dictionary = table.state["players"][peer]
		_labels[3 + i].text = (
			"%s\n%s" % [str(player["name"]).left(12), CasinoCards.labels(player.get("cards", []))]
		)
		_chips[i].visible = true
		i += 1
