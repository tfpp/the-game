class_name GarageEnemyModel
extends Node3D
## A hunched scavenger silhouette built from primitive meshes. It faces -Z like a
## player. The eyes are unshaded so an enemy stays readable in the garage's dead
## fixtures; each tier has its own size, skin and eye colour.

const HURT_FLASH_S := 0.12

var _skin := StandardMaterial3D.new()
var _eyes := StandardMaterial3D.new()
var _skin_color := Color.GRAY
var _eye_color := Color.WHITE
var _hurt_timer := 0.0
var _arm_left: Node3D
var _arm_right: Node3D
var _torso: Node3D


func build(tier: int) -> void:
	var info := GarageEnemyTiers.profile(tier)
	_skin_color = info["skin"]
	_eye_color = info["eyes"]
	_skin.albedo_color = _skin_color
	_skin.roughness = 0.9
	_eyes.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eyes.albedo_color = _eye_color
	scale = Vector3.ONE * float(info["scale"])
	_box("LegLeft", Vector3(0.16, 0.8, 0.18), Vector3(-0.14, 0.4, 0.0))
	_box("LegRight", Vector3(0.16, 0.8, 0.18), Vector3(0.14, 0.4, 0.0))
	_torso = _box("Torso", Vector3(0.5, 0.62, 0.3), Vector3(0.0, 1.1, 0.0))
	_torso.rotation.x = deg_to_rad(-18.0)
	var head := _box("Head", Vector3(0.3, 0.3, 0.3), Vector3(0.0, 0.42, -0.08), _torso)
	_box("Hood", Vector3(0.36, 0.2, 0.36), Vector3(0.0, 0.1, 0.03), head)
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.07, 0.04, 0.02)
		eye.mesh = mesh
		eye.material_override = _eyes
		eye.position = Vector3(0.07 * side, 0.0, -0.16)
		head.add_child(eye)
	_arm_left = _limb("ArmLeft", Vector3(-0.33, 0.25, 0.0))
	_arm_right = _limb("ArmRight", Vector3(0.33, 0.25, 0.0))
	if info["ranged"]:
		_box("Gun", Vector3(0.08, 0.12, 0.5), Vector3(0.0, -0.55, -0.2), _arm_right)
	else:
		for side: float in [-1.0, 1.0]:
			_box("Claws", Vector3(0.14, 0.08, 0.2), Vector3(0.0, -0.6, -0.08), _arm(side))


## `stride` 0..1 swings the limbs while walking; `raised` lifts the arms for a
## wind-up so players can see an attack coming.
func animate(delta: float, stride: float, walking: bool, raised: bool) -> void:
	var swing := sin(stride * TAU) * (0.6 if walking else 0.0)
	var lift := deg_to_rad(-100.0) if raised else 0.0
	_arm_left.rotation.x = lerpf(_arm_left.rotation.x, lift + swing, minf(delta * 12.0, 1.0))
	_arm_right.rotation.x = lerpf(_arm_right.rotation.x, lift - swing, minf(delta * 12.0, 1.0))
	_eyes.albedo_color = _eye_color.lightened(0.5) if raised else _eye_color
	if _hurt_timer > 0.0:
		_hurt_timer -= delta
		_skin.albedo_color = Color.WHITE if _hurt_timer > 0.0 else _skin_color


func flash() -> void:
	_hurt_timer = HURT_FLASH_S
	_skin.albedo_color = Color.WHITE


func _arm(side: float) -> Node3D:
	return _arm_left if side < 0.0 else _arm_right


func _limb(limb_name: String, at: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = limb_name
	pivot.position = at
	_torso.add_child(pivot)
	_box("Mesh", Vector3(0.13, 0.62, 0.14), Vector3(0.0, -0.3, 0.0), pivot)
	return pivot


func _box(part: String, size: Vector3, at: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = part
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = _skin
	node.position = at
	parent.add_child(node)
	return node
