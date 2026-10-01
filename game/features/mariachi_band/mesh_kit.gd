class_name MariachiMeshKit
extends RefCounted
## Collects low-poly boxes, cylinders and rings into one vertex-coloured mesh, so a
## musician's sombrero, suit trim and instrument cost one draw call per rig pivot
## instead of one per part. Untextured and matte like the patrons' accessories; draw
## the result with the shared `vertex_color.tres`.

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()


func box(at: Transform3D, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(mesh, at, color)


## A cylinder (or cone/dish) along `at`'s Y axis.
func cylinder(
	at: Transform3D, top: float, bottom: float, height: float, color: Color, sides: int = 10
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 0
	_append(mesh, at, color)


## A ring around `at`'s Y axis.
func ring(at: Transform3D, inner: float, outer: float, color: Color, sides: int = 14) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = sides
	mesh.ring_segments = 4
	_append(mesh, at, color)


func is_empty() -> bool:
	return _vertices.is_empty()


func commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func triangle_count() -> int:
	return _indices.size() / 3


func _append(mesh: PrimitiveMesh, at: Transform3D, color: Color) -> void:
	var arrays := mesh.get_mesh_arrays()
	var offset := _vertices.size()
	var normal_basis := at.basis.inverse().transposed()
	for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		_vertices.append(at * vertex)
		_colors.append(color)
	for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array:
		_normals.append((normal_basis * normal).normalized())
	for index: int in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
		_indices.append(offset + index)
