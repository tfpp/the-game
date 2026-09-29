extends RefCounted
## Explicit resources keep kits selectable, reusable and included in exports.

const Definition := preload("res://features/room_kits/definition.gd")
const KITS := {
	"classic": preload("res://features/room_kits/classic.tres"),
	"modern": preload("res://features/room_kits/modern.tres"),
	"deco": preload("res://features/room_kits/deco.tres"),
	"concrete": preload("res://features/room_kits/concrete.tres"),
}


static func apply(layout: Dictionary, spec: Dictionary) -> void:
	layout["cell_kits"] = {}
	layout["room_kits"] = {}
	var default_kit: String = spec.get("style", {}).get("kit", "classic")
	for cell: Vector2i in layout["cells"]:
		layout["cell_kits"][cell] = default_kit
	for room: Dictionary in spec["rooms"]:
		var kit: String = room.get("kit", default_kit)
		layout["room_kits"][room["id"]] = kit
		var rect: Rect2i = layout["rooms"][room["id"]]
		for z: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				layout["cell_kits"][Vector2i(x, z)] = kit


static func materials() -> Dictionary[String, Material]:
	var result: Dictionary[String, Material] = {}
	for id: String in KITS:
		var kit: Definition = KITS[id]
		for surface: String in ["wall", "floor", "ceiling", "trim", "accent", "light"]:
			var material := StandardMaterial3D.new()
			material.resource_name = id + "_" + surface
			material.albedo_color = kit.get(surface + "_color")
			material.albedo_texture = preload("res://features/world_builder/textures/plaster.png")
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			material.uv1_scale = Vector3.ONE * 1.2
			material.roughness = 0.95 if id == "concrete" else 0.7
			material.set_meta(&"per_pixel_lighting", true)
			if surface == "light":
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			result[id + "_" + surface] = material
	return result
