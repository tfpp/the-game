class_name GameAudio
extends Node
## Short cosmetic cues. Gameplay sends authority-only events; no sound is saved
## in replicated state, so late joiners never replay old shots or pickups.

signal sound_started(cue: StringName, positional: bool, at: Vector3)

const BUS := &"GameSFX"
const MAX_WORLD_VOICES := 24
const MAX_UI_VOICES := 4
const SHOT := preload("res://features/game_audio/audio/sci-fi-sounds/explosionCrunch_000.ogg")
const HEAVY_SHOT := preload("res://features/game_audio/audio/sci-fi-sounds/explosionCrunch_002.ogg")
const EXPLOSION := preload("res://features/game_audio/audio/sci-fi-sounds/explosionCrunch_004.ogg")
const IMPACT := preload("res://features/game_audio/audio/impact-sounds/impactGeneric_light_000.ogg")
const HIT := preload("res://features/game_audio/audio/impact-sounds/impactPunch_medium_000.ogg")
const OPEN := preload("res://features/game_audio/audio/interface-sounds/open_001.ogg")
const CLOSE := preload("res://features/game_audio/audio/interface-sounds/close_001.ogg")
const EQUIP := preload("res://features/game_audio/audio/interface-sounds/select_001.ogg")
const PICKUP := preload("res://features/game_audio/audio/interface-sounds/confirmation_001.ogg")
const DROP := preload("res://features/game_audio/audio/interface-sounds/drop_001.ogg")

const PROFILES := {
	&"pistol": [SHOT, -9.0, 1.8],
	&"smg": [SHOT, -12.0, 2.4],
	&"shotgun": [HEAVY_SHOT, -8.0, 1.5],
	&"awp": [HEAVY_SHOT, -7.0, 1.0],
	&"explosion": [EXPLOSION, -10.0, 1.0],
	&"impact": [IMPACT, -16.0, 1.0],
	&"hit": [HIT, -16.0, 1.0],
	&"open": [OPEN, -18.0, 1.0],
	&"close": [CLOSE, -18.0, 1.0],
	&"equip": [EQUIP, -16.0, 1.0],
	&"pickup": [PICKUP, -16.0, 1.0],
	&"drop": [DROP, -16.0, 1.0],
}

var _world := Node3D.new()
var _ui := Node.new()


func _ready() -> void:
	add_to_group(&"game_audio")
	add_child(_world)
	add_child(_ui)
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, BUS)
		AudioServer.add_bus_effect(index, AudioEffectLimiter.new())
	Network.mode_changed.connect(_clear)


static func play_at(source: Node, cue: StringName, at: Vector3) -> void:
	var audio := source.get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if audio != null:
		audio._play(cue, true, at)


static func play_ui(source: Node, cue: StringName) -> void:
	var audio := source.get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if audio != null:
		audio._play(cue, false, Vector3.ZERO)


func _play(cue: StringName, positional: bool, at: Vector3) -> void:
	if Network.mode == Network.Mode.SERVER:
		return
	var profile := _profile(cue)
	if profile.is_empty() or not at.is_finite():
		return
	if positional:
		_make_room(_world, MAX_WORLD_VOICES)
		var player := AudioStreamPlayer3D.new()
		player.stream = profile[0]
		player.volume_db = profile[1]
		player.pitch_scale = profile[2]
		player.bus = BUS
		player.unit_size = 6.0
		player.max_distance = 48.0
		player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_world.add_child(player)
		player.global_position = at
		player.finished.connect(player.queue_free)
		player.play()
	else:
		_make_room(_ui, MAX_UI_VOICES)
		var player := AudioStreamPlayer.new()
		player.stream = profile[0]
		player.volume_db = profile[1]
		player.pitch_scale = profile[2]
		player.bus = BUS
		_ui.add_child(player)
		player.finished.connect(player.queue_free)
		player.play()
	sound_started.emit(cue, positional, at)


func _make_room(parent: Node, limit: int) -> void:
	while parent.get_child_count() >= limit:
		var oldest := parent.get_child(0)
		parent.remove_child(oldest)
		oldest.queue_free()


func _clear(_mode: Network.Mode) -> void:
	_make_room(_world, 1)
	_make_room(_ui, 1)


func _profile(cue: StringName) -> Array:
	return PROFILES.get(cue, [])
