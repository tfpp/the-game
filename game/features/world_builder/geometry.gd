extends RefCounted
## Material/sector mesh batches, plus matching collision for structural surfaces.

var cast_shadows := true
var lightmap_detail := false
var materials: Dictionary[String, Material] = {}
var surfaces: Dictionary[String, SurfaceTool] = {}
var faces: Dictionary[String, PackedVector3Array] = {}
var sector_keys: Dictionary[String, String] = {}


func quad(
	material: String,
	points: Array[Vector3],
	normal: Vector3,
	solid: bool = true,
	vertex_normals: Array[Vector3] = []
) -> void:
	if (points[2] - points[0]).cross(points[1] - points[0]).dot(normal) < 0:
		if points.size() == 3:
			points = [points[0], points[2], points[1]]
			if not vertex_normals.is_empty():
				vertex_normals = [vertex_normals[0], vertex_normals[2], vertex_normals[1]]
		else:
			points = [points[0], points[3], points[2], points[1]]
			if not vertex_normals.is_empty():
				vertex_normals = [
					vertex_normals[0], vertex_normals[3], vertex_normals[2], vertex_normals[1]
				]
	var center := (points[0] + points[2]) * 0.5
	var sector := "%d_%d" % [floori(center.x / 16.0), floori(center.z / 16.0)]
	if not cast_shadows or material == "glass":
		sector += "_unshadowed"
	elif lightmap_detail:
		sector += "_detail"
	var key := sector + "/" + material
	if not material.is_empty() and not surfaces.has(key):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(materials[material])
		surfaces[key] = tool
		sector_keys[key] = sector
	var tool: SurfaceTool = surfaces.get(key)
	var indices: Array[int] = [0, 1, 2]
	if points.size() == 4:
		indices = [0, 1, 2, 0, 2, 3]
	for index: int in indices:
		var point := points[index]
		var uv := Vector2(point.x, point.z)
		if absf(normal.y) < 0.5:
			uv = Vector2(point.z if absf(normal.x) > 0.5 else point.x, -point.y)
		if tool != null:
			var vertex_normal := normal if vertex_normals.is_empty() else vertex_normals[index]
			var shade := 0.88 + 0.12 * vertex_normal.dot(Vector3(-0.4, 0.8, 0.3).normalized())
			tool.set_normal(vertex_normal)
			tool.set_color(Color(shade, shade, shade))
			tool.set_uv(uv)
			tool.add_vertex(point)
		if solid:
			if not faces.has(sector):
				faces[sector] = PackedVector3Array()
			faces[sector].append(point)


func box(
	material: String,
	center: Vector3,
	size: Vector3,
	solid: bool = false,
	basis: Basis = Basis.IDENTITY
) -> void:
	var corners: Array[Vector3] = []
	for z: float in [-0.5, 0.5]:
		for y: float in [-0.5, 0.5]:
			for x: float in [-0.5, 0.5]:
				corners.append(center + basis * (Vector3(x, y, z) * size))
	var indices: Array[Array] = [
		[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]
	]
	var normals: Array[Vector3] = [
		Vector3.FORWARD, Vector3.BACK, Vector3.DOWN, Vector3.UP, Vector3.LEFT, Vector3.RIGHT
	]
	for i: int in 6:
		var face: Array[Vector3] = []
		for index: int in indices[i]:
			face.append(corners[index])
		quad(material, face, basis * normals[i], solid)


func finish(root: Node3D) -> void:
	var meshes: Dictionary[String, ArrayMesh] = {}
	for key: String in surfaces:
		var sector: String = sector_keys[key]
		if not meshes.has(sector):
			meshes[sector] = ArrayMesh.new()
		surfaces[key].commit(meshes[sector])
	for sector: String in meshes:
		var instance := MeshInstance3D.new()
		instance.name = "Chunk_" + sector
		instance.mesh = meshes[sector]
		# Interior shells face inward; both sides must occlude outside sunlight.
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if sector.ends_with("_unshadowed")
			else GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		)
		attach(root, instance, root)
		if faces.has(sector):
			var body := StaticBody3D.new()
			body.name = "Solid"
			attach(instance, body, root)
			var collision := CollisionShape3D.new()
			collision.name = "Collision"
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces[sector])
			collision.shape = shape
			collision.add_to_group(&"radar_geometry", true)
			attach(body, collision, root)


static func attach(parent: Node, child: Node, root: Node) -> void:
	parent.add_child(child)
	child.owner = root
