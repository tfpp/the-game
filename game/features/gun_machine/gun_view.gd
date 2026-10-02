class_name GunView
extends RefCounted
## Selects an authored model for double-barrel plasma rolls. Other generated guns
## use procedural dimensions and colors from the stats shown by the rig or kiosk.
## Every view carries `Grip` and `SupportGrip` markers for the player hand rig.

const PLASMA_SCENE := preload("res://features/gun_machine/double_barrel_plasma.tscn")
const PLASMA_FIRST_PERSON_OFFSET := Vector3(0.25, -0.27, -0.64)

const BARREL_SPACING := 0.055
const BODY_COLOR := Color(0.15, 0.15, 0.17)


## A `Node3D`, forward-facing down -Z, with a `Muzzle` marker at the end of the
## barrels — the same muzzle-flash convention features/holdables/hand.gd uses.
static func build(stats: Dictionary) -> Node3D:
	if int(stats["ammo_type"]) == GunGenerator.AmmoType.PLASMA and int(stats["barrel_count"]) == 2:
		return PLASMA_SCENE.instantiate() as Node3D
	var root := Node3D.new()
	var ammo_type: GunGenerator.AmmoType = stats["ammo_type"]
	var profile := GunGenerator.profile(ammo_type)
	var barrel_count: int = stats["barrel_count"]
	var color: Color = profile["color"]

	# Barrel length/thickness reflect the rolled stats: a harder-hitting round gets a
	# thicker barrel, a faster one a longer one.
	var length := clampf(0.35 + float(stats["projectile_speed"]) / 220.0, 0.35, 1.0)
	var radius := clampf(0.02 + float(stats["damage"]) / 400.0, 0.02, 0.05)

	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.09, 0.11, 0.22)
	body.mesh = body_mesh
	body.position = Vector3(0, 0, 0.06)
	body.material_override = _material(BODY_COLOR)
	root.add_child(body)

	for offset: Vector2 in _barrel_offsets(barrel_count):
		var barrel := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		barrel.mesh = mesh
		barrel.rotation.x = deg_to_rad(90.0)
		barrel.position = Vector3(offset.x, offset.y, -length * 0.5)
		barrel.material_override = _material(color)
		root.add_child(barrel)

	if GunGenerator.is_ray_gun(stats):
		_add_ray_gun_details(root, body, length, color)

	# Hand-rig markers, so HeldArms poses the player's hands on every generated gun:
	# the right hand under the rear of the body, the left under the barrels.
	var grip := Marker3D.new()
	grip.name = "Grip"
	grip.position = Vector3(0, -0.04, 0.1)
	root.add_child(grip)
	var support := Marker3D.new()
	support.name = "SupportGrip"
	support.position = Vector3(0, -radius - BARREL_SPACING, -length * 0.45)
	root.add_child(support)

	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -length)
	root.add_child(muzzle)

	return root


## The Ray Gun's retro look: a red body and glowing green rings around the barrel.
static func _add_ray_gun_details(
	root: Node3D, body: MeshInstance3D, length: float, glow: Color
) -> void:
	body.material_override = _material(Color(0.6, 0.08, 0.06))
	for index: int in 3:
		var ring := MeshInstance3D.new()
		ring.name = "RayRing%d" % index
		var mesh := TorusMesh.new()
		mesh.inner_radius = 0.035
		mesh.outer_radius = 0.055 - index * 0.006
		ring.mesh = mesh
		ring.rotation.x = deg_to_rad(90.0)
		ring.position = Vector3(0, 0, -length * (0.25 + index * 0.25))
		ring.material_override = GunFx.material(glow, true)
		root.add_child(ring)


static func _barrel_offsets(barrel_count: int) -> Array[Vector2]:
	match barrel_count:
		1:
			return [Vector2(0, 0)] as Array[Vector2]
		2:
			return [Vector2(-BARREL_SPACING, 0), Vector2(BARREL_SPACING, 0)] as Array[Vector2]
		3:
			return (
				[
					Vector2(-BARREL_SPACING, 0),
					Vector2(BARREL_SPACING, 0),
					Vector2(0, BARREL_SPACING),
				]
				as Array[Vector2]
			)
		_:
			return (
				[
					Vector2(-BARREL_SPACING, -BARREL_SPACING),
					Vector2(BARREL_SPACING, -BARREL_SPACING),
					Vector2(-BARREL_SPACING, BARREL_SPACING),
					Vector2(BARREL_SPACING, BARREL_SPACING),
				]
				as Array[Vector2]
			)


static func _material(color: Color) -> StandardMaterial3D:
	return GunFx.material(color)
