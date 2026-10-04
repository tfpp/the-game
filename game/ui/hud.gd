extends CanvasLayer
## Corner readouts: version (top left) and a compact VOICE / nearby-players plate (top
## right). The plate's first line lights up teal with who is talking (from
## features/voice_chat's `speaker_names()`); the second counts players within voice
## range, everyone connected and the connection state. Desktop play uses pointer lock;
## touch and controller play can keep the pointer free. Narrow screens hide the version.

const REFRESH_S := 0.25
## Positional voice is clearly audible inside this range (meters).
const NEARBY_RADIUS := 20.0
const VOICE_IDLE := Color(0.78, 0.68, 0.5, 0.8)
const VOICE_LIVE := Color(0.45, 0.82, 0.76, 1)

var _refresh_in := 0.0

@onready var _version: Control = $Corners/Version
@onready var _release: Label = $Corners/Version/Line/Release
@onready var _commit: Label = $Corners/Version/Line/Commit
@onready var _count: Label = $Corners/Players/Lines/Count
@onready var _status: Label = $Corners/Players/Lines/Status
@onready var _players: Control = $Corners/Players


func _ready() -> void:
	_release.text = release_text(Network.game_version())
	# The hash sits in the detail font, which reads better for hex.
	_commit.text = Network.short_version(Network.build_version)


func _input(event: InputEvent) -> void:
	# Leave the mouse alone while a menu (e.g. the login screen) is open.
	if get_tree().get_first_node_in_group(&"modal_ui"):
		return
	# Browsers only grant pointer lock inside a user-gesture handler, so capture on click.
	var click := event as InputEventMouseButton
	if (
		click
		and click.pressed
		and click.device != InputEvent.DEVICE_ID_EMULATION
		and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	):
		Controls.select_device(Controls.Device.KEYBOARD)
		Controls.start()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("release_mouse"):
		Controls.pause()
		Controls.menu_requested.emit()


func _process(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in > 0.0:
		return
	_refresh_in = REFRESH_S
	var voice := get_tree().get_first_node_in_group(&"voice_chat")
	var speakers: PackedStringArray = voice.speaker_names() if voice != null else []
	_count.text = voice_text(speakers)
	_count.add_theme_color_override(
		"font_color", VOICE_LIVE if not speakers.is_empty() else VOICE_IDLE
	)
	_status.text = status_text(_nearby_count(), _player_count(), _connection_text())
	var viewport := get_viewport().get_visible_rect().size
	var stretch := get_viewport().get_stretch_transform().get_scale().x
	var scale := HudLayout.hud_scale(stretch)
	_version.visible = not HudLayout.is_narrow(viewport, scale)
	# Grow from the top-right corner so the plate stays inside the screen.
	_players.pivot_offset = Vector2(_players.size.x, 0)
	_players.scale = Vector2.ONE * scale


## "v0.3.0", shown next to the build's short commit hash.
static func release_text(game_version: String) -> String:
	return "v" + game_version


static func player_count_text(count: int) -> String:
	return "%d player%s" % [count, "" if count == 1 else "s"]


## "VOICE", or "VOICE · You, Ana" while someone is talking; more than three speakers
## collapse to "+N" so the plate stays compact.
static func voice_text(speakers: PackedStringArray) -> String:
	if speakers.is_empty():
		return "VOICE"
	var shown := speakers.slice(0, 3)
	var more := speakers.size() - shown.size()
	return "VOICE · " + ", ".join(shown) + (" +%d" % more if more > 0 else "")


## "2 nearby · 5 players · online".
static func status_text(nearby: int, players: int, connection: String) -> String:
	return "%d nearby · %s · %s" % [nearby, player_count_text(players), connection]


## Other players within `radius` of `origin`.
static func count_nearby(origin: Vector3, others: Array[Vector3], radius: float) -> int:
	var count := 0
	for point: Vector3 in others:
		if point.distance_to(origin) <= radius:
			count += 1
	return count


func _nearby_count() -> int:
	var me := multiplayer.get_unique_id()
	var origin := Vector3.INF
	var others: Array[Vector3] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Node3D
		if player == null or node.is_queued_for_deletion():
			continue
		if node.get_multiplayer_authority() == me:
			origin = player.global_position
		else:
			others.append(player.global_position)
	return 0 if origin == Vector3.INF else count_nearby(origin, others, NEARBY_RADIUS)


func _player_count() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		if not node.is_queued_for_deletion():
			count += 1
	return count


func _connection_text() -> String:
	match Network.mode:
		Network.Mode.CLIENT:
			# The server shows up as a peer only once our join ticket is accepted.
			var joined := multiplayer.get_peers().has(MultiplayerPeer.TARGET_PEER_SERVER)
			return "online" if joined else "connecting…"
		Network.Mode.SERVER:
			return "server"
		_:
			return "offline"
