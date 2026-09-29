extends RefCounted
## Read-only build metadata. Player input never becomes process arguments.

const SNAPSHOT_PATH := "res://features/console/repo_snapshot.gd"
const COMMANDS: Array[String] = [
	"git log",
	"git log --oneline",
	"git show",
	"git show --stat",
	"git status",
	"git branch",
	"git rev-parse HEAD",
	"git ls-files",
]
const USAGE := (
	"Read-only repository snapshot commands:\n"
	+ "git log [--oneline] (last 20 commits), git show [--stat] (HEAD summary),\n"
	+ "git status (tracked changes), git branch (current), git rev-parse HEAD, git ls-files.\n"
	+ "No other arguments, file contents, shell commands or writes are supported."
)

var _data: Dictionary = {}
var _loaded := false


func execute(value: String) -> String:
	if value.is_empty() or value == "help":
		return USAGE
	if not COMMANDS.has("git " + value):
		return "Unsupported Git command or arguments.\n" + USAGE
	_load_snapshot()
	if _data.is_empty():
		return "Repository snapshot unavailable. Export with game/scripts/export.sh."
	var key := value.replace(" --oneline", "").replace(" --stat", "")
	return (
		"Repository snapshot at %s (not a live working tree):\n%s"
		% [str(_data.get("rev-parse HEAD", "unknown")), str(_data.get(key, "Unavailable."))]
	)


func _load_snapshot() -> void:
	if _loaded:
		return
	_loaded = true
	if ResourceLoader.exists(SNAPSHOT_PATH):
		var resource := load(SNAPSHOT_PATH) as GDScript
		_data = resource.get("DATA")
	elif OS.has_feature("editor") and not OS.has_feature("web"):
		_data = preload("res://features/console/git_snapshot.gd").collect()
