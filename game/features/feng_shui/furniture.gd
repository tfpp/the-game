extends RefCounted
## Scene-to-layout adapter. No retained nodes, processing, RPCs or gameplay effects.

const ELEMENTS: Array[String] = ["wood", "fire", "earth", "metal", "water"]
const STRUCTURE: Array[String] = [
	"floor",
	"wall",
	"ceiling",
	"roof",
	"ramp",
	"column",
	"pillar",
	"foundation",
	"ground",
	"paving",
	"terrain",
	"door",
	"window",
	"skylight",
	"fence",
	"railing",
	"rail",
	"partition",
	"lintel",
	"coffer",
	"promenade",
	"stair",
	"stairs",
	"threshold",
	"shutter",
	"quay",
	"retaining",
	"opening"
]
const WOOD: Array[String] = [
	"wood",
	"walnut",
	"plant",
	"planter",
	"tree",
	"table",
	"desk",
	"chair",
	"stool",
	"bench",
	"sofa",
	"couch",
	"bed",
	"wardrobe",
	"counter",
	"kitchen",
	"cabinet",
	"rack",
	"crate",
	"pallet",
	"paper",
	"card",
	"book",
	"ledger",
	"register",
	"envelope",
	"cubby",
	"cigar",
	"cigarette"
]
const FIRE: Array[String] = [
	"lamp",
	"light",
	"bulb",
	"sconce",
	"chandelier",
	"fixture",
	"radiator",
	"heater",
	"oven",
	"stove",
	"television",
	"monitor",
	"illuminated",
	"signal"
]
const WATER: Array[String] = [
	"water",
	"fountain",
	"basin",
	"sink",
	"pump",
	"pitcher",
	"bottle",
	"glass",
	"beer",
	"wine",
	"whiskey",
	"martini",
	"ice",
	"shampoo"
]
const METAL: Array[String] = [
	"metal",
	"brass",
	"steel",
	"galvanised",
	"car",
	"barrel",
	"bin",
	"dumpster",
	"cart",
	"machine",
	"fan",
	"clock",
	"phone",
	"radio",
	"camera",
	"key",
	"coin",
	"clip",
	"bell",
	"tray",
	"bucket",
	"luggage",
	"suitcase",
	"trunk",
	"briefcase",
	"extinguisher",
	"utility",
	"electrical",
	"transformer",
	"hydrant",
	"meter",
	"bollard",
	"gate",
	"ladder",
	"drain"
]


## Defaults are a game convention, not material chemistry or traditional Feng Shui.
## Unknown furniture is earth; scene metadata always takes precedence.
static func default_element(identity: String) -> String:
	var words := _words(identity)
	if words.size() == 1 and words[0] == "bar":
		return "wood"
	for group: Array in [FIRE, WATER, WOOD, METAL]:
		for word: String in words:
			if word in group:
				if group == FIRE:
					return "fire"
				if group == WATER:
					return "water"
				return "wood" if group == WOOD else "metal"
	return "earth"


## Geometry is projected into root-local X/Z; root's placement in the world is ignored.
## Each prefab contributes once, regardless of its number of mesh/collider children.
## Unknown loose meshes are earth furniture; structure, actors and GridMaps are excluded.
static func snapshot(root: Node3D, floor_rect: Rect2, floor_height: float = 0.0) -> Dictionary:
	var result := {"valid": true, "footprints": [], "elements": PackedFloat64Array([0, 0, 0, 0, 0])}
	_visit(root, Transform3D.IDENTITY, floor_rect, floor_height, result, true)
	return result


static func _visit(
	node: Node,
	transform: Transform3D,
	floor_rect: Rect2,
	floor_height: float,
	result: Dictionary,
	is_root: bool
) -> void:
	if node is CharacterBody3D or node is GridMap:
		return
	var local := transform
	if node is Node3D and not is_root:
		local *= (node as Node3D).transform
	var identity := str(node.get_meta("prop_id", node.name))
	var path := node.scene_file_path
	var prefab := node.has_meta("prop_id") or "/props/" in path or "/models/" in path
	# Also group legacy and interactive furniture, not just modern prop-kit scenes.
	prefab = prefab or (node is Node3D and default_element(identity) != "earth")
	var explicit := node.has_meta("feng_shui_element")
	if explicit and str(node.get_meta("feng_shui_element")) == "none":
		return
	if not explicit and not prefab and _is_structure(identity):
		return
	if (
		explicit
		or prefab
		or node is MeshInstance3D
		or node is CSGBox3D
		or node is CSGCylinder3D
		or node is CSGSphere3D
		or node is Light3D
	):
		var element := str(node.get_meta("feng_shui_element", default_element(identity)))
		var index := ELEMENTS.find(element)
		if index < 0:
			result["valid"] = false
			return
		var bounds := _bounds(node, local)
		if bounds.size == Vector3.ZERO and not node is Light3D:
			return
		if node is Light3D and bounds.size == Vector3.ZERO:
			# Light sources contribute fire but never floor occupancy.
			bounds = AABB(local.origin, Vector3.ZERO)
		var footprint := Rect2(
			Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)
		)
		if not footprint.intersects(floor_rect) and not floor_rect.has_point(footprint.position):
			return
		var elements: PackedFloat64Array = result["elements"]
		elements[index] += 1.0
		result["elements"] = elements
		# Wall/ceiling decor contributes an element but is not an obstacle on the floor.
		if (
			footprint.has_area()
			and bounds.position.y <= floor_height + 0.3
			and not _is_decor(identity)
		):
			(result["footprints"] as Array).append(footprint)
		return
	for child: Node in node.get_children():
		_visit(child, local, floor_rect, floor_height, result, false)


static func _words(identity: String) -> PackedStringArray:
	var words := identity.to_snake_case().replace("-", "_").split("_", false)
	for index: int in words.size():
		words[index] = words[index].rstrip("0123456789")
	return words


static func _is_structure(identity: String) -> bool:
	var words := _words(identity)
	for word: String in words:
		if word in STRUCTURE:
			return true
	return false


static func _is_decor(identity: String) -> bool:
	var value := identity.to_snake_case()
	return (
		value.contains("wall_")
		or value.contains("pendant")
		or value.contains("chandelier")
		or value.contains("ceiling")
		or value.contains("framed_art")
		or value.contains("sign")
	)


## Mesh geometry only: collision padding, lights and interaction areas do not inflate it.
static func _bounds(node: Node, transform: Transform3D) -> AABB:
	var result := AABB()
	if node is CharacterBody3D or node is GridMap:
		return result
	var found := false
	var own := AABB()
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		own = (node as MeshInstance3D).mesh.get_aabb()
	elif node is CSGBox3D:
		var size := (node as CSGBox3D).size
		own = AABB(-size * 0.5, size)
	elif node is CSGCylinder3D:
		var cylinder := node as CSGCylinder3D
		var size := Vector3(cylinder.radius * 2, cylinder.height, cylinder.radius * 2)
		own = AABB(-size * 0.5, size)
	elif node is CSGSphere3D:
		var size := Vector3.ONE * (node as CSGSphere3D).radius * 2
		own = AABB(-size * 0.5, size)
	if own.size != Vector3.ZERO:
		result = transform * own
		found = true
	for child: Node in node.get_children():
		var child_transform := transform
		if child is Node3D:
			child_transform *= (child as Node3D).transform
		var child_bounds := _bounds(child, child_transform)
		if child_bounds.size == Vector3.ZERO:
			continue
		result = result.merge(child_bounds) if found else child_bounds
		found = true
	return result
