extends Node
## Dedicated-server-only delivery. No Discord credential or chat history reaches clients.

const MAX_PENDING := 100
const MAX_ATTEMPTS := 3

var _url := ""
var _key := PackedByteArray()
var _configured := false
var _session := ""
var _sequence := 0
var _pending: Array[Dictionary] = []
var _sending := false


func enqueue(sender_name: String, text: String) -> void:
	if not multiplayer.is_server() or Network.mode != Network.Mode.SERVER:
		return
	if not _configured:
		_configure()
	if _url.is_empty() or _key.is_empty() or _pending.size() >= MAX_PENDING:
		return
	_sequence += 1
	_pending.append(
		{
			"id": "%s:%d" % [_session, _sequence],
			"timestamp": int(Time.get_unix_time_from_system()),
			"sender": sender_name.left(64),
			"text": text
		}
	)
	if not _sending:
		_drain()


func _configure() -> void:
	_configured = true
	# Environment holds only configuration paths/addresses, never secret values.
	var url := OS.get_environment("GAME_CHAT_BOT_URL").strip_edges()
	if url.is_empty():
		return
	if not url.begins_with("http://") and not url.begins_with("https://"):
		print("Game chat relay disabled: invalid bot URL")
		return
	var path := OS.get_environment("GAME_CHAT_KEY_FILE")
	if path.is_empty():
		path = "/run/secrets/game-chat-key"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("Game chat relay disabled: key unavailable")
		return
	var key := file.get_as_text().strip_edges().to_utf8_buffer()
	if key.size() < 32:
		print("Game chat relay disabled: key too short")
		return
	_url = url
	_key = key
	_session = Crypto.new().generate_random_bytes(16).hex_encode()


func _drain() -> void:
	_sending = true
	while not _pending.is_empty():
		var message: Dictionary = _pending[0]
		var body := JSON.stringify(message)
		var delivered := false
		for attempt: int in MAX_ATTEMPTS:
			if not multiplayer.is_server() or Network.mode != Network.Mode.SERVER:
				_pending.clear()
				_sending = false
				return
			var status: int = await _post(body)
			if status == 204:
				delivered = true
				break
			if status >= 400 and status < 500:
				break
			if attempt < MAX_ATTEMPTS - 1:
				await get_tree().create_timer(float(attempt + 1)).timeout
		_pending.pop_front()
		if not delivered:
			print("Game chat relay dropped a message after delivery failure")
	_sending = false


static func signature_for(body: String, key: PackedByteArray) -> String:
	return (
		Crypto
		. new()
		. hmac_digest(HashingContext.HASH_SHA256, key, ("game-chat-v1\n" + body).to_utf8_buffer())
		. hex_encode()
	)


func _post(body: String) -> int:
	var signature := signature_for(body, _key)
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.body_size_limit = 4096
	# Never forward a signed message to a redirected destination.
	request.max_redirects = 0
	add_child(request)
	var error := request.request(
		_url,
		["Content-Type: application/json", "X-Game-Chat-Signature: " + signature],
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		request.queue_free()
		return 0
	var response: Array = await request.request_completed
	request.queue_free()
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS:
		return 0
	return int(response[1])
