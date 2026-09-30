extends GutTest
## The pre-run hook's logger only excuses the listed, self-recovering engine warnings.

const KnownEngineWarnings := preload("res://tests/hooks/known_engine_warnings.gd")
const JOLT := "Jolt Physics job system exceeded the maximum number of jobs. Waiting..."


func _log(code: String, error_type: int) -> GutTrackedError:
	var tracker: GutErrorTracker = GutUtils.get_error_tracker()
	var error: GutTrackedError = tracker.add_error(
		"f", "file.cpp", 1, code, "", false, error_type, []
	)
	var backtraces: Array[ScriptBacktrace] = []
	KnownEngineWarnings.new()._log_error(
		"f", "file.cpp", 1, code, "", false, error_type, backtraces
	)
	return error


func test_known_warning_is_handled_and_others_still_fail() -> void:
	var known := _log(JOLT, Logger.ERROR_TYPE_WARNING)
	var other := _log("Some other engine warning", Logger.ERROR_TYPE_WARNING)
	var as_error := _log(JOLT, Logger.ERROR_TYPE_ERROR)
	assert_true(known.handled, "Known Jolt warning is excused")
	assert_false(other.handled, "Unlisted warnings still fail the test")
	assert_false(as_error.handled, "Only warnings are excused, not errors")
	other.handled = true
	as_error.handled = true


func test_pre_run_hook_is_configured() -> void:
	var config: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://.gutconfig.json")
	)
	assert_eq(config.get("pre_run_script"), "res://tests/hooks/pre_run.gd")
