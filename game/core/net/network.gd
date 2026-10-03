extends Node
## Owns the MultiplayerPeer and decides how this process runs.
##
## Authority model:
## - Server (peer 1) is authoritative for everything: spawning, despawning,
##   spawn positions, and all game state added by features.
## - The one exception is player movement: each client is the multiplayer
##   authority of its own Player node, simulates Source movement locally, and
##   replicates it via MultiplayerSynchronizer.
##
## Modes (picked in `start_from_environment`):
##   dedicated server: `godot --headless -- --server [--port=7777]`
##   client:           `-- --connect=ws://host:7777`, or `?server=wss://...` on web
##   offline:          `-- --offline`, `?server=offline`, or no server configured;
##                     OfflineMultiplayerPeer, this process is the server
##
## Web builds with no `?server=` join `game/network/default_server_url`.
## Native builds default to offline so local development needs no backend.
##
## Joining needs a ticket from the accounts API (`api/`, `POST /join-ticket`), checked
## with SceneMultiplayer's auth handshake *before* the peer counts as connected, so an
## unauthenticated peer never sees `peer_connected`, RPCs or replication:
##   1. The client sends its ticket with `send_auth` and completes its side.
##   2. The server verifies it (JoinTicket plus a nonce replay check) and completes, or
##      sends "error:<reason>" and drops the peer. Silent peers time out.
## Server flags: `--ticket-key-file=PATH` (the key shared with the API), or
## `--dev-insecure-auth` for local tests, which also accepts "dev:<name>" tickets.
## Client flags: `--ticket=...`, or `--dev-insecure-auth [--name=Bob]`. Without either,
## joining waits for the login screen (`login_required`) to fetch a ticket.
##
## Version check: the client's auth message is {"version": <build>, "ticket": <ticket>},
## and the server turns away any build but its own ("error:version:<server build>")
## before looking at the ticket. Builds are the git commit CI exported them from
## (`scripts/export.sh` writes res://build_info.gd); local runs are "dev", and
## `--build-version=X` overrides it for testing.

signal mode_changed(mode: Mode)
signal connection_failed(reason: String)
## A server is configured but joining needs a ticket; the login UI handles it.
signal login_required(url: String)

enum Mode { OFFLINE, SERVER, CLIENT }

const DEFAULT_PORT := 7777
const DEFAULT_SERVER_SETTING := "game/network/default_server_url"
const DEFAULT_API_SETTING := "game/network/api_url"
const AUTH_TIMEOUT_S := 5.0
const DEV_TICKET_PREFIX := "dev:"
const AUTH_ERROR_PREFIX := "error:"
const VERSION_ERROR_PREFIX := "version:"
const BUILD_INFO_PATH := "res://build_info.gd"
const DEV_BUILD := "dev"

var mode := Mode.OFFLINE
## This build's version: a git commit SHA from CI, or "dev".
var build_version := DEV_BUILD
## User args after `--`, e.g. {"server": "", "port": "7777"}.
var args := {}
## Server URL waiting for a login (see `login_required`), or "".
var pending_url := ""

## Server: shared ticket key, or empty. `insecure_auth` also accepts "dev:" tickets.
var ticket_key := PackedByteArray()
var insecure_auth := false
## Server: authenticated peers, peer id -> {"account_id": int, "name": String}.
var peer_accounts := {}
## Client: the server's build when it refused ours, else "". Reloading fixes it on web.
var server_version_mismatch := ""
## Server: nonce -> expiry of tickets already used, to reject replays.
var _used_nonces := {}

## Client: ticket to present, and the reason the server gave if it refused us.
var _ticket := ""
var _auth_error := ""


func _enter_tree() -> void:
	args = _parse_user_args()
	# `--build-version=` pretends to be another build (tests of the version check).
	build_version = (
		str(args.get("build-version", "")) if args.get("build-version") else load_build_version()
	)


