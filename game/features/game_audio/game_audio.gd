class_name GameAudio
extends Node
## Short cosmetic cues. Gameplay sends authority-only events; no sound is saved
## in replicated state, so late joiners never replay old shots or pickups.

signal sound_started(cue: StringName, positional: bool, at: Vector3)

const BUS := &"GameSFX"
const MAX_WORLD_VOICES := 24
const MAX_UI_VOICES := 4
const PISTOL_SHOT := preload("res://assets/game_audio/audio/pistol_shot.wav")
const MP5_SHOT := preload("res://assets/game_audio/audio/mp5_shot.wav")
const M4A4_SHOT := preload("res://assets/game_audio/audio/m4a4_shot.wav")
const AK47_SHOT := preload("res://assets/game_audio/audio/ak47_shot.wav")
const SHOTGUN_SHOT := preload("res://assets/game_audio/audio/shotgun_shot.wav")
const AWP_SHOT := preload("res://assets/game_audio/audio/awp_shot.wav")
const RELOAD_MAG_OUT := preload("res://assets/game_audio/audio/reload_mag_out.wav")
const RELOAD_MAG_IN := preload("res://assets/game_audio/audio/reload_mag_in.wav")
const RELOAD_CHARGE := preload("res://assets/game_audio/audio/reload_charge.wav")
const EXPLOSION := preload("res://assets/game_audio/audio/sci-fi-sounds/explosionCrunch_004.ogg")
const IMPACT := preload("res://assets/game_audio/audio/impact-sounds/impactGeneric_light_000.ogg")
const HIT := preload("res://assets/game_audio/audio/impact-sounds/impactPunch_medium_000.ogg")
const OPEN := preload("res://assets/game_audio/audio/interface-sounds/open_001.ogg")
const CLOSE := preload("res://assets/game_audio/audio/interface-sounds/close_001.ogg")
const EQUIP := preload("res://assets/game_audio/audio/interface-sounds/select_001.ogg")
const PICKUP := preload("res://assets/game_audio/audio/interface-sounds/confirmation_001.ogg")
const DROP := preload("res://assets/game_audio/audio/interface-sounds/drop_001.ogg")
const DOOR_OPEN := preload("res://assets/game_audio/audio/rpg-audio/doorOpen_1.ogg")
const DOOR_CLOSE := preload("res://assets/game_audio/audio/rpg-audio/doorClose_2.ogg")
const DOOR_LOCKED := preload("res://assets/game_audio/audio/rpg-audio/metalLatch.ogg")
const DOOR_UNLOCK := preload("res://assets/game_audio/audio/rpg-audio/metalClick.ogg")
const KEY_PICKUP := preload("res://assets/game_audio/audio/rpg-audio/handleCoins2.ogg")

const VAN_DEPARTURE := preload("res://assets/starter_room/van_departure.wav")

const WOK_YELL := preload("res://assets/strip_mall/audio/wok_yell.wav")
const SUSHI_YELL := preload("res://assets/strip_mall/audio/sushi_yell.wav")

const PROFILES := {
	&"city_wok_yell": [WOK_YELL, -15.0, 1.0],
	&"city_sushi_yell": [SUSHI_YELL, -15.0, 1.0],
	&"van_departure": [VAN_DEPARTURE, -12.0, 1.0],
	&"pistol": [PISTOL_SHOT, -9.0, 1.0],
	&"smg": [MP5_SHOT, -12.0, 1.0],
	&"m4a4": [M4A4_SHOT, -10.0, 1.0],
	&"ak47": [AK47_SHOT, -10.0, 1.0],
	&"shotgun": [SHOTGUN_SHOT, -8.0, 1.0],
	&"awp": [AWP_SHOT, -7.0, 1.0],
	&"reload_mag_out": [RELOAD_MAG_OUT, -18.0, 1.0],
	&"reload_mag_in": [RELOAD_MAG_IN, -18.0, 1.0],
	&"reload_charge": [RELOAD_CHARGE, -18.0, 1.0],
	&"explosion": [EXPLOSION, -10.0, 1.0],
	&"impact": [IMPACT, -16.0, 1.0],
	&"hit": [HIT, -16.0, 1.0],
	&"open": [OPEN, -18.0, 1.0],
	&"close": [CLOSE, -18.0, 1.0],
	&"equip": [EQUIP, -16.0, 1.0],
	&"pickup": [PICKUP, -16.0, 1.0],
	&"drop": [DROP, -16.0, 1.0],
	&"elevator_ding": [PICKUP, -10.0, 1.4],
	&"door_open": [DOOR_OPEN, -12.0, 1.0],
	&"door_close": [DOOR_CLOSE, -12.0, 1.0],
	&"door_locked": [DOOR_LOCKED, -9.0, 0.8],
	&"door_unlock": [DOOR_UNLOCK, -9.0, 1.0],
	&"key_pickup": [KEY_PICKUP, -12.0, 1.2],
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
