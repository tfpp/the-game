class_name PrawnSkinAppearance
extends RefCounted
## Changes only per-instance view materials; originals restore on unequip.
## Shared catalog meshes, stats, muzzle/grip markers and arms are untouched.

const PAINT := preload("res://features/pawn_shop/skin_paint.gdshader")
static var _materials: Dictionary[String, ShaderMaterial] = {}


static func apply(view: Node3D, skin: String) -> void:
	if not PrawnSkinCatalog.SKINS.has(skin):
		skin = ""
	if view.get_meta("prawn_skin", "") == skin:
		return
	view.set_meta("prawn_skin", skin)
	for mesh: MeshInstance3D in view.find_children("*", "MeshInstance3D", true, false):
		var name_lower := String(mesh.name).to_lower()
		if "bore" in name_lower or "sight" in name_lower or "scope" in name_lower:
			continue
		if not mesh.has_meta("prawn_original"):
			mesh.set_meta("prawn_original", {"material": mesh.material_override})
		var original: Material = mesh.get_meta("prawn_original")["material"]
		var standard := original as StandardMaterial3D
		var texture := standard.albedo_texture if standard != null else null
		var mask := mesh.get_meta("skin_mask") as Texture2D if mesh.has_meta("skin_mask") else null
		mesh.material_override = material(skin, texture, mask) if not skin.is_empty() else original


static func material(
	skin: String, texture: Texture2D = null, mask: Texture2D = null
) -> ShaderMaterial:
	var key := (
		skin
		+ (
			":" + str(texture.get_instance_id()) + ":" + str(mask.get_instance_id())
			if texture != null and mask != null
			else ""
		)
	)
	if not _materials.has(key):
		var data: Array = PrawnSkinCatalog.SKINS[skin]
		var paint := ShaderMaterial.new()
		paint.shader = PAINT
		paint.set_shader_parameter("paint", data[3])
		paint.set_shader_parameter("shell", data[4])
		paint.set_shader_parameter("pattern", float(data[2]))
		paint.set_shader_parameter("use_atlas", texture != null and mask != null)
		if texture != null and mask != null:
			paint.set_shader_parameter("base_texture", texture)
			paint.set_shader_parameter("skin_mask", mask)
		_materials[key] = paint
	return _materials[key]


static func create_view(skin: String) -> Node3D:
	var data: Array = PrawnSkinCatalog.SKINS[skin]
	var view := ItemCatalog.create_view(data[1])
	apply(view, skin)
	return view
