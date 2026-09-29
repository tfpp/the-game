extends RefCounted

const PLASTER := preload("res://features/world_builder/textures/plaster.png")
const WALLPAPER := preload("res://features/world_builder/textures/wallpaper.png")
const WOOD := preload("res://features/world_builder/textures/walnut.png")
const CARPET := preload("res://features/world_builder/textures/carpet.png")
const PROTO_FLOOR := preload("res://world/materials/proto_dark.tres")
const PROTO_WALL := preload("res://world/materials/proto_wall.tres")


static func create(theme: String) -> Dictionary[String, Material]:
	var result: Dictionary[String, Material] = {
		"floor": _material("Parquet walnut", WOOD, Color("82603c"), 0.6),
		"concrete": _material("Worn concrete", PLASTER, Color("777a76"), 1.2),
		"wall": _material("Cream damask", WALLPAPER, Color("e0cda8"), 0.5),
		"ceiling": _material("Ivory plaster", PLASTER, Color("e8d9bc"), 0.4),
		"wood": _material("Panelled walnut", WOOD, Color("ad8056"), 0.6),
		"plaster": _material("Carved limestone", PLASTER, Color("eadbc0"), 0.6),
		"gold": _material("Antique brass", PLASTER, Color("95723b"), 1.0),
		"carpet": _material("Burgundy Persian weave", CARPET, Color.WHITE, 0.45),
		"glass": _material("Window glass", PLASTER, Color("9eafbe"), 0.3),
		"glow": _material("Warm opal glass", PLASTER, Color("ffda8d"), 0.5),
	}
	result.merge(preload("res://features/room_kits/catalog.gd").materials())
	var glow := result["glow"] as StandardMaterial3D
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glass := result["glass"] as StandardMaterial3D
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.16
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.roughness = 0.35
	if theme == "prototype":
		result["floor"] = PROTO_FLOOR
		result["wall"] = PROTO_WALL
		result["ceiling"] = PROTO_FLOOR
	return result


static func _material(
	label: String, texture: Texture2D, tint: Color, scale: float
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = label
	material.set_meta(&"per_pixel_lighting", true)
	material.albedo_texture = texture
	material.albedo_color = tint
	material.vertex_color_use_as_albedo = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.roughness = 0.9
	material.metallic_specular = 0.15
	material.uv1_scale = Vector3.ONE * scale
	return material