## Reads the version CI baked into res://build_info.gd, or "dev" if there is none.
static func load_build_version() -> String:
	if not ResourceLoader.exists(BUILD_INFO_PATH):
		return DEV_BUILD
	var script := load(BUILD_INFO_PATH) as GDScript
	var version := str(script.get_script_constant_map().get("VERSION", "")) if script else ""
	return version if version else DEV_BUILD


## The release version from project.godot (application/config/version), e.g. "0.3.0".
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## A version for display: the short commit hash, or "dev".
static func short_version(version: String) -> String:
	return version.left(7) if version != DEV_BUILD else version


## Whether a flag like `--debug-roster` was passed after `--`.
func has_flag(flag: String) -> bool:
	return args.has(flag)


## Pick a mode from command-line user args (after `--`) or the web page URL.
func start_from_environment() -> void:
	if args.has("server"):
		if start_server(int(args.get("port", str(DEFAULT_PORT)))) != OK:
			get_tree().quit(1)
		return
	var url := resolve_server_url()
	if url.is_empty():
		start_offline()
	elif args.has("ticket"):
		join(url, str(args["ticket"]))
	elif has_flag("dev-insecure-auth"):
		join(url, DEV_TICKET_PREFIX + str(args.get("name", "")))
	else:
		# Play offline behind the login screen until it fetches a ticket.
		start_offline()
		pending_url = url
		login_required.emit(url)


## Accounts API base URL (ends in /api). Precedence: --api=, ?api= (web), project default.
func resolve_api_url() -> String:
	var url: String = args.get("api", "")
	if url.is_empty():
		url = _web_query_param("api")
	if url.is_empty():
		url = str(ProjectSettings.get_setting(DEFAULT_API_SETTING, ""))
	return url.trim_suffix("/")


## Server URL to join, or "" for offline. Precedence: --offline, --connect=,
## ?server= (web), then the project default (web only).
func resolve_server_url() -> String:
	if args.has("offline"):
		return ""
	var url: String = args.get("connect", "")
	if url.is_empty() and OS.has_feature("web"):
		url = _web_query_param("server")
		if url.is_empty():
			url = str(ProjectSettings.get_setting(DEFAULT_SERVER_SETTING, ""))
	return "" if url == "offline" else url


func start_server(port: int) -> Error:
	insecure_auth = has_flag("dev-insecure-auth")
	if args.has("ticket-key-file"):
		ticket_key = JoinTicket.load_key(str(args["ticket-key-file"]))
		if ticket_key.is_empty():
			push_error("Ticket key file is missing or shorter than 32 bytes")
			return ERR_FILE_CANT_READ
	if ticket_key.is_empty() and not insecure_auth:
		push_error("Refusing to start: pass --ticket-key-file=PATH (or --dev-insecure-auth)")
		return ERR_UNCONFIGURED
	if insecure_auth:
		print("WARNING: --dev-insecure-auth: accepting unsigned dev tickets")
	var peer := create_transport()
	var err := peer.create_server(port)
	if err != OK:
		push_error("Failed to listen on port %d: %s" % [port, error_string(err)])
		return err
	var scene := _scene_multiplayer()
	scene.auth_timeout = AUTH_TIMEOUT_S
	scene.auth_callback = _on_server_auth
	multiplayer.multiplayer_peer = peer
	if not multiplayer.peer_disconnected.is_connected(_on_server_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_server_peer_disconnected)
	print("Server listening on port %d (build %s)" % [port, build_version])
	_set_mode(Mode.SERVER)
	return OK


