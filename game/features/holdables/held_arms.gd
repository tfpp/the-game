class_name HeldArms
extends Node3D
## Cosmetic hand and arm rig owned by Holdables. Grip markers place the hands;
## shoulders follow the player body, so third-person items remain attached.

var _right := Node3D.new()
var _left := Node3D.new()
var _segments: Array[MeshInstance3D] = []
var _glove := StandardMaterial3D.new()
var _sleeve := StandardMaterial3D.new()


func _ready() -> void:
	_glove.albedo_color = PlayerSkin.TONES[0]
	_glove.roughness = 0.95
	_sleeve.albedo_color = Color(0.17, 0.32, 0.40)
	_sleeve.roughness = 0.9
	_right.name = "RightGlove"
	_left.name = "LeftGlove"
	add_child(_right)
	add_child(_left)
	_build_glove(_right, 1.0)
	_build_glove(_left, -1.0)
	for index: int in 4:
		var segment := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.17, 1.0, 0.17)
		segment.mesh = mesh
		segment.material_override = _sleeve
		add_child(segment)
		_segments.append(segment)


func set_sleeve_color(color: Color) -> void:
	_sleeve.albedo_color = color


func pose(right_shoulder: Vector3, left_shoulder: Vector3, support: Node3D) -> void:
	_right.transform = Transform3D.IDENTITY
	_left.visible = support != null
	if support != null:
		_left.global_transform = support.global_transform
	_arm(0, right_shoulder, _right, 1.0)
	for index: int in [2, 3]:
		_segments[index].visible = support != null
	if support != null:
		_arm(2, left_shoulder, _left, -1.0)


func _arm(index: int, shoulder: Vector3, glove: Node3D, side: float) -> void:
	var wrist := to_local(glove.to_global(Vector3(side * 0.055, -0.04, 0.055)))
	var elbow := shoulder.lerp(wrist, 0.55) + Vector3(side * 0.08, -0.16, 0.10)
	_segment(_segments[index], shoulder, elbow)
	_segment(_segments[index + 1], elbow, wrist)


func _segment(mesh: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var direction := to - from
	mesh.position = from.lerp(to, 0.5)
	mesh.basis = Basis(Quaternion(Vector3.UP, direction.normalized()))
	mesh.scale = Vector3(1, maxf(direction.length(), 0.001), 1)


func _build_glove(parent: Node3D, side: float) -> void:
	_box(parent, Vector3(side * 0.057, 0, 0.016), Vector3(0.052, 0.09, 0.075))
	for index: int in 3:
		var y := -0.031 + index * 0.028
		_box(parent, Vector3(side * 0.016, y, -0.036), Vector3(0.073, 0.023, 0.027))
		_box(parent, Vector3(-side * 0.022, y, -0.012), Vector3(0.024, 0.023, 0.052))
	_box(parent, Vector3(side * 0.015, 0.043, 0.045), Vector3(0.071, 0.03, 0.03))


func _box(parent: Node3D, at: Vector3, dimensions: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	mesh.mesh = box
	mesh.material_override = _glove
	mesh.position = at
	parent.add_child(mesh)


func set_skin_color(color: Color) -> void:
	_glove.albedo_color = color
