class_name AccountApi
extends Node
## Client for the accounts API (`api/`): sign-in, display names and join tickets.
##
## The session token is a bearer token kept in localStorage on the web (the API is on
## another site, so no cookies) and in user:// on native builds. Every call resolves to
## {"ok": bool, "status": int, "data": Dictionary, "error": String, "message": String}.

const SESSION_KEY := "the-game.session"
const VERIFIER_KEY := "the-game.discord-verifier"
const NATIVE_STORE := "user://account.cfg"
const TIMEOUT_S := 15.0
## Longest single frame counted toward TIMEOUT_S. The web build is single-threaded, so
## the first frames (shader compiles on slow GPUs) can stall for many seconds while the
## browser has already received the response; those stalls must not expire a request.
const MAX_FRAME_S := 0.25

var base_url := ""
var session_token := ""


func _init(api_url: String = "") -> void:
	base_url = api_url.trim_suffix("/")
	session_token = load_value(SESSION_KEY)


func has_session() -> bool:
	return not session_token.is_empty()


func set_session(token: String) -> void:
	session_token = token
	save_value(SESSION_KEY, token)


func clear_session() -> void:
	session_token = ""
	save_value(SESSION_KEY, "")


## Sends a JSON request. `body` is serialized when not null.
func call_api(method: HTTPClient.Method, path: String, body: Variant = null) -> Dictionary:
	if base_url.is_empty():
		log_failure(method, path, "no accounts API URL is configured")
		return _result(0, {}, "no_api", "No accounts server is configured")
	var http := HTTPRequest.new()
	# HTTPRequest's own timeout counts raw frame time, so a long loading stall expires
	# it even when the server answered; `_await_response` keeps a clamped budget instead.
	http.timeout = 0.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if has_session():
		headers.append("Authorization: Bearer " + session_token)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return _network_failure(
			method,
			path,
			HTTPRequest.RESULT_CANT_CONNECT,
			"request not sent: %s (%d)" % [error_string(err), err]
		)
	var response: Array = await _await_response(http)
	http.queue_free()
	var outcome: int = response[0]
	var status: int = response[1]
	var raw: PackedByteArray = response[3]
	if outcome != HTTPRequest.RESULT_SUCCESS:
		return _network_failure(method, path, outcome)
	var data := {}
	if raw.size() > 0:
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			data = parsed
	if status == 401 and has_session():
		clear_session()
	if status >= 200 and status < 300:
		return _result(status, data, "", "")
	var message := str(data.get("message", "Request failed (%d)" % status))
	var snippet := raw.get_string_from_utf8().left(200).strip_edges()
	log_failure(method, path, "HTTP %d, response: %s" % [status, snippet if snippet else "(empty)"])
	return _result(status, data, str(data.get("error", "http_%d" % status)), message)


## Explains an HTTPRequest.Result code in words, for the console.
static func describe_outcome(outcome: int) -> String:
	var reasons := {
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: "chunked body size mismatch",
		HTTPRequest.RESULT_CANT_CONNECT: "can't connect (server down, wrong URL or blocked)",
		HTTPRequest.RESULT_CANT_RESOLVE: "can't resolve the host name (DNS)",
		HTTPRequest.RESULT_CONNECTION_ERROR: "connection error (dropped, or CORS on the web)",
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "TLS handshake failed (certificate problem)",
		HTTPRequest.RESULT_NO_RESPONSE: "no response from the server",
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "response body too large",
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED: "couldn't decompress the response",
		HTTPRequest.RESULT_REQUEST_FAILED: "request failed",
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN: "can't open the download file",
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR: "can't write the download file",
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "too many redirects",
		HTTPRequest.RESULT_TIMEOUT: "timed out after %d s" % int(TIMEOUT_S),
	}
	return "%s (HTTPRequest result %d)" % [reasons.get(outcome, "unknown error"), outcome]


## Prints why an accounts call failed. Never includes the request body or session token.
func log_failure(method: HTTPClient.Method, path: String, reason: String) -> String:
	var methods := ["GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS", "TRACE", "CONNECT", "PATCH"]
	var url := (base_url if base_url else "<no API URL>") + path
	var line := "[accounts] %s %s failed: %s" % [methods[method], url, reason]
	push_warning(line)
	printerr(line)
	return line


func sign_up(email: String, password: String, display_name: String) -> Dictionary:
	var body := {"email": email, "password": password, "display_name": display_name}
	return await call_api(HTTPClient.METHOD_POST, "/auth/signup", body)


func log_in(email: String, password: String) -> Dictionary:
	var body := {"email": email, "password": password}
	return _keep_session(await call_api(HTTPClient.METHOD_POST, "/auth/login", body))


func verify_email(token: String) -> Dictionary:
	var body := {"token": token}
	return _keep_session(await call_api(HTTPClient.METHOD_POST, "/auth/verify-email", body))


func request_reset(email: String) -> Dictionary:
	var body := {"email": email}
	return await call_api(HTTPClient.METHOD_POST, "/auth/password-reset/request", body)


