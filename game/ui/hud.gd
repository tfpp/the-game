extends CanvasLayer
## Corner readouts: version (top left), players and connection (top right) and controls
## (bottom left). Styled with Kenney's UI Pack - Space Expansion. Desktop play uses
## pointer lock; touch and controller play can keep the pointer free.

const REFRESH_S := 0.25

var _refresh_in := 0.0

@onready var _release: Label = $Corners/Version/Line/Release
@onready var _commit: Label = $Corners/Version/Line/Commit
@onready var _count: Label = $Corners/Players/Lines/Count
@onready var _status: Label = $Corners/Players/Lines/Status


func _ready() -> void:
	_release.text = release_text(Network.game_version())
	# The hash sits in the body font: Kenney Future would uppercase it.
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
	$Corners/Keys.visible = not Controls.touch_visible()
	var pad := Controls.device == Controls.Device.GAMEPAD
	$Corners/Keys/Grid/Key0.text = "Left stick" if pad else "W A S D"
	$Corners/Keys/Grid/Key1.text = "A / Cross" if pad else "Space / Wheel"
	$Corners/Keys/Grid/Key2.text = "Right stick" if pad else "Mouse"
	$Corners/Keys/Grid/Key3.text = "Start" if pad else "Esc"
	_refresh_in -= delta
	if _refresh_in <= 0.0:
		_refresh_in = REFRESH_S
		_count.text = player_count_text(_player_count())
		_status.text = _connection_text()


## "v0.3.0", shown next to the build's short commit hash.
static func release_text(game_version: String) -> String:
	return "v" + game_version


static func player_count_text(count: int) -> String:
	return "%d player%s" % [count, "" if count == 1 else "s"]


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
