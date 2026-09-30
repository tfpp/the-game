extends RefCounted
## Seeded placement within declared zones; reject invalid, blocked or overlapping slots.

const Showcase := preload("res://features/procedural_rooms/showcase.gd")
const TYPES: Array[String] = ["garage", "storage", "utility", "pump"]
const FOOTPRINT := Vector3(8, 3.5, 8)


static func plan(rule: ProceduralPopulationRule, seed_value: int) -> Array[Dictionary]:
	if not rule.set_definitions.is_empty():
		return _catalogue_plan(rule, seed_value)
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
		if value.has("scene"):
			anchor.position = value["center"]
			anchor.add_child((value["scene"] as PackedScene).instantiate())
		else:
			anchor.position = value["center"] - anchor.basis * Vector3(0, 0, 4)
			Showcase.set_piece(anchor, value["kind"])


static func _catalogue_plan(rule: ProceduralPopulationRule, seed_value: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var occupied: Array[AABB] = []
	for slot: Vector3 in rule.slots:
		if random.randf() > clampf(rule.density, 0, 1):
			continue
		var candidates: Array[Dictionary] = []
		var total := 0.0
		for definition: ProceduralSetDefinition in rule.set_definitions:
			var index := rule.allowed_sets.find(definition.id)
			if index < 0 or definition.scene == null:
				continue
			if (
				not definition.allowed_rooms.is_empty()
				and rule.room_tag not in definition.allowed_rooms
			):
				continue
			var weight := rule.weights[index] if index < rule.weights.size() else 1.0
			if (
				weight <= 0
				or definition.footprint.x <= 0
				or definition.footprint.y <= 0
				or definition.footprint.z <= 0
			):
				continue
			var options: Array[Dictionary] = []
			for yaw: float in rule.allowed_yaws:
				if not is_finite(yaw) or absf(wrapf(yaw, -PI / 4, PI / 4)) > .0001:
					continue
				var size := definition.footprint
				if absi(roundi(yaw / (PI * .5))) % 2 == 1:
					size = Vector3(size.z, size.y, size.x)
				var bounds := AABB(slot - Vector3(size.x * .5, 0, size.z * .5), size)
				var blocked := not rule.placement_bounds.encloses(bounds)
				for reserved: AABB in rule.forbidden_volumes + occupied:
					blocked = blocked or bounds.intersects(reserved)
				if not blocked:
					options.append(
						{
							"kind": definition.id,
							"center": slot,
							"yaw": yaw,
							"bounds": bounds,
							"scene": definition.scene
						}
					)
			if not options.is_empty():
				candidates.append({"options": options, "weight": weight})
				total += weight
		if candidates.is_empty():
			continue
		var roll := random.randf() * total
		var selected: Dictionary = candidates.back()
		for candidate: Dictionary in candidates:
			roll -= candidate["weight"]
			if roll < 0:
				selected = candidate
				break
		var options: Array = selected["options"]
		var placement: Dictionary = options[random.randi_range(0, options.size() - 1)]
		result.append(placement)
		occupied.append(placement["bounds"])
	return result
