class_name MariachiBand
extends Node3D
## Mariachi Corona de Oro: five musicians on a little stage on the casino's north
## promenade, playing traditional songs on loop. The server owns which song is on
## (`net_song`) and bumps `net_take` every time a song starts, so every peer starts
## it together and late joiners pick up the current one. Players press Use near the
## stage to request the next song; the band also moves on by itself every
## `PLAYS_PER_SONG` loops. The music pauses while every musician is down.

const PLAYS_PER_SONG := 2
## Server-wide gap between accepted requests, so the band can't be spammed.
const REQUEST_COOLDOWN_S := 4.0
## Requests are taken from anywhere around the stage edge.
const REQUEST_RANGE := 4.6
const STREAMS: Array[AudioStream] = [
	preload("res://assets/mariachi_band/audio/la_cucaracha.wav"),
	preload("res://assets/mariachi_band/audio/jarabe_tapatio.wav"),
]

@export var net_song := 0:
	set(value):
		net_song = posmod(value, MariachiSongs.count())
		if is_node_ready():
			_present()
## Counts song starts; a change restarts playback on every peer.
@export var net_take := 0:
	set(value):
		net_take = value
		# Deferred so a song change replicated alongside it is applied first.
		if is_node_ready() and not _take_pending:
			_take_pending = true
			_start_take.call_deferred()

## Server: seconds into the current take.
var elapsed := 0.0
## Local fallback clock for animation while no audio plays (dedicated server, muted).
var _clock := 0.0
var _take_pending := false
var _silenced := false

@onready var _entity: NetworkedInteraction = $NetworkedEntity
@onready var _audio: AudioStreamPlayer3D = $Audio
@onready var _now_playing: Label3D = $NowPlaying
@onready var _musicians: Node3D = $Musicians


func _ready() -> void:
	add_to_group(&"interactables")
	_entity.interaction_range = REQUEST_RANGE
	_entity.register_use(can_use, _request, REQUEST_COOLDOWN_S)
	_entity.session_reset.connect(_reset_session)
	if AudioServer.get_bus_index(GameAudio.BUS) >= 0:
		_audio.bus = GameAudio.BUS
	_present()
	_start_take()


func _process(delta: float) -> void:
	_clock += delta
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		elapsed += delta
		if elapsed >= MariachiSongs.duration(net_song) * PLAYS_PER_SONG:
			advance()
	var asleep := not band_awake()
	if asleep != _silenced:
		_silenced = asleep
		_audio.stream_paused = asleep


func interaction_text() -> String:
	return "Request a song (next: %s)" % MariachiSongs.song_name(net_song + 1)


func can_use(player: Player) -> bool:
	return _entity.in_range(player) and band_awake()


func use() -> void:
	_entity.request_use()


## Server: strike up the next song from the top.
func advance() -> void:
	if not _entity.is_authority():
		return
	net_song = net_song + 1
	elapsed = 0.0
	net_take = net_take + 1


## True while at least one musician is standing (StationaryPatron `net_alive`).
func band_awake() -> bool:
	if not is_node_ready():
		return true
	for musician: Node in _musicians.get_children():
		if bool(musician.get("net_alive")):
			return true
	return false


## Only peers with speakers play the music: not the dedicated server or headless runs.
static func audible() -> bool:
	return Network.mode != Network.Mode.SERVER and DisplayServer.get_name() != "headless"


## True while the music is paused because every musician is down.
func is_silenced() -> bool:
	return _silenced


## True while this peer is actually hearing the band.
func is_playing() -> bool:
	return is_node_ready() and _audio.playing and not _silenced


## Seconds into the current song, following the audio when it plays.
func song_time() -> float:
	if is_playing():
		return _audio.get_playback_position() + AudioServer.get_time_since_last_mix()
	return _clock


func _request(_player: Player) -> bool:
	advance()
	return true


func _present() -> void:
	_now_playing.text = "Now playing: %s" % MariachiSongs.song_name(net_song)


func _start_take() -> void:
	_take_pending = false
	_clock = 0.0
	_audio.stream = STREAMS[net_song]
	if audible():
		_audio.play()
	_silenced = not band_awake()
	_audio.stream_paused = _silenced


func _reset_session(_mode: Network.Mode) -> void:
	net_song = 0
	elapsed = 0.0
	net_take = net_take + 1
