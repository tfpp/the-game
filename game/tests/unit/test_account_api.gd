extends GutTest
## AccountApi request timing and failure messages.


func test_long_frames_count_only_up_to_the_cap() -> void:
	assert_eq(AccountApi.counted_frame_time(20.0), AccountApi.MAX_FRAME_S)
	assert_eq(AccountApi.counted_frame_time(0.016), 0.016)
	assert_eq(AccountApi.counted_frame_time(-1.0), 0.0)


func test_a_startup_stall_cannot_use_up_the_timeout() -> void:
	# A dozen 20 s frames (e.g. slow WebGL shader compiles) still leave most of the budget.
	var waited := 0.0
	for i in 12:
		waited += AccountApi.counted_frame_time(20.0)
	assert_lt(waited, AccountApi.TIMEOUT_S)


func test_failure_messages_name_the_cause() -> void:
	var cases := {
		HTTPRequest.RESULT_CANT_RESOLVE: "DNS lookup failed",
		HTTPRequest.RESULT_CANT_CONNECT: "couldn't connect",
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS handshake failed",
		HTTPRequest.RESULT_TIMEOUT: "timed out",
		HTTPRequest.RESULT_CONNECTION_ERROR: "connection dropped",
	}
	for result: int in cases:
		var message := AccountApi.network_failure_message(result)
		assert_string_starts_with(message, "Couldn't reach the accounts server")
		assert_string_contains(message, cases[result])


func test_await_response_returns_the_completed_request() -> void:
	var api := AccountApi.new("http://127.0.0.1:1")
	add_child_autofree(api)
	var http := HTTPRequest.new()
	api.add_child(http)
	var body := "{}".to_utf8_buffer()
	var complete := func() -> void:
		http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), body)
	complete.call_deferred()
	var response: Array = await api._await_response(http)
	assert_eq(response[0], HTTPRequest.RESULT_SUCCESS)
	assert_eq(response[1], 200)
	assert_eq(response[3], body)


func test_unreachable_server_reports_a_network_error() -> void:
	var api := AccountApi.new("http://127.0.0.1:1")
	add_child_autofree(api)
	var result: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/health")
	assert_false(result["ok"])
	assert_eq(result["error"], "network")
	assert_string_starts_with(result["message"], "Couldn't reach the accounts server (")
