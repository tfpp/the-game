extends GutTest

const Snapshot := preload("res://features/console/git_snapshot.gd")
var _root := ""


func before_each() -> void:
	_root = ProjectSettings.globalize_path(
		"user://snapshot-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	DirAccess.make_dir_recursive_absolute(_root)


func after_each() -> void:
	_remove_fixture(_root)


func _remove_fixture(path: String) -> void:
	assert(path == _root or path.begins_with(_root + "/"))
	var dir := DirAccess.open(path)
	for folder: String in dir.get_directories():
		_remove_fixture(path.path_join(folder))
	for file: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func _git(arguments: PackedStringArray) -> String:
	var args := PackedStringArray(["-C", _root])
	args.append_array(arguments)
	var output: Array = []
	assert_eq(OS.execute("git", args, output, true), OK)
	return str(output[0]).strip_edges() if not output.is_empty() else ""


func _write(name: String, text: String) -> void:
	var file := FileAccess.open(_root.path_join(name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_metadata_excludes_contents_and_untracked_files_without_changing_repository() -> void:
	_git(["init", "-q"])
	_write("example.txt", "private content not for console\n")
	_git(["add", "example.txt"])
	_git(
		[
			"-c",
			"user.name=Test",
			"-c",
			"user.email=test@example.invalid",
			"commit",
			"-qm",
			"Example subject"
		]
	)
	var before := _git(["rev-parse", "HEAD"])
	_write("example.txt", "modified content\n")
	_write("untracked.txt", "untracked content\n")
	var data := Snapshot.collect(_root)
	assert_eq(data["rev-parse HEAD"], before)
	assert_true(data["log"].contains("Example subject"))
	assert_true(data["show"].contains("example.txt"))
	assert_true(data["status"].contains("M example.txt"))
	assert_eq(data["ls-files"], "example.txt")
	assert_false(str(data).contains("content"))
	assert_false(str(data).contains("untracked.txt"))
	# Container exports can read a checkout owned by the host user. Trust only
	# this explicit repository, without relying on checkout's temporary HOME.
	var had_owner_override := OS.has_environment("GIT_TEST_ASSUME_DIFFERENT_OWNER")
	var owner_override := OS.get_environment("GIT_TEST_ASSUME_DIFFERENT_OWNER")
	OS.set_environment("GIT_TEST_ASSUME_DIFFERENT_OWNER", "1")
	var container_data := Snapshot.collect(_root)
	if had_owner_override:
		OS.set_environment("GIT_TEST_ASSUME_DIFFERENT_OWNER", owner_override)
	else:
		OS.unset_environment("GIT_TEST_ASSUME_DIFFERENT_OWNER")
	assert_eq(container_data, data, "Container ownership does not hide the snapshot")
	assert_eq(_git(["rev-parse", "HEAD"]), before)
	assert_eq(FileAccess.get_file_as_string(_root.path_join("example.txt")), "modified content\n")
	_git(["checkout", "--detach", "-q"])
	assert_eq(Snapshot.collect(_root)["branch"], "(detached HEAD)")


func test_missing_repository_returns_no_snapshot() -> void:
	var failure := {}
	assert_eq(Snapshot.collect(_root, failure), {})
	assert_true(str(failure.get("message", "")).contains("git log failed"))
