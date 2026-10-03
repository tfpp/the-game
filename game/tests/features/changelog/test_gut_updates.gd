extends GutTest

const UpdateDetector := preload("res://addons/gut/update_detector.gd")


func test_remote_fetch_completes_without_http_request() -> void:
	# Outside the tree there is no HTTPRequest: a real fetch would error here.
	var detector: Node = UpdateDetector.new()
	autofree(detector)
	watch_signals(detector)
	assert_eq(detector.fetch_remote_file(), OK)
	assert_signal_not_emitted(detector, "download_completed")
	await detector.download_completed
	assert_signal_emitted(detector, "download_completed")
	assert_null(detector._http_request)
	assert_true(detector.remote_data.data_issues.is_empty())
	# Leave the signal emission stack before GUT frees the detector.
	await wait_process_frames(1)


func test_forced_update_check_finishes_and_loads_local_metadata() -> void:
	var detector: Node = UpdateDetector.new()
	autofree(detector)
	watch_signals(detector)
	await detector.check_for_update_with_fetch(true)
	assert_false(detector.local_data.is_empty())
	assert_null(detector._http_request)
	assert_signal_emitted(detector, "download_completed")
	await wait_process_frames(2)
	assert_signal_emitted(detector, "updated")


func test_local_compatibility_rules_remain_available() -> void:
	var detector: Node = UpdateDetector.new()
	autofree(detector)
	detector.check_for_update()
	assert_false(detector.local_data.is_empty())
	assert_true(detector.local_data.is_gut_version_valid("9.7.1", "4.7.0"))
	assert_false(detector.local_data.is_gut_version_valid("9.7.1", "4.0.0"))
	assert_false(detector.local_data.is_gut_version_valid("0.0.0", "4.7.0"))
	assert_ne(detector.get_gut_version_for_godot_version("4.7.0"), "0.0.0")
