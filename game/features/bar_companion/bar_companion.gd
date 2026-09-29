class_name BarCompanion
extends Node3D
## Owns every player's charisma, intoxication and lucky-night buff on the server.
## The bartender, Vivienne and the slot machines call into it; clients only read
## the replicated `stats` summary.

## Seconds between refreshes of the replicated summary.
const PUBLISH_S := 0.5

## peer id -> [charisma, intoxication (whole drinks), lucky seconds left]. Replicated.
@export var stats: Dictionary = {}

## peer id -> {"win": float, "intox": float, "luck": float}. Server only.
var _state: Dictionary = {}
var _publish_in := 0.0


func _ready() -> void:
	add_to_group(&"bar_companion")
	var entity := $NetworkedEntity as NetworkedEntity
	entity.session_reset.connect(_reset)
	multiplayer.peer_disconnected.connect(forget)


func charisma_for(peer: int) -> int:
	var row: Array = stats.get(peer, [])
	return int(row[0]) if row.size() == 3 else 0


func intoxication_for(peer: int) -> int:
	var row: Array = stats.get(peer, [])
	return int(row[1]) if row.size() == 3 else 0


func luck_seconds_for(peer: int) -> int:
	var row: Array = stats.get(peer, [])
	return int(row[2]) if row.size() == 3 else 0


## Extra slot reel rolls; read on the server by features/slot_machine.
func rerolls_for(peer: int) -> int:
	if multiplayer.is_server() and _state.has(peer):
		return CharmMath.LUCK_REROLLS if float(_state[peer]["luck"]) > 0.0 else 0
	return CharmMath.LUCK_REROLLS if luck_seconds_for(peer) > 0 else 0


func price_for(peer: int) -> int:
	return CharmMath.price_cents(_server_charisma(peer))


## Server-only: a casino win makes the winner briefly more charming.
func note_win(peer: int) -> void:
	if multiplayer.is_server():
		var row := _row(peer)
		row["win"] = minf(float(row["win"]) + CharmMath.WIN_CHARISMA, CharmMath.MAX_WIN_CHARISMA)
		_publish()


## Server-only: the bartender served `peer` a drink.
func add_drink(peer: int) -> void:
	if multiplayer.is_server():
		var row := _row(peer)
		row["intox"] = minf(float(row["intox"]) + 1.0, CharmMath.MAX_INTOXICATION)
		_publish()


## Server-only: Vivienne was walked to `peer`'s room.
func grant_luck(peer: int) -> void:
	if multiplayer.is_server():
		_row(peer)["luck"] = CharmMath.LUCK_S
		_publish()


func forget(peer: int) -> void:
	if multiplayer.is_server() and _state.has(peer):
		_state.erase(peer)
		_publish()


func _server_charisma(peer: int) -> int:
	if not _state.has(peer):
		return 0
	return CharmMath.charisma(float(_state[peer]["win"]), float(_state[peer]["intox"]))


func _row(peer: int) -> Dictionary:
	if not _state.has(peer):
		_state[peer] = {"win": 0.0, "intox": 0.0, "luck": 0.0}
	return _state[peer]


func _process(delta: float) -> void:
	if not multiplayer.is_server() or _state.is_empty():
		return
	advance(delta)


## Server-only: fades charisma, sobers players up and runs down lucky nights.
func advance(delta: float) -> void:
	for peer: int in _state.keys():
		var row: Dictionary = _state[peer]
		row["win"] = CharmMath.decay(float(row["win"]), delta, CharmMath.WIN_FADE_S)
		row["intox"] = CharmMath.decay(float(row["intox"]), delta, CharmMath.SOBER_S)
		row["luck"] = maxf(float(row["luck"]) - delta, 0.0)
		if is_zero_approx(row["win"]) and is_zero_approx(row["intox"]) and row["luck"] <= 0.0:
			_state.erase(peer)
	_publish_in -= delta
	if _publish_in <= 0.0:
		_publish()


func _publish() -> void:
	_publish_in = PUBLISH_S
	var next := {}
	for peer: int in _state:
		var row: Dictionary = _state[peer]
		next[peer] = [_server_charisma(peer), ceili(float(row["intox"])), ceili(float(row["luck"]))]
	if next != stats:
		stats = next


func _reset(_mode: Network.Mode) -> void:
	_state.clear()
	stats = {}
