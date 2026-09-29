extends GutTest

const Commands := preload("res://features/console/commands.gd")
const GitCommands := preload("res://features/console/git_commands.gd")


func test_dispatch_reads_snapshot_and_completes() -> void:
	var commands := Commands.new(get_tree())
	commands.git_commands._loaded = true
	commands.git_commands._data = {
		"rev-parse HEAD": "abc123",
		"log": "abc123 Example commit",
		"show": "example.gd | 2 ++",
		"status": "No tracked changes at snapshot time.",
		"branch": "main",
		"ls-files": "game/features/console/commands.gd",
	}
	for command: String in GitCommands.COMMANDS:
		var result := commands.execute(command)
		assert_true(result.contains("Repository snapshot at abc123"), command)
		assert_false(result.contains("Unavailable"), command)
	assert_true(commands.execute("git log --oneline").contains("Example commit"))
	assert_true(commands.execute("git show --stat").contains("example.gd"))
	assert_true(commands.execute("help git").contains("Read-only"))
	assert_true(commands.execute("git help").contains("git log"))
	assert_true(commands.suggestions("git sh").has("git show"))
	assert_true(commands.suggestions("git rev").has("git rev-parse HEAD"))
	assert_true(commands.suggestions("git rev-parse h").has("git rev-parse HEAD"))


func test_rejects_writes_options_paths_and_shell_without_loading() -> void:
	var commands := GitCommands.new()
	for value: String in [
		"push",
		"fetch",
		"reset --hard",
		"checkout main",
		"clean -fd",
		"config --list",
		"-c alias.x=!id x",
		"log --output=/tmp/out",
		"show HEAD:.env",
		"show ../file",
		"status; id",
		"log | cat",
		"log\nstatus",
		"log $(id)",
		"ls-files -- /etc/passwd",
		"diff",
		"log -999999",
	]:
		assert_true(commands.execute(value).begins_with("Unsupported"), value)
	assert_false(commands._loaded)
	assert_true(commands.execute("").contains("git log"))
	assert_false(commands._loaded)


func test_unavailable_snapshot_is_explicit() -> void:
	var commands := GitCommands.new()
	commands._loaded = true
	assert_true(commands.execute("log").contains("unavailable"))


func test_native_checkout_generator() -> void:
	var commands := GitCommands.new()
	var result := commands.execute("log")
	assert_true(result.contains("Repository snapshot at"), result)
	assert_false(commands._data.get("rev-parse HEAD", "").is_empty())
	assert_true(commands.execute("ls-files").contains(".gitignore"))
