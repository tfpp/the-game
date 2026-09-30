extends SceneTree
## Original measurement textures; no downloaded artwork or external asset tools.

const ASSET_DIR := "res://assets/procedural_rooms/dev_textures"
const MATERIAL_DIR := "res://features/procedural_rooms/materials"
const PREVIEW := "res://../docs/design/previews/dev-textures.png"
const SIZE := 128
const TILE_METRES := 64.0 * 0.0254
const FONT := {
	"A": "010101111101101",
	"B": "110101110101110",
	"C": "011100100100011",
	"D": "110101101101110",
	"E": "111100110100111",
	"F": "111100110100100",
	"G": "011100101101011",
	"H": "101101111101101",
	"I": "111010010010111",
	"J": "001001001101010",
	"K": "101101110101101",
	"L": "100100100100111",
	"M": "101111111101101",
	"N": "101111111111101",
	"O": "010101101101010",
	"P": "110101110100100",
	"Q": "010101101111011",
	"R": "110101110101101",
	"S": "011100010001110",
	"T": "111010010010010",
	"U": "101101101101111",
	"V": "101101101101010",
	"W": "101101111111101",
	"X": "101101010101101",
	"Y": "101101010010010",
	"Z": "111001010100111",
	"0": "111101101101111",
	"1": "010110010010111",
	"2": "110001010100111",
	"3": "110001010001110",
	"4": "101101111001001",
	"5": "111100110001110",
	"6": "011100111101111",
	"7": "111001010010010",
	"8": "111101111101111",
	"9": "111101111001110",
	" ": "000000000000000",
	"/": "001001010100100",
	"-": "000000111000000"
}
const TILES := [
	["orange", "ORANGE", "b96328", "edaa63", "grid"],
	["grey", "GREY", "686e72", "acb4b8", "grid"],
	["dark", "DARK", "30383e", "737f88", "grid"],
	["floor", "FLOOR", "45535e", "8ea2b0", "grid"],
	["wall", "WALL", "a95c2c", "ecc188", "grid"],
	["ceiling", "CEILING", "8e999c", "d6dedc", "grid"],
	["checker", "CHECKER", "79878e", "3a444b", "checker"],
	["hazard", "HAZARD", "dcc15a", "252b30", "stripe"],
	["water", "WATER", "376b72", "83b5b4", "water"],
	["route", "ROUTE", "436e58", "d2e2c9", "arrow"],
	["cover", "COVER", "69547d", "c2acd8", "grid"],
	["elevator", "LIFT", "355b83", "afcde3", "lift"]
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSET_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MATERIAL_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW).get_base_dir())
	var sheet := Image.create(1120, 1080, false, Image.FORMAT_RGB8)
	sheet.fill(Color("171d23"))
	_text(sheet, "CASINO ROYALE / DEVELOPMENT TEXTURES", Vector2i(32, 24), 4, Color("f4e8d3"))
	_text(sheet, "64U TILE / 8U GRID / 128PX / ORIGINAL ART", Vector2i(32, 62), 3, Color("9baab5"))
	for index: int in TILES.size():
		var tile: Array = TILES[index]
		var texture := _tile(tile)
		var path := "%s/%s.png" % [ASSET_DIR, tile[0]]
		if texture.save_png(path) != OK:
			push_error("Cannot save " + path)
			quit(1)
			return
		_save_material(tile[0])
		var enlarged := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y: int in SIZE:
			for x: int in SIZE:
				enlarged.fill_rect(Rect2i(x * 2, y * 2, 2, 2), texture.get_pixel(x, y))
		var origin := Vector2i(32 + (index % 4) * 272, 108 + (index / 4) * 316)
		sheet.blit_rect(enlarged, Rect2i(0, 0, 256, 256), origin)
		_text(sheet, tile[1], origin + Vector2i(0, 270), 3, Color("e9dcc6"))
	if sheet.save_png(PREVIEW) != OK:
		push_error("Cannot save preview")
		quit(1)
		return
	print("DEV_TEXTURES: 12 PNGs, 12 materials, preview; tile = ", TILE_METRES, " metres")
	quit()


func _tile(tile: Array) -> Image:
	var result := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var base := Color(tile[2])
	var ink := Color(tile[3])
	for y: int in SIZE:
		for x: int in SIZE:
			var color := base
			match tile[4]:
				"checker":
					if ((x >> 5) + (y >> 5)) % 2 == 0:
						color = ink
				"stripe":
					if (x + y) % 32 < 16:
						color = ink
				"water":
					if (y + (8 if x % 64 < 32 else 0)) % 32 < 2:
						color = ink
				_:
					if x % 16 == 0 or y % 16 == 0:
						color = base.lerp(ink, 0.45)
					if x % 64 < 2 or y % 64 < 2:
						color = ink
			result.set_pixel(x, y, color)
	if tile[4] == "grid":
		result.fill_rect(Rect2i(24, 43, 80, 41), base)
		_text(result, tile[1], Vector2i((SIZE - str(tile[1]).length() * 8 + 2) / 2, 49), 2, ink)
		_text(result, "64U", Vector2i(42, 68), 2, ink)
	if tile[4] == "arrow":
		result.fill_rect(Rect2i(55, 40, 18, 62), ink)
		for y: int in range(20, 58):
			var half := y - 20
			result.fill_rect(Rect2i(64 - half, y, half * 2 + 1, 1), ink)
	if tile[4] == "lift":
		result.fill_rect(Rect2i(29, 30, 70, 70), ink)
		result.fill_rect(Rect2i(33, 34, 62, 62), base)
		result.fill_rect(Rect2i(63, 34, 2, 62), ink)
		_text(result, "LIFT", Vector2i(49, 14), 2, ink)
	return result


func _save_material(id: String) -> void:
	# Surface grids keep constant world scale; direction/door signs use authored UVs.
	var mapped := id not in ["route", "elevator"]
	var scale := 1.0 / TILE_METRES if mapped else 1.0
	var text := '[gd_resource type="StandardMaterial3D" load_steps=2 format=3]\n\n'
	text += '[ext_resource type="Texture2D" path="%s/%s.png" id="1"]\n\n' % [ASSET_DIR, id]
	text += '[resource]\nresource_name = "Dev %s"\n' % id
	text += 'albedo_texture = ExtResource("1")\nroughness = 1.0\nmetallic_specular = 0.0\n'
	text += (
		"texture_filter = %d\ntexture_repeat = true\n"
		% BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	)
	text += "uv1_scale = Vector3(%f, %f, %f)\n" % [scale, scale, scale]
	if mapped:
		text += "uv1_triplanar = true\nuv1_world_triplanar = true\nuv1_triplanar_sharpness = 16.0\n"
	var file := FileAccess.open("%s/%s.tres" % [MATERIAL_DIR, id], FileAccess.WRITE)
	if file == null:
		push_error("Cannot save material " + id)
		quit(1)
		return
	file.store_string(text)


func _text(image: Image, label: String, origin: Vector2i, scale: int, ink: Color) -> void:
	for index: int in label.length():
		var glyph: String = FONT.get(label[index], FONT[" "])
		for pixel: int in 15:
			if glyph[pixel] == "1":
				var offset := Vector2i(index * 4 + pixel % 3, pixel / 3) * scale
				image.fill_rect(Rect2i(origin + offset, Vector2i.ONE * scale), ink)
