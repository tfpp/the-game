extends RefCounted
## Mesh modelling primitives: swept profiles, mitred mouldings, lathed/fluted forms.
## Every contour point becomes a real edge loop. No CSG or engine primitive meshes.

const Geometry := preload("res://features/world_builder/geometry.gd")


static func sweep(
	g: Geometry,
	material: String,
	origin: Vector3,
	basis: Basis,
	length: float,
	profile: Array[Vector2]
) -> void:
	# Local X follows the run. Profile X is local Y; profile Y is local Z.
	var area := 0.0
	for i: int in profile.size():
		var next := profile[(i + 1) % profile.size()]
		area += profile[i].cross(next)
	for i: int in profile.size():
		var a := profile[i]
		var b := profile[(i + 1) % profile.size()]
		var edge := b - a
		var normal := basis * Vector3(0, edge.y, -edge.x).normalized() * signf(area)
		g.quad(
			material,
			[
				origin + basis * Vector3(0, a.x, a.y),
				origin + basis * Vector3(length, a.x, a.y),
				origin + basis * Vector3(length, b.x, b.y),
				origin + basis * Vector3(0, b.x, b.y)
			],
			normal,
			false
		)
	var indices := Geometry2D.triangulate_polygon(PackedVector2Array(profile))
	for end: float in [0.0, length]:
		for i: int in range(0, indices.size(), 3):
			var points: Array[Vector3] = []
			for j: int in 3:
				var point := profile[indices[i + j]]
				points.append(origin + basis * Vector3(end, point.x, point.y))
			g.quad(material, points, basis.x * (-1 if end == 0 else 1), false)


static func frame(
	g: Geometry,
	material: String,
	origin: Vector3,
	basis: Basis,
	rect: Rect2,
	profile: Array[Vector2],
	bottom: bool = true
) -> void:
	# Concentric rectangles join with diagonal mitres; profile = outward width, depth.
	for ring: int in profile.size() - 1:
		var a := _rect_loop(rect.grow(profile[ring].x), profile[ring].y)
		var b := _rect_loop(rect.grow(profile[ring + 1].x), profile[ring + 1].y)
		for side: int in 4:
			if side == 0 and not bottom:
				continue
			var next := (side + 1) % 4
			var local: Array[Vector3] = [a[side], a[next], b[next], b[side]]
			var normal := (local[1] - local[0]).cross(local[2] - local[0]).normalized()
			if normal.z < 0:
				normal = -normal
			var points: Array[Vector3] = []
			for point: Vector3 in local:
				points.append(origin + basis * point)
			g.quad(material, points, (basis.inverse().transposed() * normal).normalized(), false)


static func _rect_loop(rect: Rect2, depth: float) -> Array[Vector3]:
	return [
		Vector3(rect.position.x, rect.position.y, depth),
		Vector3(rect.end.x, rect.position.y, depth),
		Vector3(rect.end.x, rect.end.y, depth),
		Vector3(rect.position.x, rect.end.y, depth)
	]


static func lathe(
	g: Geometry,
	material: String,
	origin: Vector3,
	basis: Basis,
	profile: Array[Vector2],
	segments: int = 24,
	half: bool = false,
	flutes: int = 0
) -> void:
	# Profile = radius, height. Engaged columns use only their exposed half circumference.
	var angle_start := -PI / 2.0 if half else 0.0
	var angle_range := PI if half else TAU
	for row: int in profile.size() - 1:
		for segment: int in segments:
			var angle_a := angle_start + segment * angle_range / segments
			var angle_b := angle_start + (segment + 1) * angle_range / segments
			var lower := profile[row]
			var upper := profile[row + 1]
			# End rings meet the unfluted base/capital without open wedge-shaped gaps.
			var lower_flutes := flutes if row > 0 else 0
			var upper_flutes := flutes if row + 1 < profile.size() - 1 else 0
			var points: Array[Vector3] = [
				_ring_point(lower, angle_a, lower_flutes),
				_ring_point(lower, angle_b, lower_flutes),
				_ring_point(upper, angle_b, upper_flutes),
				_ring_point(upper, angle_a, upper_flutes),
			]
			var normal := (points[1] - points[0]).cross(points[3] - points[0]).normalized()
			var radial := Vector3(cos((angle_a + angle_b) / 2), 0, sin((angle_a + angle_b) / 2))
			if normal.dot(radial) < 0:
				normal = -normal
			var normals: Array[Vector3] = []
			var normal_basis := basis.inverse().transposed()
			for i: int in 4:
				var angle := angle_a if i in [0, 3] else angle_b
				var ring := lower if i < 2 else upper
				var ring_flutes := lower_flutes if i < 2 else upper_flutes
				var tangent := (
					_ring_point(ring, angle + 0.001, ring_flutes)
					- _ring_point(ring, angle - 0.001, ring_flutes)
				)
				var rise := (
					_ring_point(upper, angle, upper_flutes)
					- _ring_point(lower, angle, lower_flutes)
				)
				var smooth := rise.cross(tangent).normalized()
				if smooth.is_zero_approx():
					smooth = normal
				elif smooth.dot(normal) < 0:
					smooth = -smooth
				normals.append((normal_basis * smooth).normalized())
			for i: int in points.size():
				points[i] = origin + basis * points[i]
			g.quad(material, points, (normal_basis * normal).normalized(), false, normals)


static func _ring_point(profile: Vector2, angle: float, flutes: int) -> Vector3:
	var radius := profile.x
	if flutes > 0:
		radius *= 1.0 - 0.12 * pow(maxf(0, cos(angle * flutes)), 2)
	return Vector3(cos(angle) * radius, profile.y, sin(angle) * radius)


static func tube(
	g: Geometry, material: String, points: Array[Vector3], radius: float, segments: int = 8
) -> void:
	# Shared rings use the tangent at each centerline point, so bends have no cracks.
	var rings: Array[Array] = []
	for i: int in points.size():
		var direction := (
			(points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		)
		var helper := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.95 else Vector3.UP
		var x := direction.cross(helper).normalized()
		var z := direction.cross(x).normalized()
		var ring: Array[Vector3] = []
		for segment: int in segments:
			var angle := segment * TAU / segments
			ring.append(points[i] + (x * cos(angle) + z * sin(angle)) * radius)
		rings.append(ring)
	for section: int in points.size() - 1:
		for segment: int in segments:
			var next := (segment + 1) % segments
			var normal: Vector3 = (
				((rings[section][segment] + rings[section][next]) / 2.0 - points[section])
				. normalized()
			)
			g.quad(
				material,
				[
					rings[section][segment],
					rings[section][next],
					rings[section + 1][next],
					rings[section + 1][segment]
				],
				normal,
				false
			)
