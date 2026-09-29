extends RefCounted
## Recessed panel doors with continuous bevel loops, moulded stiles and turned hardware.

const Geometry := preload("res://features/world_builder/geometry.gd")
const Profiles := preload("res://features/world_builder/profiles.gd")


static func door(g: Geometry, origin: Vector3, basis: Basis, width: float, height: float) -> void:
	var panels: Array[Rect2] = []
	var rail := 0.14
	for column: int in 2:
		var panel_width := (width - rail * 3) / 2.0
		var x := rail + column * (panel_width + rail)
		panels.append(Rect2(x, 0.18, panel_width, height * 0.32 - 0.18))
		panels.append(Rect2(x, height * 0.32 + 0.13, panel_width, height * 0.68 - 0.31))
	var x_cuts: Array[float] = [0.025, width - 0.025]
	var y_cuts: Array[float] = [0.025, height - 0.025]
	for panel: Rect2 in panels:
		x_cuts.append(panel.position.x)
		x_cuts.append(panel.end.x)
		y_cuts.append(panel.position.y)
		y_cuts.append(panel.end.y)
	x_cuts.sort()
	y_cuts.sort()
	for x: int in x_cuts.size() - 1:
		for y: int in y_cuts.size() - 1:
			var rect := Rect2(
				x_cuts[x], y_cuts[y], x_cuts[x + 1] - x_cuts[x], y_cuts[y + 1] - y_cuts[y]
			)
			if rect.size.x < 0.0001 or rect.size.y < 0.0001:
				continue
			var cut := false
			for panel: Rect2 in panels:
				if panel.has_point(rect.get_center()):
					cut = true
			if not cut:
				_plane(g, origin, basis, rect, 0.06)
	for panel: Rect2 in panels:
		# Bevels descend into the panel well, then roll back up around its central field.
		var inset := minf(0.075, panel.size.x * 0.18)
		Profiles.frame(
			g,
			"wood",
			origin,
			basis,
			panel,
			[
				Vector2(0, 0.06),
				Vector2(-0.018, 0.075),
				Vector2(-0.033, 0.065),
				Vector2(-0.045, 0.025),
				Vector2(-inset, 0.005)
			]
		)
		_plane(g, origin, basis, panel.grow(-inset), 0.005)
	# Actual bevelled outer edges, rear face and jamb thickness.
	Profiles.frame(
		g,
		"wood",
		origin,
		basis,
		Rect2(0, 0, width, height),
		[Vector2(0, -0.06), Vector2(0, 0.02), Vector2(-0.025, 0.06)]
	)
	_plane(g, origin, Basis(-basis.x, basis.y, -basis.z), Rect2(-width, 0, width, height), 0.06)
	g.box(
		"",
		origin + basis * Vector3(width / 2, height / 2, 0),
		Vector3(width, height, 0.12),
		true,
		basis
	)
	for side: float in [-1, 1]:
		var mount := origin + basis * Vector3(width - 0.12, 1.02, side * 0.065)
		var hardware_basis := Basis(basis.x, basis.z * side, basis.y)
		Profiles.lathe(
			g,
			"gold",
			mount,
			hardware_basis,
			[
				Vector2(0.045, 0),
				Vector2(0.052, 0.008),
				Vector2(0.047, 0.018),
				Vector2(0.025, 0.028),
				Vector2(0.022, 0.07),
				Vector2(0.046, 0.09),
				Vector2(0.055, 0.115),
				Vector2(0.043, 0.14),
				Vector2(0.005, 0.15)
			],
			16
		)
	# Turned hinge barrels sit on the actual hinge edge.
	for y: float in [0.25, height - 0.3]:
		Profiles.lathe(
			g,
			"gold",
			origin + basis * Vector3(0.015, y, 0),
			basis,
			[Vector2(0.025, 0), Vector2(0.025, 0.18), Vector2(0.016, 0.19)],
			12
		)


static func _plane(g: Geometry, origin: Vector3, basis: Basis, rect: Rect2, depth: float) -> void:
	var points: Array[Vector3] = [
		Vector3(rect.position.x, rect.position.y, depth),
		Vector3(rect.end.x, rect.position.y, depth),
		Vector3(rect.end.x, rect.end.y, depth),
		Vector3(rect.position.x, rect.end.y, depth)
	]
	for i: int in points.size():
		points[i] = origin + basis * points[i]
	g.quad("wood", points, basis.z, false)
