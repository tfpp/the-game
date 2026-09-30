extends CanvasLayer
## Read-only view of existing replicated buffs; never writes gameplay state.

var _root: Control
var _label: Label
var _close_button: Button
var _font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()


func _ready() -> void:
	layer = 9
	add_to_group(&"esc_menu_links")
	_build()
	get_viewport().size_changed.connect(_resize)
	_resize()
	Controls.menu_requested.connect(_close.bind(false))
	Network.mode_changed.connect(func(_mode: Network.Mode) -> void: _close(false))


func esc_menu_label() -> String:
	return "Player stats"


func esc_menu_open() -> void:
	_root.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	_refresh()
	_close_button.grab_focus()


func _input(event: InputEvent) -> void:
	if (
		_root.visible
		and (event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"))
	):
		get_viewport().set_input_as_handled()
		_close()


func _process(_delta: float) -> void:
	if _root.visible:
		_refresh()


func _refresh() -> void:
	var bar := get_parent() as BarCompanion
	var peer := multiplayer.get_unique_id()
	var prayer := get_tree().get_first_node_in_group(&"kaaba_prayer") as KaabaPrayer
	var blessings := prayer.blessings_for(peer) if prayer != null else 0
	_label.text = describe(
		bar.charisma_for(peer), bar.intoxication_for(peer), bar.luck_seconds_for(peer), blessings
	)


static func describe(charisma: int, intox: int, luck: int, blessings: int) -> String:
	var text := (
		"Charisma: %d / 10\nIntoxication: %d / 10 (%s)\n" % [charisma, intox, CharmMath.mood(intox)]
	)
	text += "\nVivienne's price: %s\n" % PlayerMoney.format_money(CharmMath.price_cents(charisma))
	text += "Charisma lowers her price by 7% per point.\n"
	if intox > CharmMath.TIPSY_DRINKS:
		text += "Debuff: too drunk — drinks past three reduce charisma.\n"
	elif intox > 0:
		text += "Buff: tipsy — the first three drinks add charisma.\n"
	else:
		text += "No drink buff or debuff.\n"
	text += "\nLucky night: "
	text += (
		("%d:%02d — +2 extra slot rolls (offline/dev)." % [luck / 60, luck % 60])
		if luck > 0
		else "inactive."
	)
	text += "\nKaaba blessings: %d / 5 (+%d%% base slot chance).\n" % [blessings, blessings * 200]
	text += "\nWin charisma fades 1/min; drinks fade 1/90s. Bar timers continue while signed out."
	return text


func _close(resume := true) -> void:
	if not _root.visible:
		return
	_root.hide()
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _build() -> void:
	_root = Control.new()
	_root.theme = preload("res://ui/theme/ui_theme.tres").duplicate()
	_root.theme.default_font = _font
	_root.theme.default_font_size = 16
	_root.theme.set_font("font", "Button", _font)
	_root.theme.set_font_size("font_size", "Button", 16)
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 290
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "PLAYER STATS"
	column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_label = Label.new()
	_label.custom_minimum_size.x = 270
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(_label)
	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size.y = 44
	_close_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	_close_button.pressed.connect(_close)
	column.add_child(_close_button)
	_root.hide()


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	_font.set("oversampling", ui_scale)
	_root.size = logical / ui_scale
