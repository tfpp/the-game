extends CanvasLayer
## In-game feature changelog: open "Release notes" from the Esc menu (or press L) to see
## what's shipped, Esc or L again to close.
##
## Entries are collated from each feature's release_notes/*.json plus frozen legacy
## entries.gd (see AGENTS.md). This
## is static, read-only content baked into the client, so it needs no server round trip.
##
## Entries are grouped under "Edge" (added since the latest release, headed with the
## build's short commit) and the last 10
## releases, from scripts/release_notes.sh at the repo root, which maps each vX.Y.Z tag
## to the entry titles it added. The web export bakes its output into releases.gd; local
## debug runs call it on the checkout (with uncommitted entries) when the panel first
## opens. Without either (PR previews, or no git), the panel lists every entry.

const UI_THEME := preload("res://ui/theme/ui_theme.tres")
const TOGGLE_ACTION := &"toggle_changelog"
const MODAL_GROUP := &"modal_ui"
## Nodes in this group get a link in the Esc menu (`ui/login/login_screen.gd`); they
## must implement `esc_menu_label() -> String` and `esc_menu_open() -> void`, and may
## implement `esc_menu_icon() -> Texture2D`.
const ESC_MENU_GROUP := &"esc_menu_links"
const PANEL_WIDTH := 640.0
const PANEL_MAX_HEIGHT := 520.0
## Room the panel keeps from the screen edges on narrow screens.
const SCREEN_MARGIN := 32.0
## The light sheet the notes sit on, inside ui_theme.tres's panel.
const SHEET_COLOR := Color("#f6f7fb")
const SHEET_BORDER := Color("#c3c9d6")
const SHEET_PADDING := 16.0
## Colors on the sheet: slate text, a lighter slate for summaries and dates, and a light
## blue from ui_theme.tres's buttons for the edge and release headings (and bullets).
const TEXT_COLOR := "#232838"
const MUTED_COLOR := "#566074"
const RELEASE_COLOR := "#36bdf7"
const EDGE_COLOR := "#36bdf7"
## A short blank line between releases.
const RELEASE_GAP := "\n[font_size=8]\n[/font_size]"
## The body's bold font, so `[b]` means a heading (and nothing gets a faux bold).
const HEADING_FONT := preload("res://assets/fonts/exo2/Exo2-Bold.ttf")
const RELEASES_PATH := "res://features/changelog/releases.gd"
## The `version` of the pseudo-release for entries added since the latest release.
const EDGE := "edge"
const MONTHS: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

var _backdrop: Control
var _body: RichTextLabel


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


## One bulleted row for `entry` (see entry_list): the title, then the summary in a
## smaller, muted line. Tolerant of missing keys so a malformed entry can't crash the
## panel.
static func entry_line(entry: Dictionary) -> String:
	var text := (
		"[color=%s][font_size=19]%s[/font_size][/color]" % [TEXT_COLOR, str(entry.get("title", ""))]
	)
	var summary := str(entry.get("summary", ""))
	if summary:
		text += "\n[color=%s][font_size=16]%s[/font_size][/color]" % [MUTED_COLOR, summary]
	return (
		"[cell padding=0,1,10,0][color=%s]•[/color][/cell][cell padding=0,0,0,10]%s[/cell]"
		% [RELEASE_COLOR, text]
	)


## Rows from entry_line as a bulleted list: a two-column table, so wrapped lines hang
## under the text instead of the bullet.
static func entry_list(rows: Array[String]) -> String:
	return "[table=2]%s[/table]" % "".join(rows) if rows else ""


## A release heading: the version in the heading font (the body's bold font) and an
## accent color, then the date, small and muted.
static func heading_text(title: String, color: String, detail: String) -> String:
	return (
		"[b][font_size=24][color=%s]%s[/color][/font_size][/b]" % [color, title]
		+ (
			"   [color=%s][font_size=15]%s[/font_size][/color]" % [MUTED_COLOR, detail]
			if detail
			else ""
		)
	)


