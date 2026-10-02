extends SceneTree

const TEXTURES := {
	"asphalt": preload("res://assets/street_props/surfaces/asphalt_wet.png"),
	"sidewalk": preload("res://assets/street_props/surfaces/sidewalk_slabs.png"),
	"alley": preload("res://assets/street_props/surfaces/concrete_wall.png")
}


func _initialize() -> void:
	for id: String in TEXTURES:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = TEXTURES[id]
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE * .5
		mat.roughness = 1.0
		mat.metallic_specular = 0.0
		assert(
			(
				ResourceSaver.save(mat, "res://features/street_district/materials/" + id + ".tres")
				== OK
			)
		)
	quit()