## Connects to `url` and presents `ticket` (from the API, or "dev:<name>" for a
## --dev-insecure-auth server).
func join(url: String, ticket: String) -> Error:
	_ticket = ticket
	_auth_error = ""
	server_version_mismatch = ""
	pending_url = ""
	var peer := create_transport()
	var err := peer.create_client(url)
	if err != OK:
		connection_failed.emit(error_string(err))
		return err
	var scene := _scene_multiplayer()
	scene.auth_timeout = AUTH_TIMEOUT_S
	scene.auth_callback = _on_client_auth
	if not scene.peer_authenticating.is_connected(_on_client_authenticating):
		scene.peer_authenticating.connect(_on_client_authenticating)
		scene.peer_authentication_failed.connect(_on_client_authentication_failed)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.multiplayer_peer = peer
	print("Connecting to %s" % url)
	_set_mode(Mode.CLIENT)
	return OK


## Browser message callbacks can run between game frames. Allow bounded headroom
## for world snapshots and short frame stalls on both ends of the connection.
static func create_transport() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.inbound_buffer_size = 1024 * 1024
	peer.outbound_buffer_size = 1024 * 1024
	peer.max_queued_packets = 4096
	return peer


func start_offline() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_set_mode(Mode.OFFLINE)


## Display name of a connected peer (server side), or "" if unknown.
func peer_name(peer_id: int) -> String:
	return str((peer_accounts.get(peer_id, {}) as Dictionary).get("name", ""))


## Client: the auth message sent to the server.
func join_request(ticket: String) -> String:
	return JSON.stringify({"version": build_version, "ticket": ticket})


## Server: checks a client's auth message (see `join_request`). Returns
## {"account": {"account_id", "name"}} or {"error": <reason sent to the client>}.
## The version is checked first, so a mismatched client doesn't burn its ticket.
func check_join_request(message: String, peer_id: int, now: int) -> Dictionary:
	var json := JSON.new()
	# Clients older than the version check send a bare ticket, which isn't JSON.
	var request: Variant = json.data if json.parse(message) == OK else null
	var version: Variant = (request as Dictionary).get("version") if request is Dictionary else null
	if not version is String or version != build_version:
		return {"error": VERSION_ERROR_PREFIX + build_version}
	var account := authenticate_ticket(str((request as Dictionary).get("ticket", "")), peer_id, now)
	if account.is_empty():
		return {"error": "invalid or expired join ticket; sign in again"}
	return {"account": account}


## Server: checks a ticket and consumes its nonce. Returns {"account_id", "name"} or {}.
## Account id 0 means an unsigned dev ticket (only with --dev-insecure-auth).
func authenticate_ticket(ticket: String, peer_id: int, now: int) -> Dictionary:
	if not ticket_key.is_empty():
		var claims := JoinTicket.verify(ticket, ticket_key, now)
		if not claims.is_empty():
			_purge_nonces(now)
			var nonce: String = claims["nonce"]
			if _used_nonces.has(nonce):
				return {}
			_used_nonces[nonce] = claims["expires"]
			return {"account_id": claims["account_id"], "name": claims["name"]}
	if insecure_auth and ticket.begins_with(DEV_TICKET_PREFIX):
		var dev_name := _sanitize_name(ticket.trim_prefix(DEV_TICKET_PREFIX))
		return {"account_id": 0, "name": dev_name if dev_name else "dev%d" % peer_id}
	return {}


## True when this process runs server logic (dedicated server or offline).
func is_authoritative() -> bool:
	return multiplayer.is_server()


func _set_mode(new_mode: Mode) -> void:
	mode = new_mode
	mode_changed.emit(mode)


func _scene_multiplayer() -> SceneMultiplayer:
	return multiplayer as SceneMultiplayer


