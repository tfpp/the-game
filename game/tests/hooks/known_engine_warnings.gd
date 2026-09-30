extends Logger
## Marks known engine warnings that recover on their own as handled, so GUT does not fail
## the test that happened to be running. GUT's own logger records every engine warning
## first; this logger is registered after it and runs next.
##
## Keep the list short and specific. Only add warnings that come from the engine rather
## than the game and that the engine recovers from.

const HANDLED := [
	# Godot's Jolt job pool can briefly run out when physics frames run back to back, as
	# under `--fixed-fps`. The engine waits for a free job and carries on (WARN_PRINT_ONCE).
	"Jolt Physics job system exceeded the maximum number of jobs",
]


func _log_error(
	_function: String,
	_file: String,
	_line: int,
	code: String,
	rationale: String,
	_editor_notify: bool,
	error_type: int,
	_script_backtraces: Array[ScriptBacktrace]
) -> void:
	if error_type != ERROR_TYPE_WARNING or not _is_known(code + rationale):
		return
	for error: GutTrackedError in GutUtils.get_error_tracker().get_current_test_errors():
		if error.error_type == ERROR_TYPE_WARNING and _is_known(error.code + error.rationale):
			error.handled = true


static func _is_known(text: String) -> bool:
	for known: String in HANDLED:
		if text.contains(known):
			return true
	return false
