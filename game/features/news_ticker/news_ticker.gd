class_name NewsTicker
extends Node3D
## Hanging flat screen over the casino's gaming floor with a scrolling BREAKING NEWS
## ticker. Only the server fetches TheNewsAPI top stories, using the
## `THENEWSAPI_TOKEN` environment variable, and replicates the headlines to every peer
## through `Sync`. The token never ships in the repository or to clients.

const TOKEN_ENV := "THENEWSAPI_TOKEN"
const API_URL := "https://api.thenewsapi.com/v1/news/top"
const REFRESH_SECONDS := 900.0
const RETRY_SECONDS := 60.0
const MAX_HEADLINES := 10
const SCROLL_SPEED := 180.0
const SEPARATOR := "   ✦   "
const FALLBACK := "Welcome to the Gilded Lily — stay tuned for the latest headlines"
const SCREEN_SIZE := Vector2(4.8, 1.2)
const VIEWPORT_SIZE := Vector2i(1280, 320)

## Server-owned, replicated headline list.
@export var headlines: PackedStringArray = PackedStringArray()

var _ticker: Label
var _viewport: SubViewport
var _shown_text := ""
var _next_fetch := 0.0
var _fetching := false


func _ready() -> void:
	_build_screen()


func _process(delta: float) -> void:
	var text := ticker_text(headlines)
	if text != _shown_text:
		_shown_text = text
		_ticker.text = text + SEPARATOR
		_ticker.position.x = VIEWPORT_SIZE.x
		_ticker.reset_size()
	_ticker.position.x -= SCROLL_SPEED * delta
	if _ticker.position.x < -_ticker.size.x:
		_ticker.position.x = VIEWPORT_SIZE.x
	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		_next_fetch -= delta
		if _next_fetch <= 0.0 and not _fetching:
			_fetch()


## Joins headlines into one ticker line, or returns the fallback when empty.
static func ticker_text(lines: PackedStringArray) -> String:
	if lines.is_empty():
		return FALLBACK
	return SEPARATOR.join(lines)


## Extracts trimmed, non-empty titles from a TheNewsAPI JSON response body.
static func parse_headlines(body: String) -> PackedStringArray:
	var result := PackedStringArray()
	var json := JSON.new()
	if json.parse(body) != OK or not json.data is Dictionary:
		return result
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return result
	var data: Variant = (parsed as Dictionary).get("data")
	if not data is Array:
		return result
	for item: Variant in data:
		if not item is Dictionary:
			continue
		var title := str((item as Dictionary).get("title", "")).strip_edges()
		title = title.replace("\n", " ")
		if not title.is_empty():
			result.append(title.left(200))
		if result.size() >= MAX_HEADLINES:
			break
	return result


func _fetch() -> void:
	var token := OS.get_environment(TOKEN_ENV)
	if token.is_empty():
		_next_fetch = INF
		return
	_fetching = true
	_next_fetch = RETRY_SECONDS
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	var url := "%s?api_token=%s&language=en&limit=%d" % [API_URL, token.uri_encode(), 3]
	if request.request(url) != OK:
		request.queue_free()
		_fetching = false
		return
	var response: Array = await request.request_completed
	request.queue_free()
	_fetching = false
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200:
		push_warning("NewsTicker: headline fetch failed (HTTP %d)" % int(response[1]))
		return
	var bytes: PackedByteArray = response[3]
	var lines := parse_headlines(bytes.get_string_from_utf8())
	if not lines.is_empty():
		headlines = lines
		_next_fetch = REFRESH_SECONDS


func _build_screen() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var background := ColorRect.new()
	background.color = Color(0.05, 0.05, 0.12)
	background.size = VIEWPORT_SIZE
	_viewport.add_child(background)
	var banner := ColorRect.new()
	banner.color = Color(0.8, 0.0, 0.0)
	banner.size = Vector2(VIEWPORT_SIZE.x, 140)
	_viewport.add_child(banner)
	var title := Label.new()
	title.text = "BREAKING NEWS"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.position = Vector2(40, 8)
	_viewport.add_child(title)
	_ticker = Label.new()
	_ticker.name = "Ticker"
	_ticker.add_theme_font_size_override("font_size", 110)
	_ticker.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_ticker.position = Vector2(VIEWPORT_SIZE.x, 160)
	_viewport.add_child(_ticker)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _viewport.get_texture()
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color(0.08, 0.08, 0.08)
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(SCREEN_SIZE.x + 0.2, SCREEN_SIZE.y + 0.2, 0.12)
	frame.mesh = box
	frame.material_override = frame_material
	add_child(frame)
	# One face per side so the ticker reads from both halves of the floor.
	for side: int in 2:
		var face := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = SCREEN_SIZE
		face.mesh = quad
		face.material_override = material
		face.position.z = 0.061 if side == 0 else -0.061
		face.rotation.y = 0.0 if side == 0 else PI
		add_child(face)
