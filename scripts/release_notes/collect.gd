extends SceneTree
## Standalone native collector. No game autoloads, imports or additional interpreter.

const LEGACY := "game/features/changelog/entries.gd"

var _root := ""
var _failed := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("usage: feature_notes.sh titles|edge|validate [REV]")
		quit(1)
		return
	_root = args[0]
	var mode := args[2]
	var rev := args[3] if args.size() > 3 else "WORKTREE"
	var titles := _titles(rev)
	var output: Array[String] = []
	match mode:
		"titles":
			for title: String in titles:
				var escaped := JSON.stringify(title)
				output.append(escaped.substr(1, escaped.length() - 2))
		"edge", "validate":
			var notes := _edge(rev)
			if mode == "validate":
				output.append("Feature release notes are valid.")
			elif not notes.is_empty():
				output.append(notes)
		_:
			_fail("usage: feature_notes.sh titles|edge|validate [REV]")
	if not _failed:
		var file := FileAccess.open(args[1], FileAccess.WRITE)
		if file == null:
			_fail("Cannot write collected release notes")
		elif not output.is_empty():
			file.store_string("\n".join(output) + "\n")
	quit(1 if _failed else 0)


func _fail(message: String) -> void:
	printerr(message)
	_failed = true


func _git(args: Array[String], allow_failure: bool = false) -> Dictionary:
	var output: Array = []
	var command: Array[String] = ["-C", _root]
	command.append_array(args)
	var code := OS.execute("git", command, output, true)
	var content := str(output[0]) if not output.is_empty() else ""
	if code != 0 and not allow_failure:
		_fail("git failed: " + content.strip_edges())
	return {"code": code, "content": content}


func _read(path: String, rev: String) -> String:
	if rev == "WORKTREE":
		var absolute := _root.path_join(path)
		return FileAccess.get_file_as_string(absolute) if FileAccess.file_exists(absolute) else ""
	var result := _git(["show", rev + ":" + path], true)
	if result["code"] != 0:
		_git(["rev-parse", "--verify", rev])
		return ""
	return str(result["content"])


func _paths(rev: String) -> Array[String]:
	var paths: Array[String] = []
	if rev == "WORKTREE":
		var root := _root.path_join("game/features")
		if not DirAccess.dir_exists_absolute(root):
			return paths
		for feature: String in DirAccess.get_directories_at(root):
			var folder := root.path_join(feature).path_join("release_notes")
			if not DirAccess.dir_exists_absolute(folder):
				continue
			for file: String in DirAccess.get_files_at(folder):
				paths.append("game/features/" + feature + "/release_notes/" + file)
	else:
		var result := _git(["ls-tree", "-r", "--name-only", rev])
		paths.assign(str(result["content"]).split("\n", false))
	var pattern := RegEx.create_from_string("^game/features/[^/]+/release_notes/[^/]+\\.json$")
	var notes: Array[String] = []
	for path: String in paths:
		if pattern.search(path) != null:
			notes.append(path)
	notes.sort()
	return notes


func _single_line(value: Variant) -> bool:
	return (
		value is String
		and not str(value).strip_edges().is_empty()
		and not str(value).contains("\n")
		and not str(value).contains("\r")
	)


func _fragments(rev: String) -> Dictionary:
	var notes := {}
	for path: String in _paths(rev):
		var parser := JSON.new()
		if parser.parse(_read(path, rev)) != OK:
			_fail(path + ": " + parser.get_error_message())
			continue
		var note: Variant = parser.data
		if not note is Dictionary or not _valid_note(note, path):
			_fail(path + ": expected title, summary and notes fields")
			continue
		notes[path] = note
	return notes


func _valid_note(note: Dictionary, path: String) -> bool:
	for key: Variant in note:
		if key not in ["title", "summary", "notes"]:
			return false
	for key: String in ["title", "summary"]:
		if not _single_line(note.get(key)):
			_fail(path + ": " + key + " must be a nonempty single-line string")
			return false
	var bullets: Variant = note.get("notes")
	if not bullets is Array or bullets.is_empty():
		return false
	for bullet: Variant in bullets:
		if (
			not _single_line(bullet)
			or str(bullet).begins_with("- ")
			or str(bullet).begins_with("* ")
		):
			_fail(path + ": notes must be single-line strings without bullet prefixes")
			return false
	return true


func _titles(rev: String) -> Array[String]:
	var titles: Array[String] = []
	for note: Dictionary in _fragments(rev).values():
		titles.append(str(note["title"]))
	var pattern := RegEx.create_from_string('(?m)^\\s*"title":\\s*"((?:[^"\\\\]|\\\\.)*)",?\\s*$')
	for found: RegExMatch in pattern.search_all(_read(LEGACY, rev)):
		var parser := JSON.new()
		if parser.parse('"' + found.get_string(1) + '"') != OK:
			_fail("Invalid legacy title at " + rev)
		else:
			titles.append(str(parser.data))
	var seen := {}
	for title: String in titles:
		if seen.has(title):
			_fail("duplicate release-note title: " + title)
		seen[title] = true
	return titles


func _latest_tag(rev: String) -> String:
	var commit := "HEAD" if rev == "WORKTREE" else rev
	if rev == "WORKTREE" and _git(["rev-parse", "--verify", commit], true)["code"] != 0:
		return ""
	var result := _git(
		["tag", "--merged", commit, "--list", "v[0-9]*.[0-9]*.[0-9]*", "--sort=-v:refname"]
	)
	return str(result["content"]).get_slice("\n", 0).strip_edges()


func _edge(rev: String) -> String:
	var tag := _latest_tag(rev)
	var old := _fragments(tag) if not tag.is_empty() else {}
	var notes := _fragments(rev)
	for path: String in old:
		if not notes.has(path) or notes[path] != old[path]:
			_fail(path + ": released notes are immutable; add a new file")
	var pattern := RegEx.create_from_string("(?ms)^## \\[edge\\][ \\t]*\\r?\\n(.*?)(?=^## |\\z)")
	var section := pattern.search(_read("CHANGELOG.md", rev))
	var lines: Array[String] = []
	if section != null and not section.get_string(1).strip_edges().is_empty():
		lines.append(section.get_string(1).strip_edges())
	for path: String in notes:
		if not old.has(path):
			for bullet: String in notes[path]["notes"]:
				lines.append("- " + bullet)
	return "\n".join(lines)
