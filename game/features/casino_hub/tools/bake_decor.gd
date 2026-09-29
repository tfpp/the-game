extends SceneTree
## Offline bake: merge static, non-colliding casino CSG by material and 16 m sector.
## Keep collision-bearing architecture and all gameplay nodes in their original form.

const SOURCE := "res://features/casino_hub/tools/interior_source.tscn"
const OUTPUT := "res://features/casino_hub/interior.tscn"
const BATCHES := "res://assets/casino_hub/models/decor_batches.scn"

var _groups: Dictionary[String, SurfaceTool] = {}
var _materials: Dictionary[String, Material] = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var interior := (load(SOURCE) as PackedScene).instantiate() as Node3D
	root.add_child(interior)
	await physics_frame
	await physics_frame
	var removed := 0
	for child: Node in interior.get_children():
		var csg := child as CSGShape3D
		if csg == null or csg.use_collision or not csg.visible or csg.get_child_count() > 0:
			continue
		var data := csg.get_meshes()
		if data.size() != 2:
			continue
		var mesh := data[1] as ArrayMesh
		var transform: Transform3D = csg.transform * (data[0] as Transform3D)
		var sector := Vector2i(floori(csg.position.x / 16.0), floori(csg.position.z / 16.0))
		for surface: int in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			var key := "%s_%d_%d" % [material.resource_path, sector.x, sector.y]
			if not _groups.has(key):
				var builder := SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				_groups[key] = builder
				_materials[key] = material
			_groups[key].append_from(mesh, surface, transform)
		interior.remove_child(csg)
		csg.free()
		removed += 1
	var batches := Node3D.new()
	batches.name = "DecorBatches"
	var count := 0
	for key: String in _groups:
		var instance := MeshInstance3D.new()
		instance.name = "Sector%d" % count
		instance.mesh = _groups[key].commit()
		instance.material_override = _materials[key]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batches.add_child(instance)
		instance.owner = batches
		count += 1
	var packed := PackedScene.new()
	assert(packed.pack(batches) == OK)
	assert(ResourceSaver.save(packed, BATCHES, ResourceSaver.FLAG_COMPRESS) == OK)
	batches.free()
	var saved_batches := (load(BATCHES) as PackedScene).instantiate()
	interior.add_child(saved_batches)
	saved_batches.owner = interior
	var result := PackedScene.new()
	assert(result.pack(interior) == OK)
	assert(ResourceSaver.save(result, OUTPUT) == OK)
	print("DECOR_BAKE: ", removed, " CSG draws -> ", count, " sector/material batches")
	interior.free()
	quit()
