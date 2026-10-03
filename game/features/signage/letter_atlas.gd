class_name SignLetterAtlas
extends RefCounted
## Shared 64×64 letter-tile atlas for modeled signs. Glyphs are 5×7 pixel tiles in
## 8×8 cells, painted once at runtime from the patterns below and cached.

const SIZE := 64
const CELL := 8
const COLUMNS := SIZE / CELL
const GLYPH_W := 5
const GLYPH_H := 7
const FALLBACK := "?"
const GLYPHS := {
	"A": ".###.#...##...#######...##...##...#",
	"B": "####.#...##...#####.#...##...#####.",
	"C": ".###.#...##....#....#....#...#.###.",
	"D": "####.#...##...##...##...##...#####.",
	"E": "######....#....####.#....#....#####",
	"F": "######....#....####.#....#....#....",
	"G": ".###.#...##....#.####...##...#.####",
	"H": "#...##...##...#######...##...##...#",
	"I": ".###...#....#....#....#....#...###.",
	"J": "..###...#....#....#....#.#..#..##..",
	"K": "#...##..#.#.#..##...#.#..#..#.#...#",
	"L": "#....#....#....#....#....#....#####",
	"M": "#...###.###.#.##.#.##...##...##...#",
	"N": "#...##...###..##.#.##..###...##...#",
	"O": ".###.#...##...##...##...##...#.###.",
	"P": "####.#...##...#####.#....#....#....",
	"Q": ".###.#...##...##...##.#.##..#..##.#",
	"R": "####.#...##...#####.#.#..#..#.#...#",
	"S": ".#####....#.....###.....#....#####.",
	"T": "#####..#....#....#....#....#....#..",
	"U": "#...##...##...##...##...##...#.###.",
	"V": "#...##...##...##...##...#.#.#...#..",
	"W": "#...##...##...##.#.##.#.##.#.#.#.#.",
	"X": "#...##...#.#.#...#...#.#.#...##...#",
	"Y": "#...##...#.#.#...#....#....#....#..",
	"Z": "#####....#...#...#...#...#....#####",
	"Ż": "..#..#####....#...#...#...#..#####",
	"Ł": "#....#..#.#.#..##...#....#....#####",
	"0": ".###.#...##..###.#.###..##...#.###.",
	"1": "..#...##....#....#....#....#...###.",
	"2": ".###.#...#....#...#...#...#...#####",
	"3": "####.....#....#.###.....#....#####.",
	"4": "...#...##..#.#.#..#.#####...#....#.",
	"5": "######....####.....#....##...#.###.",
	"6": ".###.#....#....####.#...##...#.###.",
	"7": "#####....#...#...#...#....#....#...",
	"8": ".###.#...##...#.###.#...##...#.###.",
	"9": ".###.#...##...#.####....#....#.###.",
	"-": "...............#####...............",
	".": "..............................#....",
	",": "...........................#...#...",
	"!": "..#....#....#....#....#.........#..",
	"'": "..#....#...........................",
	"$": "..#...#####.#...###...#.#####...#..",
	"&": ".##..#..#.#.#...#...#.#.##..#..##.#",
	"?": ".###.#...#....#...#...#.........#..",
	"/": "....#....#...#...#...#...#....#....",
	":": "......#....#.........#....#........",
	"#": ".#.#..#.#.#####.#.#.#####.#.#..#.#.",
	" ": "...................................",
}

static var _texture: ImageTexture
static var _order: Array = []


## Tile index for a character; unknown characters use the fallback glyph.
static func index_of(character: String) -> int:
	if _order.is_empty():
		_order = GLYPHS.keys()
	var key := character.to_upper()
	if not GLYPHS.has(key):
		key = FALLBACK
	return _order.find(key)


## UV rectangle of a character's 5×7 glyph inside the atlas.
static func uv_rect(character: String) -> Rect2:
	var index := index_of(character)
	var origin := Vector2((index % COLUMNS) * CELL + 1, (index / COLUMNS) * CELL)
	return Rect2(origin / SIZE, Vector2(GLYPH_W, GLYPH_H) / SIZE)


static func image() -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_LA8)
	img.fill(Color(1, 1, 1, 0))
	for character: String in GLYPHS:
		var pattern: String = GLYPHS[character]
		var index := index_of(character)
		var ox := (index % COLUMNS) * CELL + 1
		var oy := (index / COLUMNS) * CELL
		for i in mini(pattern.length(), GLYPH_W * GLYPH_H):
			if pattern[i] == "#":
				img.set_pixel(ox + i % GLYPH_W, oy + i / GLYPH_W, Color.WHITE)
	return img


static func texture() -> ImageTexture:
	if _texture == null:
		_texture = ImageTexture.create_from_image(image())
	return _texture
