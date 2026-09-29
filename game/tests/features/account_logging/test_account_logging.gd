extends GutTest


func test_describes_timeouts_and_dns_failures() -> void:
	assert_string_contains(AccountApi.describe_outcome(HTTPRequest.RESULT_TIMEOUT), "timed out")
	assert_string_contains(AccountApi.describe_outcome(HTTPRequest.RESULT_CANT_RESOLVE), "DNS")
	assert_string_contains(AccountApi.describe_outcome(999), "unknown error")


func test_log_line_names_method_url_and_reason() -> void:
	var api := AccountApi.new("https://api.example/")
	var line := api.log_failure(HTTPClient.METHOD_POST, "/join-ticket", "HTTP 503")
	assert_eq(line, "[accounts] POST https://api.example/join-ticket failed: HTTP 503")
	api.free()


func test_missing_url_still_reports_no_api() -> void:
	var api := AccountApi.new("")
	add_child_autofree(api)
	var result: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/me")
	assert_eq(result["error"], "no_api")
