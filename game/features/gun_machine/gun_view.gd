class_name GunView
extends RefCounted
## Builds a weapon's visual model straight from its rolled stats, since every
## generated gun is a one-off: barrel count, thickness, length and color all come
## from the stats a GunRig (or the machine's preview) is showing, not a fixed asset.
## On top of the stat-driven barrels, every gun gets the parts a real one has: a
## receiver, stock, pistol grip, trigger and guard, magazine, Picatinny-style top rail
## with front and rear sights, and a handguard with an under rail. Each part is a
## named child so the machine can reveal them one at a time as it "assembles" a gun.

const BARREL_SPACING := 0.055
const BODY_COLOR := Color(0.15, 0.15, 0.17)
const FURNITURE_COLOR := Color(0.24, 0.2, 0.16)
const METAL_COLOR := Color(0.32, 0.33, 0.36)
const RAIL_SLOT_SPACING := 0.025

## Every part name build() creates, in the order the machine assembles them.
const PART_NAMES: Array[StringName] = [
	&"Receiver",
	&"Grip",
	&"TriggerGuard",
	&"Trigger",
	&"Magazine",
	&"Stock",
	&"Barrels",
	&"Handguard",
	&"TopRail",
	&"UnderRail",
	&"RearSight",
	&"FrontSight",
]


