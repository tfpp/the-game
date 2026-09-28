extends Node
## Kenney UI Pack sounds for every menu button: a click on press, a switch for toggles
## (check buttons, presets, backpack slots) and a quiet tap on mouse hover. Buttons are
## hooked as they enter the tree, so features get sounds without doing anything.
## Asset paths stay literal so `scripts/unused_assets.gd` sees them.
## Plays on the GameSFX bus, so Settings > Audio's "Sound effects" volume applies.

signal played(cue: StringName)

## cue -> [stream, volume_db]
const CUES := {
	&"click": [preload("res://assets/kenney/ui/Sounds/click-a.ogg"), -12.0],
	&"switch": [preload("res://assets/kenney/ui/Sounds/switch-a.ogg"), -12.0],
	&"hover": [preload("res://assets/kenney/ui/Sounds/tap-a.ogg"), -24.0],
}
const BUS := &"GameSFX"
const MAX_VOICES := 4
## Buttons that opt out (e.g. ones that play their own cue) set this meta to true.
const MUTE_META := &"ui_sounds_mute"


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for button: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		_hook(button as BaseButton)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook(node as BaseButton)


func _hook(button: BaseButton) -> void:
	if button.pressed.is_connected(_on_pressed):
		return
	button.pressed.connect(_on_pressed.bind(button))
	button.mouse_entered.connect(_on_hovered.bind(button))


func _on_pressed(button: BaseButton) -> void:
	if not button.get_meta(MUTE_META, false):
		play(&"switch" if button.toggle_mode else &"click")


func _on_hovered(button: BaseButton) -> void:
	if not button.disabled and not button.get_meta(MUTE_META, false):
		play(&"hover")


func play(cue: StringName) -> void:
	if Network.mode == Network.Mode.SERVER or not CUES.has(cue):
		return
	while get_child_count() >= MAX_VOICES:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var player := AudioStreamPlayer.new()
	player.stream = CUES[cue][0]
	player.volume_db = CUES[cue][1]
	if AudioServer.get_bus_index(BUS) >= 0:
		player.bus = BUS
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	played.emit(cue)
