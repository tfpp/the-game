class_name KaabaPrayer
extends Node3D
## Players pray near the Kaaba to earn blessings. Each blessing gives a losing slot
## spin one more roll of the reels; they stack up to MAX_BLESSINGS and a win spends
## them all. The server owns both dictionaries; clients only request a prayer.

const MAX_BLESSINGS := 5
const PRAYER_S := 6.0
## Horizontal distance from the Kaaba's centre; its walls are 2.25 m out.
const USE_RANGE := 5.5

## peer id -> blessings earned.
@export var blessings: Dictionary = {}
## peer id -> true while that player is mid-prayer.
@export var praying: Dictionary = {}

var _timers: Dictionary = {}
var _chant: AudioStream

@onready var entity: NetworkedInteraction = $NetworkedEntity

@onready var _audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"kaaba_prayer")
	multiplayer.peer_disconnected.connect(_forget)
	Network.mode_changed.connect(_on_mode_changed)
	entity.register_use(can_use, _start_prayer)
	entity.event_received.connect(_on_effect)


func interaction_text() -> String:
	var count := blessings_for(multiplayer.get_unique_id())
	if count >= MAX_BLESSINGS:
		return "Your blessings are full (%d/%d) — try the slots" % [count, MAX_BLESSINGS]
	return "Pray at the Kaaba (blessings %d/%d)" % [count, MAX_BLESSINGS]


func can_use(player: Player) -> bool:
	var offset := player.net_position - global_position
	offset.y = 0.0
	return (
		offset.length() <= USE_RANGE
		and not praying.has(player.get_multiplayer_authority())
		and blessings_for(player.get_multiplayer_authority()) < MAX_BLESSINGS
	)


func use() -> void:
	entity.request_use()


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
	entity.receive_legacy_action(&"use")


func _start_prayer(player: Player) -> bool:
	var peer_id := player.get_multiplayer_authority()
	var next := praying.duplicate()
	next[peer_id] = true
	praying = next
	_timers[peer_id] = 0.0
	play_prayer.rpc()
	return true


func _process(delta: float) -> void:
	if multiplayer.is_server() and not _timers.is_empty():
		_advance(delta)


func _advance(delta: float) -> void:
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
			var eye := player.movement.eye_height_m() - player.movement.hull_height_m() * 0.5
			var look := Basis.from_euler(Vector3(player.net_pitch, player.net_yaw, 0))
			var at := player.net_position + Vector3.UP * eye + look * Vector3.FORWARD * 0.9
			entity.send_event(&"completed", {"position": at})


func _in_range(player: Player) -> bool:
	var offset := player.net_position - global_position
	offset.y = 0.0
	return offset.length() <= USE_RANGE


func _stop(peer_id: int) -> void:
	_timers.erase(peer_id)
	if praying.has(peer_id):
		var next := praying.duplicate()
		next.erase(peer_id)
		praying = next


## An event, not state: late joiners don't hear old prayers.
@rpc("authority", "call_local", "reliable")
func play_prayer() -> void:
	if Network.mode == Network.Mode.SERVER:
		return
	if _chant == null:
		_chant = KaabaChant.takbir()
	if not _audio.playing:
		_audio.stream = _chant
		_audio.play()


func _forget(peer_id: int) -> void:
	_stop(peer_id)
	consume(peer_id)


func _player_for_peer(peer_id: int) -> Player:
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var player := node as Player
		if player != null and player.get_multiplayer_authority() == peer_id:
			return player
	return null


func _on_mode_changed(_mode: Network.Mode) -> void:
	blessings = {}
	praying = {}
	_timers.clear()
	for child: Node in get_children():
		if child is BlessingEffect:
			child.queue_free()


## Called only after a paid slot spin succeeds; no effect for rejected wagers.
func show_blessed_spin(at: Vector3) -> void:
	entity.send_event(&"gamble", {"position": at})


func _on_effect(event: StringName, payload: Dictionary) -> void:
	if event not in [&"completed", &"gamble"] or Network.mode == Network.Mode.SERVER:
		return
	var effect := BlessingEffect.new()
	add_child(effect)
	effect.global_position = payload["position"]
	effect.build(event == &"gamble")
