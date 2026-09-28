extends Node3D
## Asset-free cabinet and reel placeholders. Presentation only; never chooses results.

const SYMBOLS: Array[String] = ["7", "BAR", "STAR", "BELL", "GEM"]
const GOLD := Color("f6c85f")
const INK := Color("122133")
var _reels: Array[Label3D] = []
var _status: Label3D
var _caption: Label3D
var _lever: Node3D
var _last_state: Dictionary = {}

@onready var _machine: SlotMachine = get_parent() as SlotMachine


func _ready() -> void:
	_box(Vector3(2.2, 2.8, 1.2), Vector3(0, 1.4, 0), INK)
	_box(Vector3(2.3, 0.15, 1.3), Vector3(0, 0.08, 0), GOLD)
	_box(Vector3(2.05, 0.5, 0.08), Vector3(0, 2.4, 0.63), GOLD)
	_label("LUCKY FIVE", Vector3(0, 2.4, 0.69), 64, INK)
	_box(Vector3(2.05, 0.85, 0.08), Vector3(0, 1.65, 0.63), GOLD)
	for index: int in 3:
		var x := float(index - 1) * 0.65
		_box(Vector3(0.59, 0.68, 0.09), Vector3(x, 1.65, 0.69), Color("fff5da"))
		_reels.append(_label(SYMBOLS[index], Vector3(x, 1.65, 0.75), 58, INK))
	_status = _label("TRY YOUR LUCK", Vector3(0, 1.02, 0.66), 34, GOLD)
	_caption = _label("4 WINS / 5 SPINS", Vector3(0, 0.78, 0.66), 26, Color.WHITE)
	_box(Vector3(0.95, 0.16, 0.12), Vector3(0, 0.42, 0.64), Color("070d14"))
	_lever = Node3D.new()
	_lever.position = Vector3(1.25, 1.3, 0)
	add_child(_lever)
	var stem := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.055
	cylinder.bottom_radius = 0.055
	cylinder.height = 0.7
	stem.mesh = cylinder
	stem.position.y = 0.35
	stem.material_override = _material(GOLD)
	_lever.add_child(stem)
	var knob := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	knob.mesh = sphere
	knob.position.y = 0.75
	knob.material_override = _material(Color("e34b58"))
	_lever.add_child(knob)


func _process(_delta: float) -> void:
	var snapshot := _machine.state
	if snapshot == _last_state:
		return
	_last_state = snapshot.duplicate(true)
	var reels: Array = snapshot["reels"]
	for index: int in 3:
		_reels[index].text = SYMBOLS[int(reels[index])]
		_reels[index].modulate = INK if index < int(snapshot["stopped"]) else Color("84909b")
	_lever.rotation.x = 0.8 if snapshot["spinning"] else 0.0
	if snapshot["spinning"]:
		_status.text = "SPINNING…"
		_caption.text = str(snapshot["operator"]).left(20)
	elif int(snapshot["spin"]) > 0:
		_status.text = "WINNER!" if snapshot["won"] else "NO WIN — TRY AGAIN"
		_caption.text = str(snapshot["operator"]).left(20)
	else:
		_status.text = "TRY YOUR LUCK"
		_caption.text = "4 WINS / 5 SPINS"


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.35
	return material


func _box(dimensions: Vector3, origin: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.position = origin
	mesh.material_override = _material(color)
	add_child(mesh)


func _label(text: String, origin: Vector3, font_size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = origin
	label.font_size = font_size
	label.pixel_size = 0.003
	label.modulate = color
	label.outline_size = 0
	add_child(label)
	return label