## A `Node3D`, forward-facing down -Z, with a `Muzzle` marker at the end of the
## barrels — the same muzzle-flash convention features/holdables/hand.gd uses.
static func build(stats: Dictionary) -> Node3D:
	var root := Node3D.new()
	var ammo_type: GunGenerator.AmmoType = stats["ammo_type"]
	var profile := GunGenerator.profile(ammo_type)
	var barrel_count: int = stats["barrel_count"]
	var color: Color = profile["color"]
	var body := _material(BODY_COLOR)
	var metal := _material(METAL_COLOR, 0.8)
	var furniture := _material(FURNITURE_COLOR)
	var accent := _material(color, 0.4)

	# Barrel length/thickness reflect the rolled stats: a harder-hitting round gets a
	# thicker barrel, a faster one a longer one.
	var length := clampf(0.35 + float(stats["projectile_speed"]) / 220.0, 0.35, 1.0)
	var radius := clampf(0.02 + float(stats["damage"]) / 400.0, 0.02, 0.05)
	# Wider barrel clusters get a wider receiver so the barrels stay attached.
	var spread := BARREL_SPACING if barrel_count > 1 else 0.0
	var width := maxf(0.09, spread * 2.0 + radius * 2.0 + 0.02)
	var top := 0.055 + (BARREL_SPACING if barrel_count >= 3 else 0.0)

	var receiver := _part(&"Receiver", root)
	_box(
		receiver,
		Vector3(width, 0.11 + top - 0.055, 0.26),
		Vector3(0, (top - 0.055) * 0.5, 0.05),
		body
	)
	_box(receiver, Vector3(0.012, 0.03, 0.06), Vector3(width * 0.5 + 0.006, 0.01, 0.02), accent)

	var grip := _part(&"Grip", root)
	var grip_mesh := _box(grip, Vector3(0.06, 0.14, 0.055), Vector3(0, -0.11, 0.13), furniture)
	grip_mesh.rotation.x = deg_to_rad(-15.0)

	var guard := _part(&"TriggerGuard", root)
	_box(guard, Vector3(0.02, 0.012, 0.09), Vector3(0, -0.1, 0.065), metal)
	_box(guard, Vector3(0.02, 0.05, 0.012), Vector3(0, -0.075, 0.02), metal)

	var trigger := _part(&"Trigger", root)
	var trigger_mesh := _box(
		trigger, Vector3(0.012, 0.04, 0.012), Vector3(0, -0.075, 0.075), accent
	)
	trigger_mesh.rotation.x = deg_to_rad(20.0)

	var magazine := _part(&"Magazine", root)
	var magazine_depth := clampf(0.08 + float(stats["magazine_size"]) / 400.0, 0.08, 0.2)
	var magazine_mesh := _box(
		magazine,
		Vector3(0.045, magazine_depth, 0.06),
		Vector3(0, -0.055 - magazine_depth * 0.5, -0.03),
		metal
	)
	magazine_mesh.rotation.x = deg_to_rad(10.0)

	var stock := _part(&"Stock", root)
	_box(stock, Vector3(0.05, 0.05, 0.16), Vector3(0, 0.0, 0.26), furniture)
	_box(stock, Vector3(0.055, 0.13, 0.05), Vector3(0, -0.03, 0.36), furniture)
	_box(stock, Vector3(0.058, 0.135, 0.012), Vector3(0, -0.03, 0.39), body)

	var barrels := _part(&"Barrels", root)
	for offset: Vector2 in _barrel_offsets(barrel_count):
		var barrel := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = length
		barrel.mesh = mesh
		barrel.rotation.x = deg_to_rad(90.0)
		barrel.position = Vector3(offset.x, offset.y, -length * 0.5)
		barrel.material_override = accent
		barrels.add_child(barrel)
		# A muzzle ring on each barrel's tip.
		var ring := MeshInstance3D.new()
		var ring_mesh := CylinderMesh.new()
		ring_mesh.top_radius = radius * 1.3
		ring_mesh.bottom_radius = radius * 1.3
		ring_mesh.height = 0.03
		ring.mesh = ring_mesh
		ring.rotation.x = deg_to_rad(90.0)
		ring.position = Vector3(offset.x, offset.y, -length + 0.015)
		ring.material_override = metal
		barrels.add_child(ring)

	var handguard_length := length * 0.55
	var handguard := _part(&"Handguard", root)
	_box(
		handguard,
		Vector3(width + 0.01, 0.07 + top - 0.055, handguard_length),
		Vector3(0, (top - 0.055) * 0.5, -0.08 - handguard_length * 0.5),
		body
	)

	var rail_length := 0.26 + handguard_length
	var rail_center := 0.18 - rail_length * 0.5
	var top_y := 0.055 + top
	_rail(_part(&"TopRail", root), rail_length, Vector3(0, top_y + 0.008, rail_center), metal)
	var under_y := -0.035 - (BARREL_SPACING if barrel_count >= 4 else 0.0)
	var under_length := handguard_length * 0.8
	_rail(
		_part(&"UnderRail", root),
		under_length,
		Vector3(0, under_y - 0.008, -0.08 - handguard_length * 0.5),
		metal,
		-1.0
	)

	var rear_sight := _part(&"RearSight", root)
	_box(rear_sight, Vector3(0.012, 0.03, 0.02), Vector3(-0.014, top_y + 0.03, 0.15), metal)
	_box(rear_sight, Vector3(0.012, 0.03, 0.02), Vector3(0.014, top_y + 0.03, 0.15), metal)
	_box(rear_sight, Vector3(0.04, 0.012, 0.025), Vector3(0, top_y + 0.02, 0.15), metal)

	var front_sight := _part(&"FrontSight", root)
	var front_z := minf(-0.08 - handguard_length + 0.02, -0.1)
	_box(front_sight, Vector3(0.03, 0.02, 0.02), Vector3(0, top_y + 0.02, front_z), metal)
	_box(front_sight, Vector3(0.008, 0.03, 0.008), Vector3(0, top_y + 0.045, front_z), accent)

	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -length)
	root.add_child(muzzle)

	return root


static func _part(part_name: StringName, parent: Node3D) -> Node3D:
	var node := Node3D.new()
	node.name = part_name
	parent.add_child(node)
	return node


static func _box(
	parent: Node3D, size: Vector3, position: Vector3, material: Material
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)
	return instance


## A rail base with evenly spaced cross slots; `side` is 1 for a top rail (slots
## stick up) and -1 for an under rail (slots hang down).
static func _rail(
	parent: Node3D, length: float, center: Vector3, material: Material, side: float = 1.0
) -> void:
	_box(parent, Vector3(0.028, 0.01, length), center, material)
	var slots := maxi(2, int(length / RAIL_SLOT_SPACING))
	for i: int in slots:
		var z := center.z - length * 0.5 + (float(i) + 0.5) * (length / float(slots))
		_box(
			parent,
			Vector3(0.034, 0.008, RAIL_SLOT_SPACING * 0.5),
			Vector3(center.x, center.y + side * 0.009, z),
			material
		)


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


static func _material(color: Color, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.45 if metallic > 0.0 else 0.8
	return material
