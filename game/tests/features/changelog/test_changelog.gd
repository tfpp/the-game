extends GutTest
## Pure text handling for the changelog panel (features/changelog/changelog.gd), kept
## free of scene access so it's unit-testable.

const Changelog := preload("res://features/changelog/changelog.gd")
const ChangelogEntries := preload("res://features/changelog/entries.gd")


func test_entry_line_bolds_the_title_and_keeps_the_summary() -> void:
	var line := Changelog.entry_line({"title": "Frogs", "summary": "Frogs hop around."})
	assert_eq(line, "[b]Frogs[/b] — Frogs hop around.")


func test_entry_line_tolerates_missing_keys() -> void:
	assert_eq(Changelog.entry_line({}), "[b][/b] — ")


func test_body_text_joins_one_line_per_entry_in_order() -> void:
	var entries: Array[Dictionary] = [
		{"title": "A", "summary": "first"},
		{"title": "B", "summary": "second"},
	]
	assert_eq(Changelog.body_text(entries), "[b]A[/b] — first\n[b]B[/b] — second")


func test_body_text_of_an_empty_list_is_empty() -> void:
	assert_eq(Changelog.body_text([]), "")


func test_every_shipped_entry_has_a_title_and_summary() -> void:
	for entry: Dictionary in ChangelogEntries.ENTRIES:
		assert_false(str(entry.get("title", "")).is_empty(), "entry missing a title")
		assert_false(str(entry.get("summary", "")).is_empty(), "entry missing a summary")


func test_every_shipped_entry_title_is_unique() -> void:
	# releases.gd matches entries to releases by title.
	var seen := {}
	for entry: Dictionary in ChangelogEntries.ENTRIES:
		var title := str(entry.get("title", ""))
		assert_false(seen.has(title), "duplicate changelog title: " + title)
		seen[title] = true


func test_date_text_spells_the_month() -> void:
	assert_eq(Changelog.date_text("2026-09-28"), "Sep 28, 2026")
	assert_eq(Changelog.date_text("2027-01-05"), "Jan 5, 2027")
	assert_eq(Changelog.date_text("soon"), "soon")
	assert_eq(Changelog.date_text("2026-13-01"), "2026-13-01")


func test_releases_text_groups_entries_under_each_release() -> void:
	var entries: Array[Dictionary] = [
		{"title": "Boats", "summary": "Sail around."},
		{"title": "Hats", "summary": "Wear hats."},
		{"title": "Frogs", "summary": "Frogs hop around."},
	]
	var releases := [
		{"version": "edge", "titles": ["Boats"]},
		{"version": "0.7.0", "date": "2026-10-02", "titles": ["Hats", "Gone"]},
		{"version": "0.6.2", "date": "2026-09-28", "titles": []},
		{"version": "0.6.1", "date": "2026-09-28", "titles": ["Frogs"]},
	]
	var date := "  [color=#ffffff99]%s[/color]"
	assert_eq(
		Changelog.releases_text(releases, entries),
		(
			"\n"
			. join(
				[
					"[font_size=20][b]Edge[/b][/font_size]" + date % "not released yet",
					"[b]Boats[/b] — Sail around.",
					"",
					"[font_size=20][b]v0.7.0[/b][/font_size]" + date % "Oct 2, 2026",
					"[b]Hats[/b] — Wear hats.",
					# An entry renamed or removed since still shows its title.
					"[b]Gone[/b]",
					"",
					"[font_size=20][b]v0.6.2[/b][/font_size]" + date % "Sep 28, 2026",
					"Fixes and improvements.",
					"",
					"[font_size=20][b]v0.6.1[/b][/font_size]" + date % "Sep 28, 2026",
					"[b]Frogs[/b] — Frogs hop around.",
				]
			)
		)
	)


func test_releases_text_leaves_out_an_empty_edge() -> void:
	var releases := [
		{"version": "edge", "titles": []},
		{"version": "0.6.0", "date": "2026-09-28", "titles": []},
	]
	assert_eq(
		Changelog.releases_text(releases, []),
		(
			"[font_size=20][b]v0.6.0[/b][/font_size]  [color=#ffffff99]Sep 28, 2026[/color]\n"
			+ "Fixes and improvements."
		)
	)


func test_releases_text_skips_malformed_releases() -> void:
	assert_eq(Changelog.releases_text(["nope", 3], []), "")


func test_releases_are_absent_outside_release_exports() -> void:
	assert_eq(Changelog.load_releases(), [])


func test_registers_a_release_notes_link_in_the_esc_menu() -> void:
	var node := Changelog.new()
	add_child_autofree(node)
	assert_true(node.is_in_group(&"esc_menu_links"))
	assert_eq(node.esc_menu_label(), "Release notes")
	node.esc_menu_open()
	assert_true(node.is_in_group(&"modal_ui"))
