extends CanvasLayer
## In-game feature changelog: open "Release notes" from the Esc menu (or press L) to see
## what's shipped, Esc or L again to close.
##
## The entries live in entries.gd so new features can add to the list without touching
## this script (see AGENTS.md for the rule that every new feature must add one). This
## is static, read-only content baked into the client, so it needs no server round trip.
##
## Builds from main group entries under "Edge" (added since the latest release) and the
## last 10 releases: the web export generates releases.gd (scripts/release_notes.sh at
## the repo root) from the vX.Y.Z tags, mapping each release to the entry titles it
## added. Builds without releases.gd (local runs, PR previews) list every entry.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const TOGGLE_ACTION := &"toggle_changelog"
const MODAL_GROUP := &"modal_ui"
## Nodes in this group get a link in the Esc menu (`ui/login/login_screen.gd`); they
## must implement `esc_menu_label() -> String` and `esc_menu_open() -> void`, and may
## implement `esc_menu_icon() -> Texture2D`.
const ESC_MENU_GROUP := &"esc_menu_links"
const PANEL_WIDTH := 420.0
const PANEL_MAX_HEIGHT := 480.0
const RELEASES_PATH := "res://features/changelog/releases.gd"
## The `version` of the pseudo-release for entries added since the latest release.
const EDGE := "edge"
const MONTHS: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

var _backdrop: Control


func _ready() -> void:
	Controls.ensure_action(TOGGLE_ACTION, [_key_event(KEY_L)])
	add_to_group(ESC_MENU_GROUP)
	_build()


func _input(event: InputEvent) -> void:
	if _is_open():
		if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(TOGGLE_ACTION):
			get_viewport().set_input_as_handled()
			_close()
		return
	if get_tree().get_first_node_in_group(MODAL_GROUP):
		return
	if event.is_action_pressed(TOGGLE_ACTION):
		get_viewport().set_input_as_handled()
		_open()


func esc_menu_label() -> String:
	return "Release notes"


func esc_menu_icon() -> Texture2D:
	return preload("res://assets/kenney/game-icons/PNG/White/1x/information.png")


func esc_menu_open() -> void:
	_open()


## One BBCode line for `entry`, tolerant of missing keys so a malformed entry can't
## crash the panel.
static func entry_line(entry: Dictionary) -> String:
	var title := str(entry.get("title", ""))
	var summary := str(entry.get("summary", ""))
	return "[b]%s[/b] — %s" % [title, summary]


## The full BBCode body, one line per entry, in the order given.
static func body_text(entries: Array[Dictionary]) -> String:
	var lines: Array[String] = []
	for entry: Dictionary in entries:
		lines.append(entry_line(entry))
	return "\n".join(lines)


## The generated releases (see releases.gd above), newest first, after an EDGE
## pseudo-release with the entries since the latest one; [] without releases.gd.
static func load_releases() -> Array:
	if not ResourceLoader.exists(RELEASES_PATH):
		return []
	var script := load(RELEASES_PATH) as GDScript
	if script == null:
		return []
	var constants := script.get_script_constant_map()
	return (
		[{"version": EDGE, "titles": constants.get("EDGE", [])}]
		+ Array(constants.get("RELEASES", []))
	)


## "Sep 28, 2026" for "2026-09-28"; anything else is returned unchanged.
static func date_text(iso: String) -> String:
	var parts := iso.split("-")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return iso
	var month := parts[1].to_int()
	if month < 1 or month > 12:
		return iso
	return "%s %d, %s" % [MONTHS[month - 1], parts[2].to_int(), parts[0]]


## The BBCode body grouped by release: a heading per release, then the entries it added
## (from `entries`, matched by title). An empty EDGE is left out.
static func releases_text(releases: Array, entries: Array[Dictionary]) -> String:
	var by_title := {}
	for entry: Dictionary in entries:
		by_title[str(entry.get("title", ""))] = entry
	var blocks: Array[String] = []
	for release: Variant in releases:
		if not release is Dictionary:
			continue
		var version := str(release.get("version", "?"))
		var titles: Array = release.get("titles", [])
		if version == EDGE and titles.is_empty():
			continue
		var lines: Array[String] = [
			(
				"[font_size=20][b]%s[/b][/font_size]  [color=#ffffff99]%s[/color]"
				% (
					["Edge", "not released yet"]
					if version == EDGE
					else ["v" + version, date_text(str(release.get("date", "")))]
				)
			)
		]
		for title: Variant in titles:
			var entry: Dictionary = by_title.get(str(title), {"title": str(title)})
			lines.append(entry_line(entry) if entry.has("summary") else "[b]%s[/b]" % str(title))
		if lines.size() == 1:
			lines.append("Fixes and improvements.")
		blocks.append("\n".join(lines))
	return "\n\n".join(blocks)


func _open() -> void:
	add_to_group(MODAL_GROUP)
	_backdrop.visible = true


func _close() -> void:
	if is_in_group(MODAL_GROUP):
		remove_from_group(MODAL_GROUP)
	_backdrop.visible = false


func _is_open() -> bool:
	return _backdrop.visible


func _build() -> void:
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
	panel.custom_minimum_size.x = PANEL_WIDTH
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var heading := Label.new()
	heading.text = "What's new"
	heading.theme_type_variation = &"HeadingLabel"
	box.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_MAX_HEIGHT)
	box.add_child(scroll)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	body.add_theme_color_override("default_color", Color.WHITE)
	var releases := load_releases()
	body.text = (
		releases_text(releases, ChangelogEntries.ENTRIES)
		if releases
		else body_text(ChangelogEntries.ENTRIES)
	)
	scroll.add_child(body)

	var footer := Label.new()
	footer.text = "Esc or L to close"
	footer.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.6))
	box.add_child(footer)


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
