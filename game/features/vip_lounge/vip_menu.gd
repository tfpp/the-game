extends CanvasLayer
## Local, responsive club menu. All buttons send fixed requests to nearby stations.

var root: Control
var panel: PanelContainer
var heading: Label
var description: Label
var summary: Label
var status: Label
var hud: Label
var toast: Label
var fade: ColorRect
var actions: VBoxContainer
var active: VipStation
var waiting := false
var buttons: Array[Button] = []
var font: Font = preload("res://assets/fonts/inter/Inter-Regular.ttf").duplicate()
@onready var club: VipLounge = get_parent()


func _ready() -> void:
	layer = 12
	_build()
	_resize()
	get_viewport().size_changed.connect(_resize)
	Controls.menu_requested.connect(close.bind(false))
	Network.mode_changed.connect(func(_mode: Network.Mode) -> void: close(false))
	for node: Node in club.get_children():
		var endpoint := node.get_node_or_null("NetworkedEntity") as NetworkedInteraction
		if endpoint != null:
			endpoint.event_received.connect(_event.bind(node))
			endpoint.request_finished.connect(_finished)


func _event(event: StringName, payload: Dictionary, source: Node) -> void:
	if event == &"menu" and source is VipStation:
		active = source as VipStation
		waiting = false
		_open()
	elif event == &"receipt":
		waiting = false
		status.text = str(payload.get("text", ""))
		_notice(status.text)
	elif event == &"arrival":
		GameAudio.play_ui(self, &"elevator_ding")
		close()
		fade.color.a = 1.0
		create_tween().tween_property(fade, "color:a", 0.0, 0.8)
		_notice(str(payload.get("text", "")))


func _finished(action: StringName, result: NetworkedEntity.Result) -> void:
	if action == &"service" and result != NetworkedEntity.Result.ACCEPTED:
		waiting = false
		status.text = "Service unavailable. Check the cooldown or move closer and try again."


