extends RefCounted
## Key, mouse and controller glyphs for the Controls page, cut from Kenney's Input
## Prompts (pixel) tilemap: 16x16 tiles, 34 per row, numbered like the pack's
## `Tiles/tile_NNNN.png`. Wide keys (Shift, Tab, ...) span two tiles, Enter 2x2.
##
## `for_event` returns null for inputs without a glyph (and for left/right-sided keys,
## whose side a glyph can't show); callers fall back to text then.

const TILEMAP := preload("res://assets/kenney/input-prompts/Tilemap/tilemap_packed.png")
const TILE := 16
const COLUMNS := 34

## Keycode -> tile, or [tile, width, height] in tiles for bigger keys.
const KEYS := {
	KEY_ESCAPE: 17,
	KEY_F1: 18,
	KEY_F2: 19,
	KEY_F3: 20,
	KEY_F4: 21,
	KEY_F5: 22,
	KEY_F6: 23,
	KEY_F7: 24,
	KEY_F8: 25,
	KEY_F9: 26,
	KEY_F10: 27,
	KEY_F11: 28,
	KEY_F12: 29,
	KEY_QUOTELEFT: 30,
	KEY_1: 51,
	KEY_2: 52,
	KEY_3: 53,
	KEY_4: 54,
	KEY_5: 55,
	KEY_6: 56,
	KEY_7: 57,
	KEY_8: 58,
	KEY_9: 59,
	KEY_0: 60,
	KEY_MINUS: 61,
	KEY_EQUAL: 63,
	KEY_BACKSPACE: [66, 2],
	KEY_ENTER: [100, 2, 2],
	KEY_KP_ENTER: [100, 2, 2],
	KEY_Q: 85,
	KEY_W: 86,
	KEY_E: 87,
	KEY_R: 88,
	KEY_T: 89,
	KEY_Y: 90,
	KEY_U: 91,
	KEY_I: 92,
	KEY_O: 93,
	KEY_P: 94,
	KEY_BRACKETLEFT: 95,
	KEY_BRACKETRIGHT: 96,
	KEY_BACKSLASH: 99,
	KEY_A: 120,
	KEY_S: 121,
	KEY_D: 122,
	KEY_F: 123,
	KEY_G: 124,
	KEY_H: 125,
	KEY_J: 126,
	KEY_K: 127,
	KEY_L: 128,
	KEY_APOSTROPHE: 129,
	KEY_SEMICOLON: 132,
	KEY_SPACE: 153,
	KEY_META: 154,
	KEY_Z: 155,
	KEY_X: 156,
	KEY_C: 157,
	KEY_V: 158,
	KEY_B: 159,
	KEY_N: 160,
	KEY_M: 161,
	KEY_SLASH: 165,
	KEY_UP: 166,
	KEY_RIGHT: 167,
	KEY_DOWN: 168,
	KEY_LEFT: 169,
	KEY_ALT: [187, 2],
	KEY_TAB: [189, 2],
	KEY_DELETE: [191, 2],
	KEY_END: [193, 2],
	KEY_PERIOD: 197,
	KEY_CTRL: [221, 2],
	KEY_CAPSLOCK: [223, 2],
	KEY_HOME: [225, 2],
	KEY_PAGEUP: [227, 2],
	KEY_PAGEDOWN: [229, 2],
	KEY_COMMA: 231,
	KEY_SHIFT: [255, 2],
	KEY_INSERT: [257, 2],
}

const MOUSE_BUTTONS := {
	MOUSE_BUTTON_LEFT: 77,
	MOUSE_BUTTON_RIGHT: 78,
	MOUSE_BUTTON_MIDDLE: 79,
	MOUSE_BUTTON_WHEEL_UP: 80,
	MOUSE_BUTTON_WHEEL_DOWN: 81,
}

## Xbox-style face buttons, matching the "A / Cross" style text labels.
const PAD_BUTTONS := {
	JOY_BUTTON_A: 4,
	JOY_BUTTON_B: 5,
	JOY_BUTTON_X: 6,
	JOY_BUTTON_Y: 7,
	JOY_BUTTON_DPAD_UP: 35,
	JOY_BUTTON_DPAD_RIGHT: 36,
	JOY_BUTTON_DPAD_DOWN: 37,
	JOY_BUTTON_DPAD_LEFT: 38,
	JOY_BUTTON_LEFT_STICK: 424,
	JOY_BUTTON_RIGHT_STICK: 492,
	JOY_BUTTON_LEFT_SHOULDER: 553,
	JOY_BUTTON_RIGHT_SHOULDER: 554,
	JOY_BUTTON_BACK: 616,
	JOY_BUTTON_START: 617,
	JOY_BUTTON_GUIDE: 682,
}

## Glyphs for the fixed rows' names and other inputs that aren't InputEvents.
const NAMED := {
	"Mouse": 76,
	"Wheel": 82,
	"Esc": 17,
	"Start": 617,
	"Left stick": 416,
	"Right stick": 484,
}

static var _cache: Dictionary = {}


## The glyph for one binding, or null if there isn't one.
static func for_event(event: InputEvent) -> Texture2D:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.location != KEY_LOCATION_UNSPECIFIED:
			return null
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return _glyph(KEYS.get(code))
	if event is InputEventMouseButton:
		return _glyph(MOUSE_BUTTONS.get((event as InputEventMouseButton).button_index))
	if event is InputEventJoypadButton:
		return _glyph(PAD_BUTTONS.get((event as InputEventJoypadButton).button_index))
	return null


## The glyph for a name in `NAMED` ("Mouse", "Left stick", ...), or null.
static func named(name: String) -> Texture2D:
	return _glyph(NAMED.get(name))


## `spec` is a tile index, [tile, width, height] (height optional) or null.
static func _glyph(spec: Variant) -> Texture2D:
	if spec == null:
		return null
	var parts: Array = spec if spec is Array else [spec]
	var tile: int = parts[0]
	var tiles := Vector2i(parts[1] if parts.size() > 1 else 1, parts[2] if parts.size() > 2 else 1)
	var id := Vector3i(tile, tiles.x, tiles.y)
	if not _cache.has(id):
		var atlas := AtlasTexture.new()
		atlas.atlas = TILEMAP
		atlas.region = Rect2(Vector2i(tile % COLUMNS, tile / COLUMNS) * TILE, tiles * TILE)
		_cache[id] = atlas
	return _cache[id]