func confirm_reset(token: String, password: String) -> Dictionary:
	var body := {"token": token, "password": password}
	var path := "/auth/password-reset/confirm"
	return _keep_session(await call_api(HTTPClient.METHOD_POST, path, body))


func log_out() -> void:
	if has_session():
		await call_api(HTTPClient.METHOD_POST, "/auth/logout")
	clear_session()


func me() -> Dictionary:
	return await call_api(HTTPClient.METHOD_GET, "/me")


func set_display_name(display_name: String) -> Dictionary:
	var body := {"display_name": display_name}
	return await call_api(HTTPClient.METHOD_PUT, "/me/display-name", body)


func join_ticket() -> Dictionary:
	return await call_api(HTTPClient.METHOD_POST, "/join-ticket")


## Starts Discord sign-in (or linking, with `link`). Keeps a random verifier locally
## and sends only its hash, so only this browser can redeem the code Discord leads to.
## On success, data["url"] is the Discord page to open.
func start_discord(link: bool) -> Dictionary:
	var verifier := Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32))
	save_value(VERIFIER_KEY, verifier)
	var body := {"code_challenge": verifier.sha256_text(), "link": link}
	return await call_api(HTTPClient.METHOD_POST, "/auth/discord/start", body)


func finish_discord(code: String) -> Dictionary:
	var verifier := load_value(VERIFIER_KEY)
	save_value(VERIFIER_KEY, "")
	var body := {"code": code, "code_verifier": verifier}
	return _keep_session(await call_api(HTTPClient.METHOD_POST, "/auth/discord/exchange", body))


## Waits for `http` to finish, giving up after TIMEOUT_S of frame time where each frame
## counts at most MAX_FRAME_S. Resolves to the `request_completed` arguments.
func _await_response(http: HTTPRequest) -> Array:
	var response: Array = []
	http.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			response.append_array([result, code, headers, body])
	)
	var waited := 0.0
	while response.is_empty():
		await get_tree().process_frame
		if not response.is_empty():
			break
		waited += counted_frame_time(get_process_delta_time())
		if waited >= TIMEOUT_S:
			http.cancel_request()
			return [HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray()]
	return response


## How much of one frame's `delta` counts toward TIMEOUT_S.
static func counted_frame_time(delta: float) -> float:
	return clampf(delta, 0.0, MAX_FRAME_S)


## The player-facing message for a failed HTTPRequest `result`, naming the failure so
## reports say whether it was DNS, TLS, a timeout or a dropped connection.
static func network_failure_message(result: int) -> String:
	var reason := ""
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE:
			reason = "DNS lookup failed"
		HTTPRequest.RESULT_CANT_CONNECT:
			reason = "couldn't connect"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			reason = "TLS handshake failed"
		HTTPRequest.RESULT_TIMEOUT:
			reason = "timed out"
		HTTPRequest.RESULT_NO_RESPONSE, HTTPRequest.RESULT_CONNECTION_ERROR:
			reason = "connection dropped"
		_:
			reason = "error %d" % result
	return "Couldn't reach the accounts server (%s)" % reason


func _network_failure(
	method: HTTPClient.Method, path: String, result: int, reason: String = ""
) -> Dictionary:
	var message := network_failure_message(result)
	log_failure(method, path, reason if not reason.is_empty() else describe_outcome(result))
	return _result(0, {}, "network", message)


static func _method_name(method: HTTPClient.Method) -> String:
	match method:
		HTTPClient.METHOD_GET:
			return "GET"
		HTTPClient.METHOD_POST:
			return "POST"
		HTTPClient.METHOD_PUT:
			return "PUT"
	return "HTTP"


func _keep_session(result: Dictionary) -> Dictionary:
	if result["ok"]:
		set_session(str((result["data"] as Dictionary).get("token", "")))
	return result


func _result(status: int, data: Dictionary, error: String, message: String) -> Dictionary:
	return {
		"ok": error.is_empty(), "status": status, "data": data, "error": error, "message": message
	}


## Small persistent key/value store: localStorage on the web, a ConfigFile natively.
static func load_value(key: String) -> String:
	if OS.has_feature("web"):
		var value: Variant = JavaScriptBridge.eval(
			"window.localStorage.getItem(%s) || ''" % JSON.stringify(key)
		)
		return str(value) if value != null else ""
	var config := ConfigFile.new()
	if config.load(NATIVE_STORE) != OK:
		return ""
	return str(config.get_value("account", key, ""))


static func save_value(key: String, value: String) -> void:
	if OS.has_feature("web"):
		if value.is_empty():
			JavaScriptBridge.eval("window.localStorage.removeItem(%s)" % JSON.stringify(key))
		else:
			JavaScriptBridge.eval(
				"window.localStorage.setItem(%s, %s)" % [JSON.stringify(key), JSON.stringify(value)]
			)
		return
	var config := ConfigFile.new()
	config.load(NATIVE_STORE)
	config.set_value("account", key, value)
	config.save(NATIVE_STORE)
