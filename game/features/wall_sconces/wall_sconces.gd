class_name WallSconces
extends Node3D
## Outdated 1960s brass wall sconces for the annex corridors and rooms, which have no
## lights of their own and go pitch black once features/day_night/day_night.gd drops
## the ambient light at night. The casino proper already has its own sconces and
## chandeliers (features/casino_hub/interior.tscn), so this only covers the annex.
##
## Purely cosmetic and per-peer: nothing here is replicated or player-changeable. The
## glow follows the same wall-clock day/night factor DayNight uses, so the lamps stay
## dim in daylight and burn warmly at night without any RPC.

const BRASS := preload("res://features/casino_hub/materials/brass.tres")
const GLOW := preload("res://features/casino_hub/materials/glow.tres")

const LAMP_COLOR := Color(1, 0.72, 0.4)
const DAY_ENERGY := 0.25
const NIGHT_ENERGY := 1.4
const LAMP_RANGE := 9.0
const MOUNT_HEIGHT := 3.2

## One sconce per entry: x, z of the wall face, then the wall's normal (nx, nz) pointing
## into the room. Positions are the inner faces of the walls in features/annex.
const SPOTS: Array[Vector4] = [
	# Loop: approach, bend, room 1 and the corridor to room 2.
	Vector4(-14, -37, 1, 0),
	Vector4(-20, -43, 0, -1),
	Vector4(-33, -49.5, 0, 1),
	Vector4(-33, -40.5, 0, -1),
	Vector4(-46, -52, 1, 0),
	Vector4(-42, -56, -1, 0),
	Vector4(-54.8, -58, 1, 0),
	# Loop: the long spine and the west branch.
	Vector4(-52, -40, 1, 0),
	Vector4(-48, -24, -1, 0),
	Vector4(-52, -8, 1, 0),
	Vector4(-52, 20, 1, 0),
	Vector4(-48, 20, -1, 0),
	Vector4(-38, 5.5, 0, 1),
	# Loop: rooms 9 and 10.
	Vector4(-59.5, 32.5, 1, 0),
	Vector4(-40.5, 32.5, -1, 0),
	Vector4(-56, 25.5, 0, 1),
	Vector4(-44, 39.5, 0, -1),
	Vector4(-52, 45, 1, 0),
	Vector4(-53.8, 55, 1, 0),
	# North-east wing: rooms 3 and 4.
	Vector4(8, -50, 1, 0),
	Vector4(12, -38, -1, 0),
	Vector4(5.5, -62.5, 1, 0),
	Vector4(14.5, -62.5, -1, 0),
	Vector4(10, -69.5, 0, 1),
	Vector4(18, -47, 0, 1),
	Vector4(33.8, -45, -1, 0),
	# East wing: rooms 5 and 6.
	Vector4(40, -12.5, 0, 1),
	Vector4(50, -7.5, 0, -1),
	Vector4(55.5, -16.25, 1, 0),
	Vector4(68.5, -19.5, 0, 1),
	Vector4(74.5, -10, -1, 0),
	Vector4(65, -0.5, 0, -1),
	Vector4(58, -27, 1, 0),
	Vector4(60, -45.5, 0, 1),
	Vector4(55.5, -40, 1, 0),
	Vector4(64.5, -40, -1, 0),
	# South wing: corridor, rooms 7 and 8.
	Vector4(-2.5, 38, 1, 0),
	Vector4(2.5, 44, -1, 0),
	Vector4(-10, 45.5, 0, 1),
	Vector4(-18, 41.5, 0, 1),
	Vector4(-29.5, 50, 1, 0),
	Vector4(-15.5, 52.75, -1, 0),
	Vector4(-27.25, 54.5, 0, -1),
	Vector4(-24.5, 60, 1, 0),
	Vector4(-27.5, 67.5, 0, 1),
	Vector4(-17.5, 67.5, 0, 1),
	Vector4(-22.5, 80.5, 0, -1),
	Vector4(-30, 74, 1, 0),
	Vector4(-15, 74, -1, 0),
	# Food court (features/food_court), east of the south corridor.
	Vector4(12, 35, 0, 1),
	Vector4(24, 35, 0, 1),
	Vector4(10, 51, 0, -1),
	Vector4(26, 51, 0, -1),
]

var _lights: Array[OmniLight3D] = []
var _shade_material: StandardMaterial3D
var _last_factor := -1.0


func _ready() -> void:
	_shade_material = GLOW.duplicate() as StandardMaterial3D
	for spot in SPOTS:
		add_child(_build_sconce(spot))
	_apply(current_night_factor())


func _process(_delta: float) -> void:
	_apply(current_night_factor())


## 0 in full daylight, 1 at full night, from the same clock and twilight band as DayNight.
func current_night_factor() -> float:
	var t := DayNight.compute_time_of_day(
		Time.get_unix_time_from_system(), DayNight.DAY_LENGTH_SECONDS
	)
	return 1.0 - DayNight.compute_day_factor(DayNight.compute_sun_elevation_degrees(t))


static func lamp_energy(night_factor: float) -> float:
	return lerpf(DAY_ENERGY, NIGHT_ENERGY, night_factor)


func _apply(night_factor: float) -> void:
	if is_equal_approx(night_factor, _last_factor):
		return
	_last_factor = night_factor
	var energy := lamp_energy(night_factor)
	for light in _lights:
		light.light_energy = energy
	_shade_material.emission_energy_multiplier = lerpf(0.3, 1.5, night_factor)


func _build_sconce(spot: Vector4) -> Node3D:
	var normal := Vector2(spot.z, spot.w)
	var root := Node3D.new()
	root.name = "Sconce_%s_%s" % [spot.x, spot.y]
	root.position = Vector3(spot.x, MOUNT_HEIGHT, spot.y)
	root.rotation.y = atan2(normal.x, normal.y)
	root.add_child(_box(Vector3(0.5, 1.0, 0.16), Vector3(0, -0.1, 0.08), BRASS))
	root.add_child(_box(Vector3(0.32, 0.65, 0.24), Vector3(0, 0, 0.2), _shade_material))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0, 0.9)
	light.light_color = LAMP_COLOR
	light.omni_range = LAMP_RANGE
	light.omni_attenuation = 1.4
	root.add_child(light)
	_lights.append(light)
	return root


func _box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	return instance
