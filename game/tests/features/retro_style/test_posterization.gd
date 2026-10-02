extends GutTest

const Posterization := preload("res://features/retro_style/posterization.gd")
const Settings := preload("res://features/settings/settings.gd")
var _prior_store := ""


func before_each() -> void:
	_prior_store = SettingsStore.load_text(Posterization.STORE_NAME)
	SettingsStore.save_data(Posterization.STORE_NAME, {})


func after_each() -> void:
	SettingsStore.save_text(Posterization.STORE_NAME, _prior_store)
	Controls.pause()


func test_feature_scene_registers_graphics_and_defaults_off() -> void:
	var feature := preload("res://features/retro_style/feature.tscn").instantiate()
	add_child_autofree(feature)
	var effect: Posterization = feature.get_node("Posterization")
	assert_true(effect.is_in_group(&"settings_pages"))
	assert_eq(effect.settings_page_label(), "Graphics")
	assert_eq(effect.strength, 0.0)
	if DisplayServer.get_name() == "headless":
		assert_null(effect._effect, "Headless servers allocate no fullscreen resources")


func test_strength_updates_pass_and_persists_across_instances() -> void:
	var effect := _new_effect()
	_ensure_pass(effect)
	assert_false(effect._effect.visible)
	assert_eq(effect._copy.copy_mode, BackBufferCopy.COPY_MODE_DISABLED)
	effect.set_strength(0.5)
	assert_true(effect._effect.visible)
	assert_eq(effect._copy.copy_mode, BackBufferCopy.COPY_MODE_VIEWPORT)
	assert_lt(effect._copy.get_index(), effect._effect.get_index(), "Copy before sampling")
	assert_eq(effect._material.get_shader_parameter("levels"), 32.0)
	var reloaded := _new_effect()
	assert_eq(reloaded.strength, 0.5)
	effect.set_strength(0.0)
	assert_false(effect._effect.visible)
	assert_eq(effect._copy.copy_mode, BackBufferCopy.COPY_MODE_DISABLED)
	assert_eq(SettingsStore.load_data(Posterization.STORE_NAME)["strength"], 0.0)


func test_invalid_preferences_fall_back_and_numbers_clamp() -> void:
	for value: Variant in ["bad", true, {}, [], null, INF, NAN]:
		assert_eq(Posterization.normalized_strength(value), 0.0)
	for value: Variant in ["bad", true, {}, [], null]:
		SettingsStore.save_data(Posterization.STORE_NAME, {"strength": value})
		assert_eq(_new_effect().strength, 0.0)
	var effect := _new_effect()
	effect.set_strength(-1.0)
	assert_eq(effect.strength, 0.0)
	effect.set_strength(2.0)
	assert_eq(effect.strength, 1.0)
	effect.set_strength(NAN)
	assert_eq(effect.strength, 0.0)


func test_color_steps_get_coarser_without_crushing_black_and_white() -> void:
	assert_eq(Posterization.color_levels(0.0), 256)
	assert_eq(Posterization.color_levels(0.5), 32)
	assert_eq(Posterization.color_levels(1.0), 4)
	var previous := 256
	for index: int in 101:
		var levels := Posterization.color_levels(float(index) / 100.0)
		assert_lte(levels, previous)
		assert_gte(levels, 4)
		previous = levels


func test_final_pass_is_after_ui_mouse_transparent_and_fills_resizing_viewport() -> void:
	var effect := _new_effect()
	_ensure_pass(effect)
	assert_eq(effect.layer, Posterization.PRESENTATION_LAYER)
	assert_gt(effect.layer, 30, "After HUD, settings, touch controls and emote wheel")
	assert_eq(effect._effect.focus_mode, Control.FOCUS_NONE)
	assert_eq(effect._effect.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(effect._effect.anchor_right, 1.0)
	assert_eq(effect._effect.anchor_bottom, 1.0)
	assert_eq(effect._effect.offset_right, 0.0)
	assert_eq(effect._effect.offset_bottom, 0.0)
	assert_same(effect._material.shader, Posterization.SHADER)
	assert_false(effect.is_processing(), "No per-frame CPU work")


func test_slider_changes_actual_strength_readout_and_rebuild_restores_value() -> void:
	var effect := _new_effect()
	var page := effect.settings_page_build()
	add_child_autofree(page)
	var slider := page.get_node("Strength") as HSlider
	assert_eq(slider.focus_mode, Control.FOCUS_ALL)
	assert_gte(slider.custom_minimum_size.y, 48.0)
	slider.value = 0.75
	assert_eq(effect.strength, 0.75)
	assert_eq(SettingsStore.load_data(Posterization.STORE_NAME)["strength"], 0.75)
	assert_true((page.get_child(2) as Label).text.contains("75%"))
	var rebuilt := effect.settings_page_build()
	add_child_autofree(rebuilt)
	assert_eq((rebuilt.get_node("Strength") as HSlider).value, 0.75)
	slider.value = 0.0
	assert_eq((page.get_child(2) as Label).text, "Strength: Off")


func test_existing_settings_hub_opens_page_and_keeps_modal_lifecycle() -> void:
	var effect := _new_effect()
	var settings := Settings.new()
	add_child_autofree(settings)
	settings.open()
	assert_true(settings.pages().has(effect))
	settings.show_page(effect)
	assert_eq(settings._heading.text, "Graphics")
	assert_true(settings.is_in_group(&"modal_ui"))
	assert_false(Controls.gameplay_active())
	var slider := settings._body.find_child("Strength", true, false) as HSlider
	slider.value = 1.0
	assert_eq(effect.strength, 1.0)
	settings.go_back()
	assert_eq(settings._heading.text, "Settings")
	assert_true(settings.is_open())
	settings.close()
	assert_false(settings.is_in_group(&"modal_ui"))


func _new_effect() -> Posterization:
	var effect := Posterization.new()
	add_child_autofree(effect)
	return effect


func _ensure_pass(effect: Posterization) -> void:
	# Headless runtime intentionally skips GPU allocation; inspect setup explicitly.
	if effect._effect == null:
		effect._build_effect()
