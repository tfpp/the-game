extends SceneTree
## Bake the lobby portal using the same profiled joinery as the hotel.

const Geometry := preload("res://features/world_builder/geometry.gd")
const Profiles := preload("res://features/world_builder/profiles.gd")
const Joinery := preload("res://features/world_builder/joinery.gd")
const Materials := preload("res://features/world_builder/materials.gd")


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "HotelEntrance"
	var geometry := Geometry.new()
	geometry.materials = Materials.create("hotel")
	Joinery.door(geometry, Vector3(-0.75, 0, 0), Basis.IDENTITY, 1.5, 2.7)
	for side: float in [-1, 1]:
		var basis := Basis(Vector3.UP, PI if side < 0 else 0)
		Profiles.frame(
			geometry,
			"plaster",
			Vector3.ZERO,
			basis,
			Rect2(-0.75, 0, 1.5, 2.7),
			[
				Vector2(0, 0),
				Vector2(0, 0.12),
				Vector2(0.05, 0.16),
				Vector2(0.1, 0.12),
				Vector2(0.17, 0.19),
				Vector2(0.23, 0.19),
				Vector2(0.26, 0.1),
				Vector2(0.26, 0)
			],
			false
		)
		Profiles.sweep(
			geometry,
			"wood",
			basis * Vector3(-1.08, 0, 0),
			basis,
			2.16,
			[
				Vector2(2.96, 0),
				Vector2(2.96, 0.17),
				Vector2(3.0, 0.21),
				Vector2(3.25, 0.21),
				Vector2(3.3, 0.25),
				Vector2(3.34, 0.25),
				Vector2(3.34, 0)
			]
		)
	geometry.finish(root)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(
			packed, "res://features/hotel_annex/entrance.scn", ResourceSaver.FLAG_COMPRESS
		)
	root.free()
	quit(error)
