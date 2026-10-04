extends SceneTree
## Import the supplied rig and replace its embedded fresh skin with compact rotten paint.

const SOURCE := "../docs/design/model-sources/creepy-doll/"
const OUTPUT := "res://assets/pawn_shop/models/creepy_doll/"


func _initialize() -> void:
	var source := ProjectSettings.globalize_path("res://").path_join(SOURCE)
	var image := Image.load_from_file(source.path_join("rotten-source.png"))
	image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	ResourceSaver.save(texture, OUTPUT + "rotten.res")
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(OUTPUT + "rotten.res")
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(source.path_join("source.glb"), state) != OK:
		quit(1)
		return
	var model := document.generate_scene(state)
	model.name = "RottenDoll"
	_replace(model, material)
	var packed := PackedScene.new()
	packed.pack(model)
	var result := ResourceSaver.save(packed, OUTPUT + "model.scn")
	model.free()
	quit(result)


func _replace(node: Node, material: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		for surface: int in mesh.mesh.get_surface_count():
			mesh.mesh.surface_set_material(surface, material)
			mesh.set_surface_override_material(surface, null)
		print("Doll mesh bounds: ", mesh.mesh.get_aabb())
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		for animation: StringName in player.get_animation_list():
			print("Doll animation: ", animation)
			if String(animation).ends_with("Walk"):
				player.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
	for child: Node in node.get_children():
		_replace(child, material)
