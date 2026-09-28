class_name SlotReelMesh
extends RefCounted
## Curved drum face, UVs follow the arc so reel printing rolls through the window.


static func create() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	const SEGMENTS := 8
	for row: int in range(SEGMENTS + 1):
		var v := float(row) / SEGMENTS
		var angle := lerpf(-1.1, 1.1, v)
		for side: int in 2:
			vertices.append(
				Vector3((float(side) - 0.5) * 0.52, -sin(angle) * 0.43, cos(angle) * 0.38)
			)
			normals.append(Vector3(0, -sin(angle), cos(angle)))
			uvs.append(Vector2(float(side), v))
	for row: int in SEGMENTS:
		var a := row * 2
		indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func next_stop(current: float, symbol: int) -> float:
	return current + fposmod(float(symbol) - current, 5.0)
