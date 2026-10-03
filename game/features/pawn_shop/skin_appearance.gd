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
		mesh.material_override = (
			material(skin) if not skin.is_empty() else mesh.get_meta("prawn_original")["material"]
			as Material
		)


static func material(skin: String) -> ShaderMaterial:
	if not _materials.has(skin):
		var data: Array = PrawnSkinCatalog.SKINS[skin]
		var paint := ShaderMaterial.new()
		paint.shader = PAINT
		paint.set_shader_parameter("paint", data[3])
		paint.set_shader_parameter("shell", data[4])
		paint.set_shader_parameter("pattern", float(data[2]))
		_materials[skin] = paint
	return _materials[skin]


static func create_view(skin: String) -> Node3D:
	var data: Array = PrawnSkinCatalog.SKINS[skin]
	var view := ItemCatalog.create_view(data[1])
	apply(view, skin)
	return view
