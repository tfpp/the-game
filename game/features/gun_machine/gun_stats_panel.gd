extends CanvasLayer
## Shows the local player's current generated gun: `ammo_text()` feeds the ammo line of
## the weapon panel (features/weapon_hotbar), and — press Tab — the full rolled stat
## sheet. The extra UI a randomly generated weapon needs, since its specs aren't printed
## on a fixed item like features/holdables' pistol or shotgun.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const TOGGLE_ACTION := &"toggle_gun_stats"
const MODAL_GROUP := &"modal_ui"

var _backdrop: Control
var _body: RichTextLabel


func _ready() -> void:
	Controls.ensure_action(TOGGLE_ACTION, [_key_event(KEY_TAB)])
	_build_panel()


func _process(_delta: float) -> void:
	var rig := _local_rig()
	if rig == null or not rig.is_active():
		if _is_open():
			_close()
		return
	if _is_open():
		_body.text = _stats_text(rig)


## "loaded / reserve" for the held gun (the active rig, or a holdable with a magazine),
## a bare count for other ammo-fed holdables, plus "Reloading…" while reloading.
## Empty when nothing ammo-fed is held.
static func ammo_text(tree: SceneTree, peer: int) -> String:
	var rig := GunRig.for_peer(tree, peer)
	if rig != null and rig.is_active():
		return "%d / %d" % [rig.net_ammo_in_mag, rig.net_ammo_reserve]
	var hand := Hand.for_peer(tree, peer)
	if hand == null:
		return ""
	var weapon := hand.net_item_id
	var magazine := hand.magazine_for(weapon)
	if magazine != null:
		var loaded := magazine.loaded()
		var reserve := maxi(0, hand.inventory().ammo_for(weapon) - loaded)
		return "%d / %d%s" % [loaded, reserve, "  Reloading…" if magazine.active() else ""]
	if ItemCatalog.AMMO_PACKS.has(ItemCatalog.base_weapon(weapon)):
		return "%d" % hand.inventory().ammo_for(weapon)
	return ""


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
		"Fire mode: %s" % ("Automatic" if bool(stats.get("is_automatic", false)) else "Semi-auto"),
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
	_body.add_theme_color_override("default_color", Color(0.2, 0.12, 0.08))
	box.add_child(_body)

	var footer := Label.new()
	footer.text = "Esc or Tab to close"
	footer.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	box.add_child(footer)


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
