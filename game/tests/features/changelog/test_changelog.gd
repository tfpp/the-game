extends GutTest
## Pure text handling for the changelog panel (features/changelog/changelog.gd), kept
## free of scene access so it's unit-testable.

const Changelog := preload("res://features/changelog/changelog.gd")
const ChangelogEntries := preload("res://features/changelog/entries.gd")


func test_entry_line_is_a_bulleted_row_with_the_summary_under_the_title() -> void:
	var line := Changelog.entry_line({"title": "Frogs", "summary": "Frogs hop around."})
	assert_eq(
		line,
		(
			"[cell padding=0,1,10,0][color=#36bdf7]•[/color][/cell]"
			+ "[cell padding=0,0,0,10][color=#232838][font_size=19]Frogs[/font_size][/color]\n"
			+ "[color=#566074][font_size=16]Frogs hop around.[/font_size][/color][/cell]"
		)
	)


func test_entry_line_tolerates_missing_keys() -> void:
	assert_eq(
		Changelog.entry_line({}),
		(
			"[cell padding=0,1,10,0][color=#36bdf7]•[/color][/cell]"
			+ "[cell padding=0,0,0,10][color=#232838][font_size=19][/font_size][/color][/cell]"
		)
	)


func test_entry_line_uses_no_faux_bold() -> void:
	# The body's bold font is the heading font, so entries must not use [b].
	assert_false(Changelog.entry_line({"title": "A", "summary": "b"}).contains("[b]"))


func test_body_text_is_one_list_of_every_entry_in_order() -> void:
	var entries: Array[Dictionary] = [
		{"title": "A", "summary": "first"},
		{"title": "B", "summary": "second"},
	]
	assert_eq(
		Changelog.body_text(entries),
		(
			"[table=2]%s%s[/table]"
			% [Changelog.entry_line(entries[0]), Changelog.entry_line(entries[1])]
		)
	)


func test_body_text_of_an_empty_list_is_empty() -> void:
	assert_eq(Changelog.body_text([]), "")


func test_heading_text_uses_the_heading_font_and_a_muted_detail() -> void:
	assert_eq(
		Changelog.heading_text("v0.6.0", "#36bdf7", "Sep 28, 2026"),
		(
			"[b][font_size=24][color=#36bdf7]v0.6.0[/color][/font_size][/b]"
			+ "   [color=#566074][font_size=15]Sep 28, 2026[/font_size][/color]"
		)
	)
	assert_eq(
		Changelog.heading_text("x", "#000", ""),
		"[b][font_size=24][color=#000]x[/color][/font_size][/b]"
	)


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
		{"version": "edge", "commit": "90ccba1", "titles": ["Boats"]},
		{"version": "0.7.0", "date": "2026-10-02", "titles": ["Hats", "Gone"]},
		{"version": "0.6.2", "date": "2026-09-28", "titles": []},
		{"version": "0.6.1", "date": "2026-09-28", "titles": ["Frogs"]},
	]
	var edge := Changelog.EDGE_COLOR
	var release := Changelog.RELEASE_COLOR
	assert_eq(
		Changelog.releases_text(releases, entries),
		(
			Changelog
			. RELEASE_GAP
			. join(
				[
					(
						Changelog.heading_text("Edge", edge, "90ccba1")
						+ "\n"
						+ Changelog.entry_list([Changelog.entry_line(entries[0])])
					),
					(
						Changelog.heading_text("v0.7.0", release, "Oct 2, 2026")
						+ "\n"
						+ (
							Changelog
							. entry_list(
								[
									Changelog.entry_line(entries[1]),
									# An entry renamed or removed since still shows its title.
									Changelog.entry_line({"title": "Gone"}),
								]
							)
						)
					),
					(
						Changelog.heading_text("v0.6.2", release, "Sep 28, 2026")
						+ "\n"
						+ Changelog.entry_list(
							[Changelog.entry_line({"title": "Fixes and improvements"})]
						)
					),
					(
						Changelog.heading_text("v0.6.1", release, "Sep 28, 2026")
						+ "\n"
						+ Changelog.entry_list([Changelog.entry_line(entries[2])])
					),
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
			Changelog.heading_text("v0.6.0", Changelog.RELEASE_COLOR, "Sep 28, 2026")
			+ "\n"
			+ Changelog.entry_list([Changelog.entry_line({"title": "Fixes and improvements"})])
		)
	)


func test_releases_text_skips_malformed_releases() -> void:
	assert_eq(Changelog.releases_text(["nope", 3], []), "")


func test_releases_are_absent_outside_release_exports() -> void:
	assert_eq(Changelog.load_releases(), [])


func test_releases_from_puts_the_edge_first() -> void:
	var script := GDScript.new()
	script.source_code = (
		"extends RefCounted\n"
		+ 'const COMMIT := "90ccba1"\n'
		+ 'const EDGE: Array[String] = ["Boats"]\n'
		+ 'const RELEASES: Array[Dictionary] = [{"version": "0.6.0", "titles": ["Frogs"]}]\n'
	)
	assert_eq(script.reload(), OK)
	assert_eq(
		Changelog.releases_from(script),
		[
			{"version": "edge", "commit": "90ccba1", "titles": ["Boats"]},
			{"version": "0.6.0", "titles": ["Frogs"]},
		]
	)
	assert_eq(Changelog.releases_from(null), [])


func test_registers_a_release_notes_link_in_the_esc_menu() -> void:
	var node := Changelog.new()
	add_child_autofree(node)
	assert_true(node.is_in_group(&"esc_menu_links"))
	assert_eq(node.esc_menu_label(), "Release notes")
	node.esc_menu_open()
	assert_true(node.is_in_group(&"modal_ui"))
