extends RefCounted
## Fixed metadata queries only; player input never becomes process arguments.

const QUERIES := {
	"log": ["log", "-20", "--format=%h %s"],
	"show":
	[
		"show",
		"--format=%h %s",
		"--stat",
		"--no-ext-diff",
		"--no-textconv",
		"--no-renames",
		"HEAD",
		"--"
	],
	"status": ["status", "--short", "--untracked-files=no"],
	"branch": ["branch", "--show-current"],
	"rev-parse HEAD": ["rev-parse", "HEAD"],
	"ls-files": ["ls-files"],
}
const LIMIT := 12000


static func collect(root: String = "", failure: Dictionary = {}) -> Dictionary:
	if root.is_empty():
		root = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var data := {}
	for name: String in QUERIES:
		var args := PackedStringArray(
			[
				"--no-pager",
				"--no-optional-locks",
				"-c",
				"core.fsmonitor=false",
				"-c",
				"color.ui=false",
				"-c",
				"safe.directory=" + root,
				"-C",
				root
			]
		)
		args.append_array(PackedStringArray(QUERIES[name]))
		var output: Array = []
		var status := OS.execute("git", args, output, true)
		if status != OK:
			failure["message"] = "git %s failed (%d): %s" % [name, status, str(output)]
			return {}
		# Clean status and a detached branch legitimately produce no output.
		var value := str(output[0]).strip_edges() if not output.is_empty() else ""
		if value.length() > LIMIT:
			value = value.left(LIMIT) + "\n[Output truncated to 12000 characters.]"
		data[name] = value
	if data["status"].is_empty():
		data["status"] = "No tracked changes at snapshot time."
	if data["branch"].is_empty():
		data["branch"] = "(detached HEAD)"
	return data
