extends RefCounted
## Seeded placement within declared zones; reject invalid, blocked or overlapping slots.

const Showcase := preload("res://features/procedural_rooms/showcase.gd")
const TYPES: Array[String] = ["garage", "storage", "utility", "pump"]
const FOOTPRINT := Vector3(8, 3.5, 8)


static func plan(rule: ProceduralPopulationRule, seed_value: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if rule.allowed_yaws.is_empty() or rule.allowed_sets.is_empty():
		return result
	var choices: Array[String] = []
	var weights: Array[float] = []
	var total := 0.0
	for index: int in rule.allowed_sets.size():
		var kind := rule.allowed_sets[index]
		var weight := rule.weights[index] if index < rule.weights.size() else 1.0
		if kind not in TYPES or weight <= 0:
			continue
		choices.append(kind)
		weights.append(weight)
		total += weight
	if total <= 0:
		return result
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var occupied: Array[AABB] = []
	for slot: Vector3 in rule.slots:
		var bounds := AABB(slot - Vector3(4, 0, 4), FOOTPRINT)
		var blocked := not rule.placement_bounds.encloses(bounds)
		for reserved: AABB in rule.forbidden_volumes + occupied:
			if bounds.intersects(reserved):
				blocked = true
		if blocked or random.randf() > clampf(rule.density, 0, 1):
			continue
		var roll := random.randf() * total
		var selected: String = choices.back()
		for index: int in choices.size():
			roll -= weights[index]
			if roll < 0:
				selected = choices[index]
				break
		var yaw := rule.allowed_yaws[random.randi_range(0, rule.allowed_yaws.size() - 1)]
		# The current 8 x 8 footprint is valid for quarter turns only.
		if absf(wrapf(yaw, -PI / 4, PI / 4)) > 0.0001:
			continue
		result.append({"kind": selected, "center": slot, "yaw": yaw, "bounds": bounds})
		occupied.append(bounds)
	return result


static func populate(room: Node3D, rule: ProceduralPopulationRule, seed_value: int) -> void:
	var old := room.get_node_or_null("Population")
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = "Population"
	room.add_child(root)
	var placements := plan(rule, seed_value)
	root.set_meta("placements", placements)
	for index: int in placements.size():
		var value: Dictionary = placements[index]
		var anchor := Node3D.new()
		anchor.name = "Slot%d_%s" % [index, value["kind"]]
		root.add_child(anchor)
		anchor.rotation.y = value["yaw"]
		anchor.position = value["center"] - anchor.basis * Vector3(0, 0, 4)
		Showcase.set_piece(anchor, value["kind"])
