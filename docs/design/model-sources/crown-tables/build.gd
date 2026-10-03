extends SceneTree
## Build new playable assemblies from reviewed mesh-first casino kit sources.
## Preserve the existing UVs and painted textures; never repaint approved artwork.
const IDS: Array[String] = [
	"blackjack_table", "poker_table", "baccarat_table", "craps_table", "video_poker_machine"
]
const EXTRAS: Array[String] = ["card_shoe", "dealer_button", "card_shoe", "craps_dice", "card_deck"]
const OFFSETS: Array[Vector3] = [
	Vector3(.8, .91, .35),
	Vector3(0, .92, .1),
	Vector3(.9, .91, .3),
	Vector3(0, .97, 0),
	Vector3(0, .7, .32)
]


func _initialize() -> void:
	var inventory: Array[Dictionary] = []
	for i: int in range(3, 4):
		var mesh := ArrayMesh.new()
		_append(
			mesh,
			load("res://assets/casino_props/models/" + IDS[i] + ".res") as ArrayMesh,
			Transform3D.IDENTITY,
			load("res://features/casino_props/materials/" + IDS[i] + ".tres") as Material
		)
		_append(
			mesh,
			load("res://assets/casino_props/models/" + EXTRAS[i] + ".res") as ArrayMesh,
			Transform3D(Basis.IDENTITY, OFFSETS[i]),
			load("res://features/casino_props/materials/" + EXTRAS[i] + ".tres") as Material
		)
		assert(ResourceSaver.save(mesh, "res://assets/table_games/models/" + IDS[i] + ".res") == OK)
		print(IDS[i], " ", mesh.get_aabb(), " surfaces=", mesh.get_surface_count())
		var triangles := 0
		var textures: Array[Dictionary] = []
		for surface: int in mesh.get_surface_count():
			var indices: PackedInt32Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
			var material := mesh.surface_get_material(surface) as StandardMaterial3D
			textures.append(
				{
					"path": material.albedo_texture.resource_path,
					"width": material.albedo_texture.get_width(),
					"height": material.albedo_texture.get_height()
				}
			)
		inventory.append(
			{
				"id": IDS[i],
				"triangles": triangles,
				"surfaces": mesh.get_surface_count(),
				"bounds": str(mesh.get_aabb()),
				"textures": textures
			}
		)
	var file := FileAccess.open(
		"res://../docs/design/model-sources/crown-tables/inventory.json", FileAccess.WRITE
	)
	file.store_string(JSON.stringify(inventory, "\t") + "\n")
	file.close()
	quit()


func _append(target: ArrayMesh, source: ArrayMesh, pose: Transform3D, material: Material) -> void:
	for surface: int in source.get_surface_count():
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.append_from(source, surface, pose)
		builder.set_material(material)
		builder.index()
		builder.commit(target)
