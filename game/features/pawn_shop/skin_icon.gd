class_name PrawnSkinIcon
extends TextureRect
## Cached actual classic weapon preview, with the same paint used in gameplay.

var skin := ""
var _renderer: ModelIconRenderer


func _ready() -> void:
	custom_minimum_size = Vector2(96, 96)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not PrawnSkinCatalog.SKINS.has(skin) or DisplayServer.get_name() == "headless":
		return
	_renderer = ModelIconRenderer.for_control(self)
	_renderer.rendered.connect(_rendered)
	texture = _renderer.request_model("prawn:" + skin, PrawnSkinAppearance.create_view.bind(skin))


func _rendered(key: String, value: Texture2D) -> void:
	if key == "model:prawn:" + skin:
		texture = value
