extends SceneTree
## Bakes the Mandarin hello sign's albedo texture inside the world-texture budget.
##
## The engine's default font covers no CJK glyphs, so 你 and 好 are painted from
## GNU Unifont 17.0.04's hex sources (dual SIL OFL 1.1 / GPLv2+ with the font
## embedding exception; excerpt and provenance in docs/design/model-sources/
## lobby-sign/). The bake is fully deterministic: the same input always produces
## the same pixels, and tests compare the shipped PNG against paint().
##
## Usage (from game/): godot --headless -s res://features/lobby_sign/tools/build_texture.gd

const RUNTIME := "res://assets/lobby_sign/textures/hello_albedo.png"
const PREVIEW := "res://../docs/design/model-sources/lobby-sign/preview-8x.png"

const WIDTH := 64
const HEIGHT := 128
const GLYPH_SCALE := 3
## Inset of the 1px gold border frame.
const FRAME_INSET := 2

## Top-left pixel of each glyph's 48x48 cell.
const CELLS: Dictionary[int, Vector2i] = {
	0x4F60: Vector2i(8, 8),
	0x597D: Vector2i(8, 73),
}

## GNU Unifont 17.0.04 rows for 你 (U+4F60, "nǐ") and 好 (U+597D, "hǎo"), verbatim.
const UNIFONT := {
	0x4F60: "08800880088011FE110232043420502091281124122412221422102010A01040",
	0x597D: "100010FC10041008FC102420242025FE24204820282010202820442084A00040",
}

const BURGUNDY := Color(0.30, 0.077, 0.115)
const GOLD := Color(0.92, 0.69, 0.36)


func _initialize() -> void:
	var image := paint()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RUNTIME.get_base_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW.get_base_dir()))
	assert(image.save_png(RUNTIME) == OK)
	var preview := paint()
	preview.resize(WIDTH * 8, HEIGHT * 8, Image.INTERPOLATE_NEAREST)
	assert(preview.save_png(PREVIEW) == OK)
	_print_preview(image)
	print("lobby_sign: baked %s (%dx%d) and %s" % [RUNTIME, WIDTH, HEIGHT, PREVIEW])
	quit()


## The sign face: one 64x128 island, 53 pixels per metre on a 1.2x2.4 m quad.
static func paint() -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
	for y: int in HEIGHT:
		for x: int in WIDTH:
			image.set_pixel(x, y, _pixel(x, y))
	return image


## One 16x16 glyph as 16 row bitmasks; bit 15 is the leftmost column.
static func glyph_rows(codepoint: int) -> PackedInt32Array:
	var rows: PackedInt32Array = []
	var data: String = UNIFONT[codepoint]
	for row: int in 16:
		rows.append(data.substr(row * 4, 4).hex_to_int())
	return rows


static func _pixel(x: int, y: int) -> Color:
	for codepoint: int in CELLS:
		var cell: Vector2i = CELLS[codepoint]
		var local := Vector2i(x - cell.x, y - cell.y)
		if (
			local.x >= 0
			and local.y >= 0
			and local.x < 16 * GLYPH_SCALE
			and local.y < 16 * GLYPH_SCALE
		):
			var rows := glyph_rows(codepoint)
			var column := 15 - local.x / GLYPH_SCALE
			if rows[local.y / GLYPH_SCALE] >> column & 1:
				return GOLD * (0.90 + 0.20 * _noise(x, y))
	if _is_frame(x, y):
		return GOLD * (0.80 + 0.16 * _noise(x, y))
	var warm := 1.0 + 0.06 * (1.0 - float(y) / float(HEIGHT))
	return BURGUNDY * (0.88 + 0.24 * _noise(x, y)) * warm


static func _is_frame(x: int, y: int) -> bool:
	var low := FRAME_INSET
	var high_x := WIDTH - FRAME_INSET - 1
	var high_y := HEIGHT - FRAME_INSET - 1
	if not (low <= x and x <= high_x and low <= y and y <= high_y):
		return false
	return x == low or x == high_x or y == low or y == high_y


## Deterministic paint noise; no random seed, so bakes are reproducible.
static func _noise(x: int, y: int) -> float:
	var hash := (x * 73856093) ^ (y * 19349663) ^ 0x5BD1E995
	return float(hash % 1000) / 1000.0


static func _print_preview(image: Image) -> void:
	var rows: Array[String] = []
	for y: int in HEIGHT:
		var row := ""
		for x: int in WIDTH:
			row += "#" if image.get_pixel(x, y).r > 0.55 else "."
		rows.append(row)
	print("\n".join(rows))
