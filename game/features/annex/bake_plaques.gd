extends SceneTree
## Offline authoring: bake the shared atlas lettering onto the six wooden plaques.
## Run with --headless --path game -s res://features/annex/bake_plaques.gd.

const SCENE := "res://features/annex/easter_eggs.tscn"


func _initialize() -> void:
	var source := load(SCENE) as PackedScene
	var plaques := source.instantiate() as Node3D
	var kit := SignBoard.new()
	var material := kit._material("letters")
	for plaque: Node3D in plaques.get_children():
		var previous := plaque.get_node("Joke") as Node3D
		var message := (
			(previous as Label3D).text
			if previous is Label3D
			else str(previous.get_meta("plaque_text"))
		)
		var letters := MeshInstance3D.new()
		letters.name = "Joke"
		letters.transform = previous.transform
		letters.mesh = SignBoard.letters_mesh(message, .065, 0.0)
		letters.material_override = material
		letters.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		letters.visibility_range_end = 18.0
		letters.set_meta("plaque_text", message)
		plaque.remove_child(previous)
		previous.free()
		plaque.add_child(letters)
		letters.owner = plaques
	var packed := PackedScene.new()
	assert(packed.pack(plaques) == OK)
	assert(ResourceSaver.save(packed, SCENE) == OK)
	plaques.free()
	kit.free()
	print("ANNEX_PLAQUES: six static atlas meshes baked")
	quit()
