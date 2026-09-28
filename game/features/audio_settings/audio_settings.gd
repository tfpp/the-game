extends Node
## The "Audio" page of the Settings menu (`features/settings/`): overall volume, sound
## effects volume (the `GameSFX` bus from `features/game_audio/`) and a mute switch.
## Saved locally per install through `SettingsStore` ("audio"), as linear volumes
## (0 to 1) plus "muted".

const SETTINGS_PAGES_GROUP := &"settings_pages"
const STORE_NAME := "audio"
const HINT_COLOR := Color(0.22, 0.25, 0.33, 0.75)
## [setting key, bus name, label].
const CHANNELS: Array[Array] = [
	["master", &"Master", "Overall"],
	["effects", &"GameSFX", "Sound effects"],
]

## Linear volume per setting key (0 to 1).
var volumes: Dictionary = {}
var muted := false


func _ready() -> void:
	add_to_group(SETTINGS_PAGES_GROUP)
	var data := SettingsStore.load_data(STORE_NAME)
	for channel: Array in CHANNELS:
		volumes[channel[0]] = clampf(float(data.get(channel[0], 1.0)), 0.0, 1.0)
	muted = bool(data.get("muted", false))
	# The GameSFX bus is created by the game_audio feature, which may load after this.
	apply.call_deferred()


func settings_page_label() -> String:
	return "Audio"


func settings_page_icon() -> Texture2D:
	return preload("res://assets/kenney/game-icons/PNG/White/1x/audioOn.png")


func settings_page_build() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	page.add_child(grid)
	for channel: Array in CHANNELS:
		_slider(grid, channel[0], channel[2])
	var mute := CheckButton.new()
	mute.text = "Mute all sound"
	mute.button_pressed = muted
	mute.toggled.connect(set_muted)
	page.add_child(mute)
	var note := Label.new()
	note.text = "Voice chat plays at the overall volume."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", HINT_COLOR)
	page.add_child(note)
	return page


func set_volume(key: String, linear: float) -> void:
	volumes[key] = clampf(linear, 0.0, 1.0)
	apply()
	_save()


func set_muted(value: bool) -> void:
	muted = value
	apply()
	_save()


## Pushes the saved volumes onto the audio buses that exist.
func apply() -> void:
	for channel: Array in CHANNELS:
		var index := AudioServer.get_bus_index(channel[1])
		if index < 0:
			continue
		var linear: float = volumes.get(channel[0], 1.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(linear, 0.0001)))
		var silent: bool = linear <= 0.0 or (muted and channel[1] == &"Master")
		AudioServer.set_bus_mute(index, silent)


func _save() -> void:
	var data := {"muted": muted}
	for key: String in volumes:
		data[key] = volumes[key]
	SettingsStore.save_data(STORE_NAME, data)


func _slider(grid: GridContainer, key: String, label: String) -> void:
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size.x = 140
	grid.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = volumes.get(key, 1.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 28
	grid.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size.x = 56
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.text = _percent(slider.value)
	grid.add_child(readout)
	slider.value_changed.connect(
		func(next: float) -> void:
			readout.text = _percent(next)
			set_volume(key, next)
	)


static func _percent(linear: float) -> String:
	return "%d%%" % roundi(linear * 100.0)
