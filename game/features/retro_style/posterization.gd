extends CanvasLayer
## Local viewport presentation, after all 3D (including held items), before the HUD.

const STORE_NAME := "posterization"
const SHADER := preload("res://features/retro_style/posterization.gdshader")

var strength := 0.0
var _effect: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = -1
	add_to_group(&"settings_pages")
	strength = normalized_strength(SettingsStore.load_data(STORE_NAME).get("strength", 0.0))
	if DisplayServer.get_name() != "headless" and Network.mode != Network.Mode.SERVER:
		_build_effect()


func settings_page_label() -> String:
	return "Graphics"


func settings_page_build() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	var heading := Label.new()
	heading.text = "Experimental posterization"
	page.add_child(heading)
	var description := Label.new()
	description.text = (
		"Squash the world's color range, including equipped items. "
		+ "Higher strength uses fewer color steps; HUD and menus stay unchanged."
	)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(description)
	var readout := Label.new()
	readout.text = _readout(strength)
	page.add_child(readout)
	var slider := HSlider.new()
	slider.name = "Strength"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = strength
	slider.custom_minimum_size.y = 48
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "Posterization strength: 0% is off, 100% is the coarsest palette."
	page.add_child(slider)
	slider.value_changed.connect(
		func(next: float) -> void:
			set_strength(next)
			readout.text = _readout(strength)
	)
	return page


func set_strength(value: float) -> void:
	strength = normalized_strength(value)
	_apply()
	SettingsStore.save_data(STORE_NAME, {"strength": strength})


static func normalized_strength(value: Variant) -> float:
	if not (value is float or value is int):
		return 0.0
	var number := float(value)
	return clampf(number, 0.0, 1.0) if is_finite(number) else 0.0


static func color_levels(value: float) -> int:
	# Roughly 8 through 2 bits per channel; intentionally not a fixed historical palette.
	return roundi(pow(2.0, lerpf(8.0, 2.0, normalized_strength(value))))


func _build_effect() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_effect = ColorRect.new()
	_effect.name = "WorldPosterization"
	_effect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_effect.material = _material
	add_child(_effect)
	_apply()


func _apply() -> void:
	if _effect == null:
		return
	# Hidden at zero: no fullscreen draw or screen-texture copy when opted out.
	_effect.visible = strength > 0.0
	_material.set_shader_parameter("levels", float(color_levels(strength)))


static func _readout(value: float) -> String:
	if value <= 0.0:
		return "Strength: Off"
	return "Strength: %d%% · %d steps per channel" % [roundi(value * 100.0), color_levels(value)]
