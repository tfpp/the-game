class_name PlayerChest
extends RefCounted
## One cached morph of the imported torso, not extra body-part meshes.
## Keep original indices, UVs, skin weights and all five existing blend shapes.

const SHAPE := "FullChest"
const PROJECTION := 0.16
const CENTER := Vector2(0.095, 0.295)
const RADIUS := Vector2(0.115, 0.125)

static var _shared_mesh: ArrayMesh


static func mesh_for(source: ArrayMesh) -> ArrayMesh:
	if _shared_mesh != null:
		return _shared_mesh
	var mesh := ArrayMesh.new()
	mesh.blend_shape_mode = source.blend_shape_mode
	for index: int in source.get_blend_shape_count():
		mesh.add_blend_shape(source.get_blend_shape_name(index))
	mesh.add_blend_shape(SHAPE)
	var arrays := source.surface_get_arrays(0)
	var shapes := source.surface_get_blend_shape_arrays(0)
	var chest: Array = []
	chest.resize(Mesh.ARRAY_MAX)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var moved := vertices.duplicate()
	var tilted := normals.duplicate()
	for index: int in vertices.size():
		var offset := projection_at(vertices[index])
		moved[index].z -= offset
		if offset > 0.0:
			tilted[index] = _normal_at(vertices[index], normals[index])
	chest[Mesh.ARRAY_VERTEX] = moved
	chest[Mesh.ARRAY_NORMAL] = tilted
	# No normal map is used; retain the original tangent data and UV charts.
	chest[Mesh.ARRAY_TANGENT] = arrays[Mesh.ARRAY_TANGENT]
	shapes.append(chest)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	mesh.surface_set_material(0, source.surface_get_material(0))
	# Godot derives the base AABB without the extra morph. Reserve its maximum
	# front projection so it cannot disappear at camera/frustum edges.
	var bounds := source.get_aabb()
	bounds.position.z -= PROJECTION
	bounds.size.z += PROJECTION
	mesh.custom_aabb = bounds
	_shared_mesh = mesh
	return mesh


## -Z is the human's front. Compact paired profiles taper to zero before the
## shoulder joins, neck and waist; hands, back, legs and head are unchanged.
static func projection_at(position: Vector3) -> float:
	var point := (Vector2(absf(position.x), position.y) - CENTER) / RADIUS
	var profile := maxf(0.0, 1.0 - point.length_squared())
	return PROJECTION * smoothstep(0.0, 1.0, profile) * smoothstep(0.0, 0.065, -position.z)


static func _normal_at(position: Vector3, normal: Vector3) -> Vector3:
	# Inverse-transpose of the smooth displacement Jacobian preserves lighting
	# without changing smoothing or hard-edge normals elsewhere on the avatar.
	const STEP := 0.001
	var slope := Vector3(
		(
			(
				projection_at(position + Vector3.RIGHT * STEP)
				- projection_at(position - Vector3.RIGHT * STEP)
			)
			/ (2.0 * STEP)
		),
		(
			(
				projection_at(position + Vector3.UP * STEP)
				- projection_at(position - Vector3.UP * STEP)
			)
			/ (2.0 * STEP)
		),
		(
			(
				projection_at(position + Vector3.BACK * STEP)
				- projection_at(position - Vector3.BACK * STEP)
			)
			/ (2.0 * STEP)
		)
	)
	var z := normal.z / (1.0 - slope.z)
	return Vector3(normal.x + slope.x * z, normal.y + slope.y * z, z).normalized()
