@tool
extends SignBoard
## White modeled lettering on Żabka green, using the shared sign geometry/atlas.

static var _green: StandardMaterial3D


func _material(kind: String) -> StandardMaterial3D:
	if kind in ["backing", "frame", "metal"]:
		if _green == null:
			_green = StandardMaterial3D.new()
			_green.albedo_color = Color("#087b3e")
			_green.roughness = 0.9
		return _green
	return super._material(kind)
