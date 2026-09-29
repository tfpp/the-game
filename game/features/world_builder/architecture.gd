extends RefCounted
## Procedural wall profiles, joinery, columns, rugs and light fittings.

const Geometry := preload("res://features/world_builder/geometry.gd")
const Profiles := preload("res://features/world_builder/profiles.gd")
const ROUND_SIDES := 8
const Joinery := preload("res://features/world_builder/joinery.gd")

var _g: Geometry
var _style: Dictionary
var _root: Node3D
var _light_count := 0
var _sconce_count := 0


func build(geometry: Geometry, layout: Dictionary, root: Node3D) -> void:
	_g = geometry
	_style = layout["style"]
	_root = root
	for wall: Dictionary in layout["walls"]:
		_wall(wall)
	for pillar: Dictionary in layout["pillars"]:
		_column(pillar["position"], pillar["height"], _style["pillar_width"] * 1.5)
	for room_id: String in layout["rooms"]:
		var rect: Rect2i = layout["rooms"][room_id]
		var scale: float = layout["cell_size"]
		var center := Vector3(
			(rect.position.x + rect.size.x * 0.5) * scale,
			0,
			(rect.position.y + rect.size.y * 0.5) * scale
		)
		var size := Vector3(rect.size.x * scale - 1.6, 0.008, rect.size.y * scale - 1.6)
		_flat("gold", center + Vector3.UP * 0.009, size)
		_flat("carpet", center + Vector3.UP * 0.015, size - Vector3(0.18, 0, 0.18))
		var height: float = layout["heights"][rect.position]
		if layout["ceiling"]:
			_ceiling_frame(center, size, height)
			if _style["lights"]:
				_pendant(center, height)
	_hall_details(layout)


func _hall_details(layout: Dictionary) -> void:
	var scale: float = layout["cell_size"]
	for path: Array in layout["paths"]:
		for i: int in 2:
			var a := (Vector2(path[i]) + Vector2.ONE * 0.5) * scale
			var b := (Vector2(path[i + 1]) + Vector2.ONE * 0.5) * scale
			if a.is_equal_approx(b):
				continue
			var along_x := absf(a.x - b.x) > 0.1
			var fixed := a.y if along_x else a.x
			var spans: Array[Vector2] = [
				(
					Vector2(minf(a.x, b.x), maxf(a.x, b.x))
					if along_x
					else Vector2(minf(a.y, b.y), maxf(a.y, b.y))
				)
			]
			for rect: Rect2i in layout["rooms"].values():
				var cross_start := (rect.position.y if along_x else rect.position.x) * scale
				var cross_end := (rect.end.y if along_x else rect.end.x) * scale
				if fixed < cross_start or fixed > cross_end:
					continue
				var low := (rect.position.x if along_x else rect.position.y) * scale
				var high := (rect.end.x if along_x else rect.end.y) * scale
				spans = _subtract(spans, low, high)
			for span: Vector2 in spans:
				var length := span.y - span.x
				var mid := (span.x + span.y) / 2.0
				var center := Vector3(mid, 0.015, fixed) if along_x else Vector3(fixed, 0.015, mid)
				var width := float(layout["hall_width"]) * scale * 0.58
				_flat(
					"gold",
					center,
					Vector3(length, 0.006, width) if along_x else Vector3(width, 0.006, length)
				)
				_flat(
					"carpet",
					center + Vector3.UP * 0.006,
					(
						Vector3(length, 0.006, width - 0.15)
						if along_x
						else Vector3(width - 0.15, 0.006, length)
					)
				)
				if not layout["ceiling"]:
					continue
				var count := maxi(1, roundi(length / 4.0))
				for index: int in count:
					var point := span.x + (index + 0.5) * length / count
					var position := (
						Vector3(point, 0, fixed) if along_x else Vector3(fixed, 0, point)
					)
					var cell := Vector2i(floori(position.x / scale), floori(position.z / scale))
					var height: float = layout["heights"][cell]
					var size := Vector3(
						length / count - 0.25, 0, float(layout["hall_width"]) * scale - 0.5
					)
					if not along_x:
						size = Vector3(size.z, 0, size.x)
					_ceiling_frame(position, size, height)
					if index % 2 == 0 and _style["lights"]:
						_pendant(position, height)


