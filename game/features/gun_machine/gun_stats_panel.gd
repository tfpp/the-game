extends CanvasLayer
## Shows the local player's current generated gun: a small always-visible ammo
## readout, and — press Tab — the full rolled stat sheet. The extra UI a randomly
## generated weapon needs, since its specs aren't printed on a fixed item like
## features/holdables' pistol or shotgun.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const TOGGLE_ACTION := &"toggle_gun_stats"
const MODAL_GROUP := &"modal_ui"

var _ammo_label: Label
var _backdrop: Control
var _body: RichTextLabel


func _ready() -> void:
	Controls.ensure_action(TOGGLE_ACTION, [_key_event(KEY_TAB)])
	_ammo_label = Label.new()
	_ammo_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_ammo_label.position = Vector2(-250, -205)
	_ammo_label.size = Vector2(500, 30)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_label.add_theme_font_size_override("font_size", 20)
	_ammo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_ammo_label.add_theme_constant_override("outline_size", 6)
	add_child(_ammo_label)
	_build_panel()


func _process(_delta: float) -> void:
	var rig := _local_rig()
	if rig == null or not rig.is_active():
		_ammo_label.text = ""
		if _is_open():
			_close()
		return
	_ammo_label.text = (
		"%s — %d / %d  (Tab for specs, R to reload)"
		% [str(rig.net_stats["display_name"]), rig.net_ammo_in_mag, rig.net_ammo_reserve]
	)
	if _is_open():
		_body.text = _stats_text(rig)


func _input(event: InputEvent) -> void:
	if _is_open():
		if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(TOGGLE_ACTION):
			get_viewport().set_input_as_handled()
			_close()
		return
	if get_tree().get_first_node_in_group(MODAL_GROUP):
		return
	if event.is_action_pressed(TOGGLE_ACTION):
		var rig := _local_rig()
		if rig == null or not rig.is_active():
			return
		get_viewport().set_input_as_handled()
		_open()


func _open() -> void:
	add_to_group(MODAL_GROUP)
	_backdrop.visible = true


func _close() -> void:
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	_backdrop.visible = false


func _is_open() -> bool:
	return _backdrop.visible


func _local_rig() -> GunRig:
	return GunRig.for_peer(get_tree(), multiplayer.get_unique_id())


func _stats_text(rig: GunRig) -> String:
	var stats := rig.net_stats
	var ammo_type: GunGenerator.AmmoType = stats["ammo_type"]
	var lines: Array[String] = [
		"[b]%s[/b]" % str(stats["display_name"]),
		"Ammo type: %s" % GunGenerator.ammo_name(ammo_type),
		"Barrels: %d" % int(stats["barrel_count"]),
		"Fire rate: %.1f rounds/sec" % float(stats["fire_rate"]),
		"Damage: %.1f per round" % float(stats["damage"]),
		"Magazine: %d / %d loaded" % [rig.net_ammo_in_mag, int(stats["magazine_size"])],
		"Reserve ammo: %d" % rig.net_ammo_reserve,
		"Total ammo capacity: %d" % int(stats["total_ammo"]),
		"Projectile speed: %.0f m/s" % float(stats["projectile_speed"]),
	]
	return "\n".join(lines)


func _build_panel() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.05, 0.06, 0.08, 0.6)
	_backdrop.visible = false
	_backdrop.theme = UI_THEME
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 380
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var heading := Label.new()
	heading.text = "Your gun"
	heading.theme_type_variation = &"HeadingLabel"
	box.add_child(heading)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(380, 0)
	_body.add_theme_color_override("default_color", Color.WHITE)
	box.add_child(_body)

	var footer := Label.new()
	footer.text = "Esc or Tab to close"
	footer.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	box.add_child(footer)


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
