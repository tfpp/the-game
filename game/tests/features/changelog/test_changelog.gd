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


func test_registers_a_release_notes_link_in_the_esc_menu() -> void:
	var node := Changelog.new()
	add_child_autofree(node)
	assert_true(node.is_in_group(&"esc_menu_links"))
	assert_eq(node.esc_menu_label(), "Release notes")
	node.esc_menu_open()
	assert_true(node.is_in_group(&"modal_ui"))