func _on_server_auth(peer_id: int, data: PackedByteArray) -> void:
	if peer_accounts.has(peer_id):
		return
	var now := int(Time.get_unix_time_from_system())
	var result := check_join_request(data.get_string_from_utf8(), peer_id, now)
	if result.has("error"):
		var reason: String = result["error"]
		if reason.begins_with(VERSION_ERROR_PREFIX):
			print("Peer %d rejected: client build doesn't match %s" % [peer_id, build_version])
		else:
			print("Peer %d rejected: invalid, expired or reused join ticket" % peer_id)
		_reject_peer(peer_id, reason)
		return
	var account: Dictionary = result["account"]
	var account_id: int = account["account_id"]
	if account_id != 0:
		# One connection per account: the newest one wins.
		for other: int in peer_accounts.keys():
			if (peer_accounts[other] as Dictionary)["account_id"] == account_id:
				print("Peer %d replaces peer %d for the same account" % [peer_id, other])
				_reject_peer(other, "signed in from somewhere else")
	peer_accounts[peer_id] = account
	print("Peer %d authenticated as %s" % [peer_id, account["name"]])
	_scene_multiplayer().complete_auth(peer_id)


## Drops a peer. One still authenticating is told why first (connected peers can't
## receive auth messages), with a short delay so the reason arrives before the close.
func _reject_peer(peer_id: int, reason: String) -> void:
	peer_accounts.erase(peer_id)
	var scene := _scene_multiplayer()
	if peer_id in scene.get_authenticating_peers():
		scene.send_auth(peer_id, (AUTH_ERROR_PREFIX + reason).to_utf8_buffer())
		await get_tree().create_timer(0.3).timeout
	if mode != Mode.SERVER:
		return
	if peer_id in scene.get_authenticating_peers() or peer_id in multiplayer.get_peers():
		scene.disconnect_peer(peer_id)


func _on_server_peer_disconnected(peer_id: int) -> void:
	peer_accounts.erase(peer_id)


func _purge_nonces(now: int) -> void:
	for nonce: String in _used_nonces.keys():
		if int(_used_nonces[nonce]) <= now:
			_used_nonces.erase(nonce)


func _sanitize_name(raw: String) -> String:
	var out := ""
	for c: String in raw.left(16):
		if (
			c == "_"
			or (c >= "0" and c <= "9")
			or (c >= "a" and c <= "z")
			or (c >= "A" and c <= "Z")
		):
			out += c
	return out


func _on_client_authenticating(peer_id: int) -> void:
	if peer_id != MultiplayerPeer.TARGET_PEER_SERVER:
		return
	var scene := _scene_multiplayer()
	scene.send_auth(peer_id, join_request(_ticket).to_utf8_buffer())
	scene.complete_auth(peer_id)


func _on_client_auth(_peer_id: int, data: PackedByteArray) -> void:
	var message := data.get_string_from_utf8()
	if not message.begins_with(AUTH_ERROR_PREFIX):
		return
	_auth_error = message.trim_prefix(AUTH_ERROR_PREFIX)
	if _auth_error.begins_with(VERSION_ERROR_PREFIX):
		server_version_mismatch = _auth_error.trim_prefix(VERSION_ERROR_PREFIX)
		_auth_error = (
			(
				"This game is version %s but the server runs %s. Reload the page to update; "
				% [short_version(build_version), short_version(server_version_mismatch)]
			)
			+ "if that doesn't help, the server is being updated, so try again in a few minutes."
		)


func _on_client_authentication_failed(_peer_id: int) -> void:
	_fail_client("Server didn't accept the connection")


func _on_connection_failed() -> void:
	_fail_client("Could not connect to server")


func _on_server_disconnected() -> void:
	_fail_client("Disconnected from server")


func _fail_client(fallback: String) -> void:
	if mode != Mode.CLIENT:
		return
	var reason := _auth_error if _auth_error else fallback
	_auth_error = ""
	print("Connection failed: %s" % reason)
	start_offline()
	connection_failed.emit(reason)


func _parse_user_args() -> Dictionary:
	var result := {}
	for arg: String in OS.get_cmdline_user_args():
		var trimmed := arg.trim_prefix("--")
		var parts := trimmed.split("=", true, 1)
		result[parts[0]] = parts[1] if parts.size() > 1 else ""
	return result


func _web_query_param(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var value: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get('%s') || ''" % key.c_escape()
	)
	return str(value) if value != null else ""
