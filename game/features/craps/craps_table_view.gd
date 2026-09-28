extends Node3D
## Cosmetic animation only. The settled faces always come from the server snapshot.

const GOLD := Color("e7c675")
const WOOD := Color("39251e")
const FELT := Color("075c42")

var _dice: Array[MeshInstance3D] = []
var _faces: Array[Label3D] = []
var _status: Label3D
var _caption: Label3D
var _time := 0.0

@onready var _table: CrapsTable = get_parent() as CrapsTable


func _ready() -> void:
	_box(Vector3(3.2, 0.22, 1.8), Vector3(0, 0.82, 0), WOOD)
	_box(Vector3(2.9, 0.04, 1.5), Vector3(0, 0.95, 0), FELT)
	for x: float in [-1.5, 1.5]:
		_box(Vector3(0.2, 0.2, 1.8), Vector3(x, 1, 0), WOOD)
	for z: float in [-0.8, 0.8]:
		_box(Vector3(3.0, 0.2, 0.2), Vector3(0, 1, z), WOOD)
	for x: float in [-1.15, 1.15]:
		_box(Vector3(0.22, 0.8, 1.2), Vector3(x, 0.4, 0), WOOD)
	var pass_line := _label("PASS LINE", Vector3(0, 0.98, 0.52), 36)
	pass_line.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	pass_line.rotation.x = -PI / 2
	for index: int in 2:
		var die := _box(Vector3.ONE * 0.24, Vector3.ZERO, Color.IVORY)
		_dice.append(die)
		var face := _label("", Vector3.ZERO, 44)
		face.modulate = Color("191919")
		face.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		face.rotation.x = -PI / 2
		_faces.append(face)
	_status = _label("CRAPS — FREE PLAY", Vector3(0, 2.0, 0), 38)
	_caption = _label("", Vector3(0, 1.72, 0), 25)
	_label(
		(
			"PASS LINE • no money wagered\nCome-out: 7 / 11 win; 2 / 3 / 12 lose\n"
			+ "Otherwise set a point — roll it again before 7!"
		),
		Vector3(0, 2.55, 0),
		22
	)


func _process(delta: float) -> void:
	_time += delta
	var snapshot := _table.state
	var rolling: bool = snapshot["rolling"]
	var values: Vector2i = snapshot["dice"]
	for index: int in 2:
		var die := _dice[index]
		die.position = Vector3(-0.35 + index * 0.7, 1.1, -0.1)
		if rolling:
			die.position.y += absf(sin(_time * 9 + index)) * 0.3
			die.rotation = Vector3(_time * 7, _time * 5, _time * 3)
		else:
			die.rotation = Vector3.ZERO
		_faces[index].visible = not rolling
		_faces[index].position = die.position + Vector3(0, 0.122, 0)
		_faces[index].text = str(values[index])
	if rolling:
		_status.text = "ROLLING…"
	elif int(snapshot["roll"]) == 0:
		_status.text = "CRAPS — FREE PLAY"
	else:
		var outcome := str(snapshot["outcome"])
		var result := "POINT %d" % int(snapshot["point"])
		if outcome == "win":
			result = "PASS LINE WINS!"
		elif outcome == "lose":
			result = "PASS LINE LOSES"
		_status.text = "%d + %d = %d • %s" % [values.x, values.y, values.x + values.y, result]
	var phase := (
		"Come-out next" if int(snapshot["point"]) == 0 else "Point %d" % int(snapshot["point"])
	)
	_caption.text = "%s • %s" % [str(snapshot["operator"]).left(20), phase]


func _box(size: Vector3, origin: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = origin
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	node.material_override = material
	add_child(node)
	return node


func _label(text: String, origin: Vector3, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = origin
	label.font_size = font_size
	label.pixel_size = 0.003
	label.modulate = GOLD
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	return label