func _subtract(spans: Array[Vector2], low: float, high: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for span: Vector2 in spans:
		if low >= span.y or high <= span.x:
			result.append(span)
		else:
			if low > span.x:
				result.append(Vector2(span.x, low))
			if high < span.y:
				result.append(Vector2(high, span.y))
	return result


func _wall(wall: Dictionary) -> void:
	var length: float = wall["a"].distance_to(wall["b"])
	var height: float = wall["height"]
	var dado: float = _style["wainscot_height"]
	_band(wall, 0.10, 0.20, 0.10, "wood")
	_band(wall, dado - 0.04, 0.12, 0.10, "wood")
	_band(wall, dado + 0.045, 0.035, 0.13, "gold")
	for layer: int in 4:
		_band(
			wall,
			height - 0.30 + layer * 0.075,
			0.075,
			_style["trim_depth"] * (1.0 + layer * 0.45),
			"plaster" if layer != 1 else "gold"
		)
	var count := maxi(1, roundi(length / float(_style["panel_spacing"])))
	var bay := length / count
	for i: int in count:
		var start := i * bay + 0.23
		var width := bay - 0.46
		if not _blocked(wall, start, width):
			_frame(wall, start + 0.1, 0.28, width - 0.2, dado - 0.50, 0.025, 0.055, "gold")
			_frame(
				wall,
				start + 0.08,
				dado + 0.3,
				width - 0.16,
				height - dado - 0.85,
				0.035,
				0.04,
				"plaster"
			)
			if i % 2 == 0 and _style["lights"]:
				_sconce(wall, start + width / 2, minf(height - 0.65, dado + 1.0))
	for i: int in range(count + 1):
		var x := clampf(i * bay, 0.25, length - 0.25)
		var width: float = _style["pillar_width"]
		if not _blocked(wall, x - width * 0.75, width * 1.5):
			_pilaster(wall, x, height)
	for opening: Dictionary in wall["openings"]:
		_opening(wall, opening)


func _blocked(wall: Dictionary, start: float, width: float) -> bool:
	for opening: Dictionary in wall["openings"]:
		if (
			start < opening["start"] + opening["width"] + 0.22
			and start + width > opening["start"] - 0.22
		):
			return true
	return false


func _band(wall: Dictionary, y: float, height: float, depth: float, material: String) -> void:
	var length: float = wall["a"].distance_to(wall["b"])
	var spans: Array[Vector2] = [Vector2(0, length)]
	for opening: Dictionary in wall["openings"]:
		if y + height / 2 < opening["sill"] or y - height / 2 > opening["sill"] + opening["height"]:
			continue
		spans = _subtract(spans, opening["start"], opening["start"] + opening["width"])
	var u: Vector3 = (wall["b"] - wall["a"]).normalized()
	var basis := Basis(u, Vector3.UP, wall["normal"])
	var profile: Array[Vector2] = [
		Vector2(-0.5 * height, 0),
		Vector2(-0.5 * height, depth * 0.3),
		Vector2(-0.4 * height, depth * 0.65),
		Vector2(-0.25 * height, depth * 0.85),
		Vector2(-0.1 * height, depth),
		Vector2(0.05 * height, depth * 0.9),
		Vector2(0.15 * height, depth * 0.5),
		Vector2(0.3 * height, depth * 0.45),
		Vector2(0.42 * height, depth * 0.85),
		Vector2(0.5 * height, depth),
		Vector2(0.5 * height, 0),
	]
	for span: Vector2 in spans:
		Profiles.sweep(
			_g, material, wall["a"] + u * span.x + Vector3.UP * y, basis, span.y - span.x, profile
		)


func _wall_box(
	wall: Dictionary, material: String, center: Vector3, size: Vector3, solid: bool = false
) -> void:
	var u: Vector3 = (wall["b"] - wall["a"]).normalized()
	var basis := Basis(u, Vector3.UP, wall["normal"])
	var position: Vector3 = wall["a"] + basis * center
	if material.is_empty() or material == "glass":
		_g.box(material, position, size, solid, basis)
		return
	var y := size.y / 2.0
	var z := size.z / 2.0
	var bevel := minf(0.025, minf(y, z) * 0.35)
	Profiles.sweep(
		_g,
		material,
		position - u * size.x / 2.0,
		basis,
		size.x,
		[
			Vector2(-y + bevel, -z),
			Vector2(y - bevel, -z),
			Vector2(y, -z + bevel),
			Vector2(y, z - bevel),
			Vector2(y - bevel, z),
			Vector2(-y + bevel, z),
			Vector2(-y, z - bevel),
			Vector2(-y, -z + bevel)
		]
	)
	if solid:
		_g.box("", position, size, true, basis)


func _frame(
	wall: Dictionary,
	x: float,
	y: float,
	width: float,
	height: float,
	thickness: float,
	depth: float,
	material: String,
	bottom: bool = true
) -> void:
	if width <= 0 or height <= 0:
		return
	var u: Vector3 = (wall["b"] - wall["a"]).normalized()
	var basis := Basis(u, Vector3.UP, wall["normal"])
	(
		Profiles
		. frame(
			_g,
			material,
			wall["a"],
			basis,
			Rect2(x, y, width, height),
			[
				Vector2(0, 0.008),
				Vector2(thickness * 0.2, depth * 0.65),
				Vector2(thickness * 0.4, depth),
				Vector2(thickness * 0.6, depth * 0.9),
				Vector2(thickness * 0.75, depth * 0.45),
				Vector2(thickness, 0.008),
			],
			bottom
		)
	)


func _pilaster(wall: Dictionary, x: float, height: float) -> void:
	var u: Vector3 = (wall["b"] - wall["a"]).normalized()
	var width: float = _style["pillar_width"]
	var depth: float = _style["pillar_depth"]
	var position: Vector3 = wall["a"] + u * x
	var basis := Basis(wall["normal"] * depth / (width / 2.0), Vector3.UP, u)
	_column_mesh(position, height, width, basis, true)
	_wall_box(
		wall,
		"",
		Vector3(x, height / 2, depth * 0.6),
		Vector3(width * 1.3, height, depth * 1.2),
		true
	)


func _column_mesh(position: Vector3, height: float, width: float, basis: Basis, half: bool) -> void:
	_g.lightmap_detail = true
	var r := width / 2.0
	var segments := ROUND_SIDES / 2 if half else ROUND_SIDES
	var base: Array[Vector2] = [
		Vector2(r * 1.3, 0),
		Vector2(r * 1.3, 0.06),
		Vector2(r * 1.15, 0.09),
		Vector2(r * 1.08, 0.12),
		Vector2(r * 1.2, 0.16),
		Vector2(r * 1.24, 0.20),
		Vector2(r * 1.17, 0.25),
		Vector2(r, 0.29),
		Vector2(r * 0.94, 0.34),
	]
	Profiles.lathe(_g, "plaster", position, basis, base, segments, half)
	Profiles.lathe(
		_g,
		"plaster",
		position,
		basis,
		[
			Vector2(r * 0.94, 0.34),
			Vector2(r, height * 0.25),
			Vector2(r * 0.96, height * 0.6),
			Vector2(r * 0.85, height - 0.4)
		],
		segments,
		half
	)
	Profiles.lathe(
		_g,
		"gold",
		position,
		basis,
		[
			Vector2(r * 0.87, height - 0.42),
			Vector2(r * 0.98, height - 0.40),
			Vector2(r * 0.98, height - 0.36)
		],
		segments,
		half
	)
	Profiles.lathe(
		_g,
		"plaster",
		position,
		basis,
		[
			Vector2(r * 0.98, height - 0.36),
			Vector2(r, height - 0.30),
			Vector2(r * 1.12, height - 0.26),
			Vector2(r * 1.25, height - 0.23),
			Vector2(r * 1.34, height - 0.18),
			Vector2(r * 1.4, height - 0.10),
			Vector2(r * 1.4, height - 0.04),
			Vector2(r * 1.25, height)
		],
		segments,
		half
	)
	_g.lightmap_detail = false


func _opening(wall: Dictionary, opening: Dictionary) -> void:
	var x: float = opening["start"]
	var width: float = opening["width"]
	var y: float = opening["sill"]
	var height: float = opening["height"]
	_frame(
		wall,
		x - 0.11,
		y,
		width + 0.22,
		height + 0.08,
		0.18,
		0.08,
		"plaster",
		opening["kind"] == "window"
	)
	_frame(wall, x, y, width, height, 0.075, 0.13, "wood", opening["kind"] == "window")
	_frame(
		wall,
		x - 0.055,
		y,
		width + 0.11,
		height + 0.04,
		0.025,
		0.18,
		"gold",
		opening["kind"] == "window"
	)
	# A real cut opening has reveals, a header and (for windows) a sill.
	for side: float in [x, x + width]:
		_wall_box(wall, "wood", Vector3(side, y + height / 2, -0.08), Vector3(0.06, height, 0.24))
	_wall_box(
		wall,
		"plaster",
		Vector3(x + width / 2, y + height + 0.15, 0.1),
		Vector3(width + 0.5, 0.16, 0.28)
	)
	var marker := Marker3D.new()
	marker.name = opening["id"]
	var u: Vector3 = (wall["b"] - wall["a"]).normalized()
	marker.position = wall["a"] + u * (x + width / 2) + Vector3.UP * y
	marker.rotation.y = atan2(-wall["normal"].x, -wall["normal"].z)
	marker.set_meta("kind", opening["kind"])
	Geometry.attach(_root.get_node("Openings"), marker, _root)
	if opening["kind"] == "window":
		_wall_box(
			wall,
			"glass",
			Vector3(x + width / 2, y + height / 2, -0.02),
			Vector3(width, height, 0.02),
			true
		)
		_wall_box(
			wall, "wood", Vector3(x + width / 2, y + height / 2, 0.07), Vector3(0.055, height, 0.08)
		)
		for level: float in [0.32, 0.66]:
			_wall_box(
				wall,
				"wood",
				Vector3(x + width / 2, y + height * level, 0.07),
				Vector3(width, 0.055, 0.08)
			)
		_wall_box(
			wall, "plaster", Vector3(x + width / 2, y, 0.08), Vector3(width + 0.3, 0.09, 0.45)
		)
	else:
		_door(wall, opening)


func _door(wall: Dictionary, opening: Dictionary) -> void:
	var u: Vector3 = (wall["b"] - wall["a"]).normalized()
	var n: Vector3 = wall["normal"]
	var is_open: bool = opening.get("open", false)
	var width: float = opening["width"] - (0.08 if is_open else 0.0)
	var height: float = opening["height"] - (0.04 if is_open else -0.005)
	var hinge: Vector3 = wall["a"] + u * (opening["start"] + (0.04 if is_open else 0.0))
	var axis := -n if is_open else u
	var front := u if is_open else n
	Joinery.door(_g, hinge, Basis(axis, Vector3.UP, front), width, height)


func _column(position: Vector3, height: float, width: float) -> void:
	_column_mesh(position, height, width, Basis.IDENTITY, false)
	_g.box("", position + Vector3.UP * height / 2, Vector3(width * 1.4, height, width * 1.4), true)


func _ceiling_frame(center: Vector3, size: Vector3, height: float) -> void:
	var basis := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	Profiles.frame(
		_g,
		"plaster",
		center + Vector3.UP * height,
		basis,
		Rect2(-size.x / 2, -size.z / 2, size.x, size.z),
		[
			Vector2(0, 0),
			Vector2(0.025, 0.04),
			Vector2(0.055, 0.06),
			Vector2(0.08, 0.035),
			Vector2(0.11, 0.02),
			Vector2(0.14, 0.07),
			Vector2(0.17, 0.08),
			Vector2(0.2, 0)
		]
	)


func _sconce(wall: Dictionary, x: float, y: float) -> void:
	_g.cast_shadows = false
	var u: Vector3 = (wall["b"] - wall["a"]).normalized()
	var n: Vector3 = wall["normal"]
	var mount: Vector3 = wall["a"] + u * x + Vector3.UP * (y - 0.15)
	Profiles.lathe(
		_g,
		"gold",
		mount,
		Basis(u, n, Vector3.UP),
		[Vector2(0.10, 0), Vector2(0.12, 0.025), Vector2(0.10, 0.055), Vector2(0.045, 0.07)],
		ROUND_SIDES
	)
	for side: float in [-1, 1]:
		var arm: Array[Vector3] = []
		for step: int in 9:
			var t := step / 8.0
			arm.append(
				(
					mount
					+ u * side * 0.17 * sin(t * PI / 2)
					+ n * (0.05 + 0.24 * sin(t * PI / 2))
					+ Vector3.UP * (0.18 * t * t - 0.10 * sin(t * PI))
				)
			)
		Profiles.tube(_g, "gold", arm, 0.018)
		var bulb := arm[-1]
		Profiles.lathe(
			_g,
			"gold",
			bulb,
			Basis.IDENTITY,
			[Vector2(0.02, -0.025), Vector2(0.055, 0), Vector2(0.068, 0.018), Vector2(0.045, 0.04)],
			ROUND_SIDES
		)
		Profiles.lathe(
			_g,
			"glow",
			bulb,
			Basis.IDENTITY,
			[
				Vector2(0.035, 0.04),
				Vector2(0.075, 0.065),
				Vector2(0.065, 0.19),
				Vector2(0.04, 0.27),
				Vector2(0.005, 0.29)
			],
			ROUND_SIDES
		)

	# Small wall lights complement the broad pendant light instead of pretending
	# the unshaded bulb mesh illuminates the wall. Reserve sixteen slots for pendants.
	if _sconce_count < 32:
		_add_light("Sconce", mount + n * 0.48 + Vector3.UP * 0.2, 0.65, 3.2, false)
		_sconce_count += 1
	_g.cast_shadows = true


func _pendant(center: Vector3, height: float) -> void:
	_g.cast_shadows = false
	var drop := minf(0.9, height - 2.15)
	Profiles.lathe(
		_g,
		"gold",
		center + Vector3.UP * (height - 0.06),
		Basis.IDENTITY,
		[Vector2(0.09, 0), Vector2(0.14, 0.025), Vector2(0.14, 0.05)],
		ROUND_SIDES
	)
	var position := center + Vector3.UP * (height - drop)
	_bowl(
		position,
		"glow",
		[Vector2(0.10, 0), Vector2(0.26, 0.06), Vector2(0.39, 0.18), Vector2(0.45, 0.30)]
	)
	_bowl(
		position,
		"gold",
		[Vector2(0.46, 0.28), Vector2(0.47, 0.31), Vector2(0.47, 0.35), Vector2(0.44, 0.36)]
	)
	for index: int in 3:
		var angle := index * TAU / 3.0
		var end := position + Vector3(cos(angle) * 0.42, 0.33, sin(angle) * 0.42)
		var start := center + Vector3.UP * (height - 0.08)
		Profiles.tube(_g, "gold", [start, end], 0.012)
	_add_light("Pendant", position - Vector3.UP * 0.2, 1.05, 7.0, true)
	_g.cast_shadows = true


func _add_light(label: String, at: Vector3, energy: float, radius: float, shadows: bool) -> void:
	if _light_count >= 48:
		return
	var light := OmniLight3D.new()
	light.name = "%sLight%d" % [label, _light_count]
	light.position = at
	light.light_color = Color("ffe8c9")
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.5
	light.shadow_enabled = shadows
	light.shadow_bias = 0.025
	light.shadow_normal_bias = 0.15
	Geometry.attach(_root, light, _root)
	_light_count += 1


func _bowl(center: Vector3, material: String, profile: Array[Vector2]) -> void:
	Profiles.lathe(_g, material, center, Basis.IDENTITY, profile, ROUND_SIDES)


func _flat(material: String, center: Vector3, size: Vector3) -> void:
	_g.quad(
		material,
		[
			center + Vector3(-size.x / 2, 0, -size.z / 2),
			center + Vector3(size.x / 2, 0, -size.z / 2),
			center + Vector3(size.x / 2, 0, size.z / 2),
			center + Vector3(-size.x / 2, 0, size.z / 2)
		],
		Vector3.UP,
		false
	)
