extends GutTest

const Entries := preload("res://features/changelog/entries.gd")
const ROOT := "user://feature_notes_test"


func test_collects_independent_feature_files_in_stable_order_with_legacy_history() -> void:
	var first := ROOT.path_join("a/release_notes")
	var second := ROOT.path_join("b/release_notes")
	DirAccess.make_dir_recursive_absolute(first)
	DirAccess.make_dir_recursive_absolute(second)
	_write_note(second.path_join("2.json"), "Second", "Second summary.")
	_write_note(first.path_join("1.json"), "First", 'Quotes "and" Unicode: café.')
	var entries := Entries.all_entries(ROOT)
	assert_eq(entries.size(), Entries.ENTRIES.size() + 2)
	assert_eq(entries[0], {"title": "First", "summary": 'Quotes "and" Unicode: café.'})
	assert_eq(entries[1], {"title": "Second", "summary": "Second summary."})
	assert_eq(entries[2], Entries.ENTRIES[0])
	DirAccess.remove_absolute(first.path_join("1.json"))
	DirAccess.remove_absolute(second.path_join("2.json"))


func test_actual_feature_note_is_collected_once() -> void:
	var matches := 0
	for entry: Dictionary in Entries.all_entries():
		if entry["title"] == "Feature-owned release notes":
			matches += 1
	assert_eq(matches, 1)


func _write_note(path: String, title: String, summary: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"title": title, "summary": summary, "notes": [summary]}))