## The full BBCode body without releases: every entry, in the order given.
static func body_text(entries: Array[Dictionary]) -> String:
	var rows: Array[String] = []
	for entry: Dictionary in entries:
		rows.append(entry_line(entry))
	return entry_list(rows)


## The exported releases.gd's releases (see releases_from), or [] without it.
static func load_releases() -> Array:
	if not ResourceLoader.exists(RELEASES_PATH):
		return []
	return releases_from(load(RELEASES_PATH) as GDScript)


## Local debug runs: runs scripts/release_notes.sh on the checkout, or [] if it can't.
## Skipped headless (tests, the dedicated server).
static func local_releases() -> Array:
	if not OS.is_debug_build() or OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return []
	var notes := ProjectSettings.globalize_path("res://").path_join("../scripts/release_notes.sh")
	if not FileAccess.file_exists(notes):
		return []
	var output := []
	if OS.execute("bash", [notes, "WORKTREE"], output) != OK or output.is_empty():
		push_warning("scripts/release_notes.sh failed; listing every changelog entry")
		return []
	var script := GDScript.new()
	script.source_code = str(output[0])
	return releases_from(script) if script.reload() == OK else []


## A release notes script's releases, newest first, after an EDGE pseudo-release with
## the entries since the latest one.
static func releases_from(script: GDScript) -> Array:
	if script == null:
		return []
	var constants := script.get_script_constant_map()
	return (
		[
			{
				"version": EDGE,
				"commit": constants.get("COMMIT", ""),
				"titles": constants.get("EDGE", [])
			}
		]
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
		var head := (
			heading_text("Edge", EDGE_COLOR, str(release.get("commit", "")))
			if version == EDGE
			else heading_text("v" + version, RELEASE_COLOR, date_text(str(release.get("date", ""))))
		)
		var rows: Array[String] = []
		for title: Variant in titles:
			rows.append(entry_line(by_title.get(str(title), {"title": str(title)})))
		if rows.is_empty():
			rows.append(entry_line({"title": "Fixes and improvements"}))
		blocks.append(head + "\n" + entry_list(rows))
	return RELEASE_GAP.join(blocks)


func _open() -> void:
	if _body.text.is_empty():
		_body.text = _text()
	add_to_group(MODAL_GROUP)
	_backdrop.visible = true


## The panel's body, built on first open so local runs only call git when asked.
func _text() -> String:
	var releases := load_releases()
	if releases.is_empty():
		releases = local_releases()
	if releases.is_empty():
		return body_text(ChangelogEntries.all_entries())
	return releases_text(releases, ChangelogEntries.all_entries())


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
	var width := minf(PANEL_WIDTH, get_viewport().get_visible_rect().size.x - 2.0 * SCREEN_MARGIN)
	panel.custom_minimum_size.x = width
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var heading := Label.new()
	heading.text = "What's new"
	heading.theme_type_variation = &"HeadingLabel"
	box.add_child(heading)

	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", _sheet_style())
	box.add_child(sheet)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width - 2.0 * SHEET_PADDING, PANEL_MAX_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Leaves room for the scrollbar.
	_body.custom_minimum_size = Vector2(width - 2.0 * SHEET_PADDING - 24.0, 0.0)
	_body.add_theme_color_override("default_color", Color(TEXT_COLOR))
	_body.add_theme_font_override("bold_font", HEADING_FONT)
	scroll.add_child(_body)

	var footer := Label.new()
	footer.text = "Esc or L to close"
	footer.add_theme_color_override("font_color", Color(0.22, 0.25, 0.33, 0.8))
	box.add_child(footer)


func _sheet_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = SHEET_COLOR
	style.border_color = SHEET_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = SHEET_PADDING
	style.content_margin_right = SHEET_PADDING - 6.0  # the scrollbar has its own inset
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event
