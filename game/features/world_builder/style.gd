extends RefCounted
## Blueprint defaults and validation for architectural details. All dimensions are metres.

const Kits := preload("res://features/room_kits/catalog.gd")

const DEFAULTS := {
	"theme": "hotel",
	"kit": "classic",
	"panel_spacing": 2.4,
	"wainscot_height": 1.1,
	"pillar_width": 0.34,
	"pillar_depth": 0.20,
	"trim_depth": 0.12,
	"window_spacing": 3.0,
	"window_width": 1.3,
	"window_height": 2.2,
	"window_sill": 1.25,
	"windows": false,
	"lights": true,
}
const SIDES := {"west": 0, "east": 1, "north": 2, "south": 3}


static func settings(spec: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	result.merge(spec.get("style", {}), true)
	return result


static func validate(spec: Dictionary, errors: Array[String]) -> void:
	var style: Variant = spec.get("style", {})
	if not style is Dictionary:
		errors.append("style must be an object.")
		return
	for key: String in style:
		if not DEFAULTS.has(key):
			errors.append("Unknown style setting: %s" % key)
	var ranges := {
		"panel_spacing": Vector2(1.5, 6),
		"wainscot_height": Vector2(0.5, 1.5),
		"pillar_width": Vector2(0.2, 0.6),
		"pillar_depth": Vector2(0.1, 0.3),
		"trim_depth": Vector2(0.04, 0.2),
		"window_spacing": Vector2(2, 8),
		"window_width": Vector2(0.6, 3),
		"window_height": Vector2(0.6, 5),
		"window_sill": Vector2(0.5, 2),
	}
	for key: String in ranges:
		if style.has(key) and not number_in(style[key], ranges[key].x, ranges[key].y):
			errors.append(
				"style.%s must be between %s and %s metres." % [key, ranges[key].x, ranges[key].y]
			)
	if style.get("theme", "hotel") not in ["hotel", "prototype"]:
		errors.append("style.theme must be hotel or prototype.")
	if not Kits.KITS.has(style.get("kit", "classic")):
		errors.append("Unknown room kit.")
	for key: String in ["windows", "lights"]:
		if style.has(key) and not style[key] is bool:
			errors.append("style.%s must be a boolean." % key)
	if spec.has("hall_height") and not number_in(spec["hall_height"], 2.5, 8):
		errors.append("hall_height must be between 2.5 and 8 metres.")


static func validate_room(room: Dictionary, errors: Array[String]) -> void:
	if room.has("skylight") and not room["skylight"] is bool:
		errors.append("Room skylight must be true or false.")
	if room.has("kit") and not Kits.KITS.has(room["kit"]):
		errors.append("Unknown room kit.")
	if room.has("elevation") and not number_in(room["elevation"], -64, 64):
		errors.append("Room elevation must be between -64 and 64 metres.")
	if room.has("height") and not number_in(room["height"], 2.5, 8):
		errors.append("Room height must be between 2.5 and 8 metres.")
	var openings: Variant = room.get("openings", [])
	if not openings is Array or openings.size() > 32:
		errors.append("Room openings must be an array of at most 32 entries.")
	else:
		for opening: Variant in openings:
			_validate_opening(opening, errors)
	var pillars: Variant = room.get("pillars", [])
	if not pillars is Array or pillars.size() > 16:
		errors.append("Room pillars must be an array of at most 16 [x,z] metre offsets.")
	else:
		for point: Variant in pillars:
			if (
				not point is Array
				or point.size() != 2
				or not number_in(point[0], 0, 256)
				or not number_in(point[1], 0, 256)
			):
				errors.append("Each pillar position must contain two nonnegative metre offsets.")


static func _validate_opening(opening: Variant, errors: Array[String]) -> void:
	if not opening is Dictionary:
		errors.append("Each opening must be an object.")
		return
	for key: String in opening:
		if key not in ["id", "kind", "side", "offset", "width", "height", "sill", "open"]:
			errors.append("Unknown opening field: %s" % key)
	var id: Variant = opening.get("id", "")
	if (
		not id is String
		or RegEx.create_from_string("^[A-Za-z][A-Za-z0-9_]{0,47}$").search(id) == null
	):
		errors.append("Opening id must be an identifier starting with a letter.")
	if opening.get("kind") not in ["window", "door"] or not SIDES.has(opening.get("side")):
		errors.append("Opening needs kind window/door and side north/south/east/west.")
	for key: String in ["offset", "width", "height", "sill"]:
		var default_value := {"offset": -1.0, "width": 1.4, "height": 2.2, "sill": 1.2}
		var minimum := 0.0 if key in ["offset", "sill"] else 0.6
		if not number_in(
			opening.get(key, default_value[key]), minimum, 256 if key == "offset" else 6
		):
			errors.append("Opening %s is missing or outside its dimension limits." % key)
	if opening.has("open") and not opening["open"] is bool:
		errors.append("Opening open must be a boolean.")
	if opening.get("kind") == "window" and opening.has("open"):
		errors.append("Only doors support open; windows use fixed glazing.")
	if opening.get("kind") == "door" and opening.get("sill", 0) != 0:
		errors.append("Door sill must be zero.")


static func number_in(value: Variant, minimum: float, maximum: float) -> bool:
	return (
		(value is float or value is int)
		and is_finite(float(value))
		and value >= minimum
		and value <= maximum
	)
