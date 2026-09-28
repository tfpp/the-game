class_name ClothingCatalog
extends RefCounted
## Clothing IDs include their fixed color so storing, swapping and dropping preserve color.

const COLORS: Array[Color] = [
	Color("f0eee5"),
	Color("283343"),
	Color("318d8c"),
	Color("5381bb"),
	Color("bf6541"),
	Color("8872b3"),
	Color("698345"),
	Color("d4ac4e"),
	Color("c77392"),
	Color("794b39"),
	Color("a1abb5"),
	Color("b7474d"),
]
const COLOR_NAMES: Array[String] = [
	"White",
	"Midnight",
	"Teal",
	"Blue",
	"Rust",
	"Lilac",
	"Moss",
	"Gold",
	"Rose",
	"Cocoa",
	"Silver",
	"Red",
]


static func slot(id: String) -> String:
	var parts := id.split(":")
	if parts.size() != 2 or parts[0] not in ["shirt", "pants"]:
		return ""
	if not parts[1].is_valid_int():
		return ""
	var index := int(parts[1])
	if index < 0 or index >= COLORS.size() or parts[1] != str(index):
		return ""
	return parts[0]


static func color_index(id: String) -> int:
	return int(id.get_slice(":", 1)) if not slot(id).is_empty() else 0


static func color(id: String) -> Color:
	return COLORS[color_index(id)]


static func title(id: String) -> String:
	var kind := slot(id)
	if kind.is_empty():
		return ""
	return "%s %s" % [COLOR_NAMES[color_index(id)], "shirt" if kind == "shirt" else "pants"]
