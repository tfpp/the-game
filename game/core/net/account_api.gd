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
	http.timeout = TIMEOUT_S
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	if has_session():
		headers.append("Authorization: Bearer " + session_token)
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		log_failure(method, path, "request not sent: %s (%d)" % [error_string(err), err])
		return _result(0, {}, "network", "Couldn't reach the accounts server")
	var response: Array = await http.request_completed
	http.queue_free()
	var outcome: int = response[0]
	var status: int = response[1]
	var raw: PackedByteArray = response[3]
	if outcome != HTTPRequest.RESULT_SUCCESS:
		log_failure(method, path, describe_outcome(outcome))
		return _result(0, {}, "network", "Couldn't reach the accounts server")
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
