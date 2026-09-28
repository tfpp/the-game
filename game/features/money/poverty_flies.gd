class_name PovertyFlies
extends Node3D
## Cosmetic swarm shown above a remote player currently ranked in the poorest 80%
## of connected wallets (see `PlayerMoney.poorest_peers`). Every peer derives the same
## ranking from the already-replicated `balances` dictionary, so this needs no
## networking of its own — each client just attaches or removes the same local effect.

const FLY_COUNT := 3
const ORBIT_RADIUS_M := 0.16
const ORBIT_SPEED := 4.2
const BOB_SPEED := 6.0
const BOB_HEIGHT_M := 0.03

var _time := 0.0
var _flies: Array[MeshInstance3D] = []


func _ready() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.08, 0.08, 0.1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in FLY_COUNT:
		var fly := MeshInstance3D.new()
		fly.mesh = mesh
		fly.material_override = material
		add_child(fly)
		_flies.append(fly)


func _process(delta: float) -> void:
	_time += delta
	for i in _flies.size():
		var offset := TAU * float(i) / float(_flies.size())
		var angle := _time * ORBIT_SPEED + offset
		var bob := sin(_time * BOB_SPEED + offset) * BOB_HEIGHT_M
		_flies[i].position = Vector3(cos(angle) * ORBIT_RADIUS_M, bob, sin(angle) * ORBIT_RADIUS_M)
