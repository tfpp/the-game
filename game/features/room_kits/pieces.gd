extends RefCounted
## Shared structural pieces used by generated rooms and the exported kit scenes.

const Geometry := preload("res://features/world_builder/geometry.gd")
const Catalog := preload("res://features/room_kits/catalog.gd")


static func corner(g: Geometry, kit: String, at: Vector3, height: float) -> void:
	if kit == "concrete":
		return
	var width := 0.22 if kit == "modern" else 0.34
	g.box(kit + "_trim", at + Vector3.UP * height / 2, Vector3(width, height, width), true)
	if kit == "deco":
		for y: float in [0.18, height - 0.2]:
			g.box(kit + "_accent", at + Vector3.UP * y, Vector3(0.42, 0.1, 0.42))


static func wall_detail(g: Geometry, kit: String, wall: Dictionary) -> void:
	if kit == "concrete":
		return
	var length: float = wall["a"].distance_to(wall["b"])
	var u: Vector3 = (wall["b"] - wall["a"]).normalized()
	var basis := Basis(u, Vector3.UP, wall["normal"])
	var height: float = wall["height"]
	# Modern: restrained skirting and a ceiling reveal. Deco: stepped crown and flutes.
	for y: float in [0.08, height - 0.10]:
		var spans: Array[Vector2] = [Vector2(0, length)]
		for opening: Dictionary in wall["openings"]:
			if y >= opening["sill"] and y <= opening["sill"] + opening["height"]:
				var cut: Array[Vector2] = []
				for span: Vector2 in spans:
					var low: float = opening["start"]
					var high: float = low + opening["width"]
					if high <= span.x or low >= span.y:
						cut.append(span)
					else:
						if span.x < low:
							cut.append(Vector2(span.x, low))
						if high < span.y:
							cut.append(Vector2(high, span.y))
				spans = cut
		for span: Vector2 in spans:
			g.box(
				kit + "_trim",
				wall["a"] + u * (span.x + span.y) / 2 + Vector3.UP * y,
				Vector3(span.y - span.x, 0.12, 0.07),
				false,
				basis
			)
	if kit != "deco":
		return
	for layer: int in 3:
		g.box(
			"deco_accent",
			(wall["a"] + wall["b"]) / 2 + Vector3.UP * (height - 0.25 - layer * 0.09),
			Vector3(length, 0.045, 0.07 + layer * 0.03),
			false,
			basis
		)
	for index: int in range(1, floori(length / 2.0)):
		var x := index * 2.0
		var blocked := false
		for opening: Dictionary in wall["openings"]:
			blocked = (
				blocked
				or (x > opening["start"] - 0.3 and x < opening["start"] + opening["width"] + 0.3)
			)
		if blocked:
			continue
		for offset: float in [-0.07, 0, 0.07]:
			g.box(
				"deco_accent",
				wall["a"] + u * (x + offset) + Vector3.UP * height / 2,
				Vector3(0.025, height - 0.9, 0.09),
				false,
				basis
			)


static func frame(
	g: Geometry, kit: String, at: Vector3, basis: Basis, width: float, height: float, window: bool
) -> void:
	for x: float in [-width / 2, width / 2]:
		g.box(
			kit + "_trim",
			at + basis * Vector3(x, height / 2, 0),
			Vector3(0.1, height + 0.1, 0.18),
			false,
			basis
		)
	g.box(
		kit + "_trim",
		at + basis * Vector3(0, height, 0),
		Vector3(width + 0.1, 0.1, 0.18),
		false,
		basis
	)
	if window:
		g.box(kit + "_trim", at, Vector3(width + 0.1, 0.1, 0.22), false, basis)
	if kit == "deco":
		for step: int in 3:
			g.box(
				"deco_accent",
				at + basis * Vector3(0, height + 0.12 + step * 0.07, 0),
				Vector3(width + 0.3 - step * 0.2, 0.05, 0.2),
				false,
				basis
			)


static func fixture(g: Geometry, kit: String, at: Vector3) -> void:
	var size := Vector3(1.3, 0.08, 0.7) if kit == "modern" else Vector3(1.1, 0.1, 0.18)
	if kit == "deco":
		for step: int in 3:
			g.box(
				"deco_trim",
				at + Vector3.DOWN * step * 0.11,
				Vector3(0.7 - step * 0.14, 0.1, 0.7 - step * 0.14)
			)
		g.box("deco_light", at + Vector3.DOWN * 0.28, Vector3(0.35, 0.12, 0.35))
	else:
		g.box(kit + "_trim", at, size + Vector3(0.08, 0.03, 0.08))
		g.box(kit + "_light", at + Vector3.DOWN * 0.045, size)


static func door(kit: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Leaf"
	var g := Geometry.new()
	g.materials = Catalog.materials()
	g.box(kit + "_trim", Vector3(0.9, 1.3, 0), Vector3(1.8, 2.6, 0.09), true)
	if kit != "concrete":
		g.box(kit + "_wall", Vector3(0.9, 1.4, 0), Vector3(1.5, 2.1, 0.105))
	if kit == "deco":
		for x: float in [0.72, 0.9, 1.08]:
			g.box("deco_accent", Vector3(x, 1.5, 0), Vector3(0.035, 1.7, 0.12))
	for z: float in [-0.1, 0.1]:
		g.box(kit + "_accent", Vector3(1.55, 1.05, z), Vector3(0.18, 0.05, 0.12))
	if kit == "concrete":
		g.box("concrete_accent", Vector3(0.9, 0.24, 0), Vector3(1.6, 0.35, 0.11))
	g.finish(root)
	return root
