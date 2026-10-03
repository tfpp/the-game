extends Node3D
## Readable physical cards, chips and dice follow the replicated table snapshot.
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
		label.position = Vector3((i % 3 - 1) * .85, 1.2, (i / 3) * .45)
		label.rotation.x = -PI / 2
		label.font_size = 24
		label.pixel_size = .002
		label.modulate = Color("f3e3bf")
		add_child(label)
		_labels.append(label)
	for i: int in 4:
		var chip := MeshInstance3D.new()
		chip.mesh = CHIP
		chip.material_override = CHIP_MATERIAL
		chip.position = Vector3((i - 1.5) * .5, 1.05, .7)
		add_child(chip)
		_chips.append(chip)


func _process(_delta: float) -> void:
	var snapshot := JSON.stringify(table.state)
	if snapshot == _last:
		return
	_last = snapshot
	for label: Label3D in _labels:
		label.text = ""
	for chip: MeshInstance3D in _chips:
		chip.visible = false
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