func _notice(text: String) -> void:
	toast.text = text
	toast.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(toast, "modulate:a", 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if (
		panel.visible
		and (event.is_action_pressed(&"release_mouse") or event.is_action_pressed(&"ui_cancel"))
	):
		get_viewport().set_input_as_handled()
		close()


func _process(_delta: float) -> void:
	var row := club.profile(multiplayer.get_unique_id())
	hud.text = ""
	if not row.is_empty():
		if row.get("inside", false):
			hud.text = "MIRROR CLUB · %s · %d lounge XP" % [VipRules.title_for(row), int(row["xp"])]
		for field: String in VipRules.DRINKS:
			if int(row.get(field, 0)) > 0:
				hud.text += "\n%s %s" % [VipRules.DRINKS[field], _time(int(row[field]))]
	hud.visible = not hud.text.is_empty()
	if not panel.visible:
		return
	var player := (
		active.entity.player_for_peer(multiplayer.get_unique_id())
		if is_instance_valid(active)
		else null
	)
	if player == null or not active.can_use(player):
		close()
		return
	if row.is_empty():
		return
	summary.text = _summary(row)
	for button: Button in buttons:
		var action := str(button.get_meta("action"))
		var cooldown := int(row.get(action + "_ready", 0))
		if action == "gift":
			cooldown = int(row.get("gift_ready", 0))
		button.disabled = waiting or cooldown > 0
		if action == "mission":
			button.disabled = button.disabled or not VipRules.mission_ready(row)
		elif action in ["shirt", "pants"]:
			button.disabled = (
				button.disabled
				or not row.get("mission", false)
				or action in row.get("wardrobe", [])
			)
		button.text = (
			str(button.get_meta("label")) + (" · " + _time(cooldown) if cooldown > 0 else "")
		)


func _open() -> void:
	for node: Node in actions.get_children():
		actions.remove_child(node)
		node.queue_free()
	buttons.clear()
	heading.text = "THE MIRROR CLUB — " + active.host_name.to_upper()
	status.text = ""
	match active.host_name:
		"Scarlett":
			description.text = (
				"Scarlett, 28 · Your discreet hostess\nWelcome upstairs. "
				+ "Your daily surprise is on the house. Gifts reset at midnight UTC."
			)
			_button("Claim daily mystery gift", "gift")
		"Jade":
			description.text = (
				"Jade, 30 · The Whisper Menu\nComplimentary drinks; "
				+ "hold and use to drink. Orders have a 30-minute cooldown. "
				+ "Boosts start after drinking; same boosts never stack. "
				+ "Luck affects private table wins and gift rarity."
			)
			_button("Order Luck Cocktail · +500% luck · 5 min", "luck")
			_button("Order Golden Hour · 2× lounge XP · 10 min", "golden")
			_button("Order Velvet Reserve · 4× gift rarity · 10 min", "velvet")
		"Valentina":
			description.text = (
				"Valentina, 29 · A private invitation\nMeet all three hosts, "
				+ "finish a private table round, and find the small crown by the window. "
				+ "Your reward: $100, a title, and an evening outfit."
			)
			_button("Complete the secret invitation", "mission")
			_button("Collect gold evening shirt", "shirt")
			_button("Collect midnight trousers", "pants")
		_:
			description.text = (
				"PRIVATE TRIPLE MATCH\nThree matching symbols pay 10×–30× your stake. "
				+ "Base win chance: 4%; Luck Cocktail: 24%."
			)
			for wager: int in VipRules.WAGERS:
				_button("Play · " + PlayerMoney.format_money(wager), "play", {"wager": wager})
	panel.show()
	add_to_group(&"modal_ui")
	Controls.pause()
	if not buttons.is_empty():
		buttons[0].grab_focus()


func _button(label: String, action: String, options: Dictionary = {}) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 44
	button.set_meta("action", action)
	button.set_meta("label", label)
	button.pressed.connect(_request.bind(action, options))
	actions.add_child(button)
	buttons.append(button)


func _request(action: String, options: Dictionary) -> void:
	if waiting or not is_instance_valid(active):
		return
	waiting = true
	status.text = "Checking the guest book…"
	active.entity.request_action(&"service", {"action": action, "options": options})


static func _time(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func _summary(row: Dictionary) -> String:
	if row.is_empty():
		return ""
	var collection: Array = row.get("collection", [])
	return (
		"%s · %d lounge XP\nInvitation: hosts %d/3 · table %s · crown %s\nGlass collection: %s"
		% [
			VipRules.title_for(row),
			int(row["xp"]),
			row["hosts"].size(),
			"✓" if row["played"] else "—",
			"✓" if row["symbol"] else "—",
			", ".join(collection) if not collection.is_empty() else "Discover your first gift"
		]
	)


func close(resume := true) -> void:
	if not panel.visible:
		return
	panel.hide()
	remove_from_group(&"modal_ui")
	if resume:
		Controls.start()


func _build() -> void:
	root = Control.new()
	root.theme = preload("res://ui/theme/ui_theme.tres").duplicate()
	root.theme.default_font = font
	root.theme.default_font_size = 15
	root.theme.set_color("font_color", "Label", Color("f0dfc0"))
	root.theme.set_font("font", "Button", font)
	root.theme.set_font_size("font_size", "Button", 14)
	var panel_style := _style(Color("241b1c"), Color("a78446"))
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 18
	panel_style.content_margin_bottom = 18
	root.theme.set_stylebox("panel", "PanelContainer", panel_style)
	root.theme.set_stylebox("normal", "Button", _style(Color("3b2823"), Color("927240")))
	root.theme.set_stylebox("hover", "Button", _style(Color("57402b"), Color("edc978")))
	root.theme.set_stylebox("pressed", "Button", _style(Color("705431"), Color("edc978")))
	root.theme.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), Color("edc978")))
	root.theme.set_stylebox("disabled", "Button", _style(Color("292323"), Color("524539")))
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 300
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	heading = _label(column)
	heading.add_theme_color_override("font_color", Color("e3bb6b"))
	description = _label(column)
	actions = VBoxContainer.new()
	column.add_child(actions)
	summary = _label(column)
	status = _label(column)
	var dismiss := Button.new()
	dismiss.text = "Close"
	dismiss.custom_minimum_size.y = 44
	dismiss.pressed.connect(close)
	column.add_child(dismiss)
	hud = _label(root)
	hud.position = Vector2(16, 115)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_constant_override("outline_size", 3)
	hud.add_theme_color_override("font_outline_color", Color.BLACK)
	toast = _label(root)
	toast.position = Vector2(16, 210)
	toast.modulate.a = 0.0
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_constant_override("outline_size", 3)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	fade = ColorRect.new()
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.color = Color(0.03, 0.02, 0.01, 0)
	root.add_child(fade)
	panel.hide()


func _style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _label(parent: Node) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 280
	parent.add_child(label)
	return label


func _resize() -> void:
	var logical := get_viewport().get_visible_rect().size
	var physical := Vector2(get_window().size)
	var ui_scale := maxf(1.0, logical.x / maxf(physical.x, 1.0))
	scale = Vector2.ONE * ui_scale
	font.set("oversampling", ui_scale)
	root.size = logical / ui_scale
	panel.custom_minimum_size = Vector2(minf(440, root.size.x - 24), minf(550, root.size.y - 24))
	panel.size = panel.custom_minimum_size
