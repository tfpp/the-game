extends SceneTree
## Fast geometry-only export of the sewer kit and storage fixtures.

const Sewer := preload("res://features/sewer_kit/kit.gd")
const Geometry := preload("res://features/world_builder/geometry.gd")
const Materials := preload("res://features/world_builder/materials.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var root := Node3D.new()
	root.name = "ServiceArea"
	var sewer := Sewer.build_network(
		Sewer.district_cells(), [Vector2i(-14, 0), Vector2i.ZERO, Vector2i(14, 0)]
	)
	sewer.position = Vector3(-16, -6, -7)
	Geometry.attach(root, sewer, root)
	# Preserve ownership of the module's geometry in the outer saved scene.
	for child: Node in sewer.find_children("*", "", true, false):
		child.owner = root
	for offset: float in [-84, 0, 84]:
		var store := Node3D.new()
		store.name = "StorageFixtures%s" % int(offset)
		store.position.x = offset
		Geometry.attach(root, store, root)
		_storage(store)
		for child: Node in store.find_children("*", "", true, false):
			child.owner = root
	var scene := PackedScene.new()
	var result := scene.pack(root)
	if result == OK:
		result = ResourceSaver.save(
			scene, "res://features/hotel_annex/service.scn", ResourceSaver.FLAG_COMPRESS
		)
	root.free()
	print("SERVICE_BUILD: ", error_string(result))
	quit(0 if result == OK else 1)


func _storage(root: Node3D) -> void:
	var g := Geometry.new()
	g.materials = Materials.create("hotel")
	# Storage partition: the sewer door is the only way into the ladder alcove.
	g.box("concrete", Vector3(-19.45, 1.75, -4), Vector3(1.1, 3.5, 0.2), true)
	g.box("concrete", Vector3(-12.55, 1.75, -4), Vector3(9.1, 3.5, 0.2), true)
	g.box("concrete", Vector3(-18, 3.05, -4), Vector3(1.8, 0.9, 0.2), true)
	# Shelving and stores sit clear of the door and shaft.
	for z: float in [-1.4, -8.6]:
		for y: float in [0.25, 1.1, 1.95]:
			g.box("concrete_trim", Vector3(-10, y, z), Vector3(2.5, 0.08, 0.8), true)
		for x: float in [-11.2, -8.8]:
			g.box("concrete_trim", Vector3(x, 1.2, z), Vector3(0.07, 2.4, 0.8), true)
		for x: float in [-10.7, -9.8]:
			g.box("wood", Vector3(x, 0.6, z), Vector3(0.65, 0.65, 0.6), true)
	g.finish(root)
