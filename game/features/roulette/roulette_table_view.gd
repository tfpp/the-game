extends Node3D
## Asset-free table and ball placeholders. Presentation only; never chooses results.

const GOLD := Color("f6c85f")
const FELT := Color("0a6b3d")
const WOOD := Color("3b2a1d")
const INK := Color("122133")
const RED := Color("b3202c")
const BLACK := Color("111318")
const MARKER_COUNT := 8
const BALL_RADIUS_M := 0.45

var _ball: MeshInstance3D
var _status: Label3D
var _caption: Label3D
var _last_state: Dictionary = {}

@onready var _table: RouletteTable = get_parent() as RouletteTable


func _ready() -> void:
	_cylinder(1.15, 0.85, Vector3(0, 0.42, 0), WOOD)
	_cylinder(1.1, 0.06, Vector3(0, 0.88, 0), FELT)
	_cylinder(0.55, 0.05, Vector3(0, 0.92, 0), INK)
	for index: int in MARKER_COUNT:
		var angle := TAU * float(index) / float(MARKER_COUNT)
		var color := RED if index % 2 == 0 else BLACK
		var pos := Vector3(cos(angle) * BALL_RADIUS_M, 0.95, sin(angle) * BALL_RADIUS_M)
		_box(Vector3(0.12, 0.02, 0.12), pos, color)
	_ball = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.045
	sphere.height = 0.09
	_ball.mesh = sphere
	_ball.material_override = _material(Color.WHITE)
	add_child(_ball)
	_status = _label("PLACE YOUR BETS", Vector3(0, 1.55, 0), 34, GOLD)
	_caption = _label("SPIN TO PLAY", Vector3(0, 1.32, 0), 26, Color.WHITE)


func _process(_delta: float) -> void:
	var snapshot := _table.state
	if snapshot == _last_state:
		return
	_last_state = snapshot.duplicate(true)
	var angle := TAU * float(int(snapshot["ball"])) / float(RouletteWheel.POCKET_COUNT)
	_ball.position = Vector3(cos(angle) * BALL_RADIUS_M, 0.97, sin(angle) * BALL_RADIUS_M)
	if snapshot["spinning"]:
		_status.text = "SPINNING…"
		_caption.text = str(snapshot["operator"]).left(20)
	elif int(snapshot["spin"]) > 0:
		_status.text = "%d — %s" % [int(snapshot["number"]), str(snapshot["color"]).to_upper()]
		_caption.text = str(snapshot["operator"]).left(20)
	else:
		_status.text = "PLACE YOUR BETS"
		_caption.text = "SPIN TO PLAY"


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.35
	return material


func _cylinder(radius: float, height: float, origin: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	mesh.mesh = cylinder
	mesh.position = origin
	mesh.material_override = _material(color)
	add_child(mesh)


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
