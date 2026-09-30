class_name KaabaPrayer
extends Node3D
## Players pray near the Kaaba to earn blessings. Each adds 200% of base slot
## win chance; they stack up to MAX_BLESSINGS and a win spends
## them all. The server owns both dictionaries; clients only request a prayer.

const MAX_BLESSINGS := 5
const PRAYER_S := 6.0
## Range around player height at the Kaaba; its walls are 2.25 m out.
const USE_RANGE := 5.5

## peer id -> blessings earned.
@export var blessings: Dictionary = {}
## peer id -> true while that player is mid-prayer.
@export var praying: Dictionary = {}

var _timers: Dictionary = {}
var _chant: AudioStream

@onready var _entity: NetworkedInteraction = $NetworkedEntity

@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"kaaba_prayer")
	multiplayer.peer_disconnected.connect(_forget)
	_entity.interaction_range = USE_RANGE
	_entity.register_use(can_use, _begin_prayer)
	_entity.session_reset.connect(_on_mode_changed)
	_entity.event_received.connect(_on_event)
	_connect_combat.call_deferred()


func interaction_text() -> String:
	var count := blessings_for(multiplayer.get_unique_id())
	if count >= MAX_BLESSINGS:
		return "Your blessings are full (%d/%d) — try the slots" % [count, MAX_BLESSINGS]
	return "Pray (+200%% slot luck; blessings %d/%d)" % [count, MAX_BLESSINGS]


func can_use(player: Player) -> bool:
	var peer := player.get_multiplayer_authority()
	return _in_range(player) and not praying.has(peer) and blessings_for(peer) < MAX_BLESSINGS


func use() -> void:
	_entity.request_use()


func blessings_for(peer_id: int) -> int:
	return int(blessings.get(peer_id, 0))


## Server-only: a slot spin won, so the prayers were answered.
func consume(peer_id: int) -> void:
	if multiplayer.is_server() and blessings.has(peer_id):
		var next := blessings.duplicate()
		next.erase(peer_id)
		blessings = next


@rpc("any_peer", "call_local", "reliable")
func request_pray() -> void:
	_entity.receive_legacy_action(&"use")


func _begin_prayer(player: Player) -> bool:
	var peer_id := player.get_multiplayer_authority()
	var next := praying.duplicate()
	next[peer_id] = true
	praying = next
	_timers[peer_id] = 0.0
	_entity.send_event(&"prayer")
	return true


func _process(delta: float) -> void:
	if multiplayer.is_server() and not _timers.is_empty():
		_advance(delta)


func _advance(delta: float) -> void:
	if not multiplayer.is_server():
		return
	for peer_id: int in _timers.keys():
		var player := _player_for_peer(peer_id)
		if player == null or not _in_range(player):
			_stop(peer_id)
			continue
		_timers[peer_id] = float(_timers[peer_id]) + delta
		if float(_timers[peer_id]) >= PRAYER_S:
			_stop(peer_id)
			var next := blessings.duplicate()
			next[peer_id] = mini(blessings_for(peer_id) + 1, MAX_BLESSINGS)
			blessings = next


func _in_range(player: Player) -> bool:
	return _entity.in_range(player)


func _stop(peer_id: int) -> void:
	_timers.erase(peer_id)
	if praying.has(peer_id):
		var next := praying.duplicate()
		next.erase(peer_id)
		praying = next


## An event, not state: late joiners don't hear old prayers.
func _on_event(event: StringName, _payload: Dictionary) -> void:
	if event == &"prayer":
		play_prayer()


func play_prayer() -> void:
	if Network.mode == Network.Mode.SERVER:
		return
	if _chant == null:
		_chant = KaabaChant.takbir()
	if not _audio.playing:
		_audio.stream = _chant
		_audio.play()


func _forget(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_stop(peer_id)
	consume(peer_id)


func _player_for_peer(peer_id: int) -> Player:
	return _entity.player_for_peer(peer_id)


func _connect_combat() -> void:
	var combat := get_tree().get_first_node_in_group(&"combat") as Combat
	if combat != null:
		combat.player_died.connect(_on_death)


func _on_death(peer_id: int, _attacker: int) -> void:
	if multiplayer.is_server():
		_stop(peer_id)


func _on_mode_changed(_mode: Network.Mode) -> void:
	blessings = {}
	praying = {}
	_timers.clear()
	_audio.stop()
