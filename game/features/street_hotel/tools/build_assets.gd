extends Node3D
## Bake full floors once; bake a cheap street copy from the real socket district.

const SPEC := preload("res://features/street_hotel/spec.gd")
const FLOOR := preload("res://features/street_hotel/floor_layout.gd")
const STREET := preload("res://features/street_district/layout.gd")
var _surface: SurfaceTool


func _ready() -> void:
	assert(
		DisplayServer.get_name() != "headless",
		"Bake MultiMeshes with a real renderer: use gl_compatibility without --headless"
	)
	DirAccess.make_dir_recursive_absolute("res://assets/street_hotel/floors")
	for index: int in SPEC.FLOORS:
		var floor := FLOOR.build(self, index)
		await get_tree().process_frame
		await get_tree().process_frame
		# Joins and live node references are authoring/test metadata, not baked state.
		floor.remove_meta("joins")
		floor.remove_meta("guest_rooms")
		for room: Node in floor.get_children():
			room.remove_meta("furniture_layout")
		_owner(floor, floor)
		var scene := PackedScene.new()
		assert(scene.pack(floor) == OK)
		assert(
			(
				ResourceSaver.save(
					scene, "res://assets/street_hotel/floors/floor_%02d.scn" % (index + 1)
				)
				== OK
			)
		)
		print(
			"HOTEL_FLOOR_BAKED: ",
			index + 1,
			" / ",
			floor.get_meta("furniture_instances"),
			" props / ",
			floor.get_meta("furniture_batches"),
			" batches"
		)
		floor.free()
	await _proxy()
	_exterior()
	get_tree().quit()


func _proxy() -> void:
	var district := STREET.build(self)
	var root := Node3D.new()
	root.name = "LowDetailStreet"
	add_child(root)
	var groups: Dictionary[String, Array] = {}
	var sources: Dictionary[String, Node3D] = {}
	for node: Node in district.get_children():
		if node.has_meta("prop_id") and node is StaticBody3D:
			var id: String = node.get_meta("prop_id")
			if (
				id
				not in [
					"brick_tenement",
					"corner_store",
					"plaster_apartments",
					"shutter_warehouse",
					"narrow_office",
					"laundry_block",
					"service_workshop",
					"hotel_facade",
					"concrete_commercial",
					"brick_storeroom"
				]
			):
				continue
			if not groups.has(id):
				groups[id] = []
				sources[id] = node
			groups[id].append((node as Node3D).global_transform)
	for id: String in groups:
		var source := sources[id].get_node("Model") as MeshInstance3D
		var original := source.material_override as StandardMaterial3D
		var image := original.albedo_texture.get_image()
		image.resize(32, 32, Image.INTERPOLATE_NEAREST)
		image.generate_mipmaps()
		var path := "res://assets/street_hotel/textures/lod_%s.png" % id
		assert(image.save_png(path) == OK)
		var material := StandardMaterial3D.new()
		material.albedo_texture = ImageTexture.create_from_image(image)
		# Persist as a small native texture resource; no render targets or extra cameras.
		assert(
			(
				ResourceSaver.save(
					material.albedo_texture, "res://assets/street_hotel/textures/lod_%s.res" % id
				)
				== OK
			)
		)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(.65, .7, .75)
		var bounds := source.mesh.get_aabb()
		_surface = SurfaceTool.new()
		_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(bounds.position + bounds.size / 2, bounds.size, 1)
		# Two-window strips preserve the facade rhythm without detailed mesh ornaments.
		for row: int in range(maxi(1, int(bounds.size.y / 3))):
			for x: float in [-1.8, 1.8]:
				_quad(
					Vector3(x, row * 3 + 1.5, bounds.end.z + .01),
					Vector2(1.2, 1.8),
					Basis.IDENTITY,
					0
				)
		var mesh := _surface.commit()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = groups[id].size()
		for i: int in multi.instance_count:
			var pose: Transform3D = groups[id][i]
			pose.origin -= SPEC.STREET_ORIGIN
			multi.set_instance_transform(i, pose)
		var batch := MultiMeshInstance3D.new()
		batch.name = id
		batch.multimesh = multi
		batch.material_override = material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(batch)
	# Exact street/sidewalk/alley geometry from the assembled graph, without caps/physics.
	var structure := district.get_node("Structure")
	for source: MeshInstance3D in structure.find_children("*", "MeshInstance3D", true, false):
		var mesh := MeshInstance3D.new()
		mesh.name = source.name
		mesh.mesh = source.mesh
		mesh.position = -SPEC.STREET_ORIGIN
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = (
			Color("313a3f") if source.name.contains("asphalt") else Color("67716f")
		)
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)
	root.set_meta("building_instances", 23)
	root.set_meta("source_origin", SPEC.STREET_ORIGIN)
	await get_tree().process_frame
	await get_tree().process_frame
	_owner(root, root)
	var scene := PackedScene.new()
	assert(scene.pack(root) == OK)
	assert(ResourceSaver.save(scene, "res://assets/street_hotel/street_lod.scn") == OK)
	district.free()
	root.free()


func _exterior() -> void:
	_surface = SurfaceTool.new()
	_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box(Vector3(0, 21, 36), Vector3(19, 42, 72), 1)
	for floor_index: int in SPEC.FLOORS:
		for bay: int in range(10):
			for side: int in [-1, 1]:
				_quad(
					Vector3(side * 9.51, floor_index * SPEC.STOREY + 1.8, 15 + bay * 6),
					Vector2(3.8, 1.8),
					Basis(Vector3.UP, side * PI / 2),
					0
				)
		_box(Vector3(0, floor_index * SPEC.STOREY + 3.5, 36), Vector3(19.15, .18, 72.15), 2)
	assert(
		(
			ResourceSaver.save(
				_surface.commit(), "res://assets/street_hotel/models/hotel_exterior.res"
			)
			== OK
		)
	)
	print("HOTEL_ASSETS_READY")


func _quad(center: Vector3, size: Vector2, basis: Basis, region: int) -> void:
	var points: Array[Vector3] = [
		Vector3(-size.x / 2, -size.y / 2, 0),
		Vector3(size.x / 2, -size.y / 2, 0),
		Vector3(size.x / 2, size.y / 2, 0),
		Vector3(-size.x / 2, size.y / 2, 0)
	]
	var uvs: Array[Vector2] = [
		Vector2(.04, .04), Vector2(.46, .04), Vector2(.46, .46), Vector2(.04, .46)
	]
	var offset := Vector2(.5 if region % 2 else 0, .5 if region >= 2 else 0)
	for i: int in [0, 3, 2, 0, 2, 1]:
		_surface.set_normal(basis.z)
		_surface.set_uv(uvs[i] + offset)
		_surface.add_vertex(center + basis * points[i])


func _box(center: Vector3, size: Vector3, region: int) -> void:
	for side: int in [-1, 1]:
		_quad(
			center + Vector3(0, 0, side * size.z / 2),
			Vector2(size.x, size.y),
			Basis(Vector3.UP, 0 if side > 0 else PI),
			region
		)
		_quad(
			center + Vector3(side * size.x / 2, 0, 0),
			Vector2(size.z, size.y),
			Basis(Vector3.UP, side * PI / 2),
			region
		)
		_quad(
			center + Vector3(0, side * size.y / 2, 0),
			Vector2(size.x, size.z),
			Basis(Vector3.RIGHT, -side * PI / 2),
			region
		)


func _owner(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		# Metadata using dictionaries of socket references is useful only before baking.
		child.remove_meta("shell_faces")
		_owner(child, root)
